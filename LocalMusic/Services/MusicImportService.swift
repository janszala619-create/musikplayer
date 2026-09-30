import Foundation
import SwiftData
import OSLog

enum MusicImportError: LocalizedError {
    case unsupportedFile
    case cannotAccessFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Dieses Dateiformat wird noch nicht unterstützt. Bitte verwende MP3, M4A oder eine kompatible MP4-Datei."
        case .cannotAccessFile:
            "Die ausgewählte Datei konnte nicht gelesen werden."
        }
    }
}

@MainActor
enum MusicImportService {
    static let currentMetadataVersion = 1
    private static let logger = Logger(subsystem: "com.localmusic.app", category: "Import")
    private static let supportedExtensions: Set<String> = ["m4a", "mp3", "mp4", "m4v", "aac", "wav"]

    static func importFile(from sourceURL: URL, into context: ModelContext) async throws {
        guard supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw MusicImportError.unsupportedFile
        }

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        // Capture provenance before copying/renaming while the source is accessible.
        let originalURL = sourceURL
        let resourceValues = try? originalURL.resourceValues(forKeys: [.nameKey, .localizedNameKey])
        let originalFileName = sourceFileName(
            url: originalURL,
            resourceName: resourceValues?.name,
            localizedName: resourceValues?.localizedName
        )

        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw MusicImportError.cannotAccessFile
        }

        let folder = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("ImportedAudio", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let id = UUID()
        let destinationName = "\(id.uuidString).\(sourceURL.pathExtension.lowercased())"
        let destinationURL = folder.appendingPathComponent(destinationName)
        try fileManager.copyItem(at: originalURL, to: destinationURL)

        do {
            let metadata = try await MetadataService.read(from: destinationURL, originalFileName: originalFileName)
            let song = Song(
                id: id,
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                duration: metadata.duration,
                fileName: destinationName,
                originalFileName: originalFileName,
                metadataVersion: currentMetadataVersion,
                artworkData: metadata.artworkData
            )
            context.insert(song)
            do {
                try context.save()
            } catch {
                context.delete(song)
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    static func repairLegacySongs(in context: ModelContext) async {
        do {
            let pending = try context.fetch(FetchDescriptor<Song>()).filter {
                $0.metadataVersion < currentMetadataVersion || MetadataFallback.isUUIDLike($0.title)
            }
            for song in pending {
                // A legacy storage name can be an original name only if it isn't a UUID.
                let original = MetadataFallback.usableText(song.originalFileName)
                    ?? MetadataFallback.usableText(song.fileName)
                let metadata: ExtractedMetadata?
                if let url = try? fileURL(for: song) {
                    metadata = try? await MetadataService.read(from: url, originalFileName: original)
                } else {
                    metadata = nil
                }
                applyLegacyRepair(to: song, metadata: metadata, originalFileName: original)
                if song.title == MetadataFallback.unknownTitle {
                    logger.notice("Original title unavailable for song \(song.id.uuidString, privacy: .public); reimport required.")
                }
            }
            if !pending.isEmpty { try context.save() }
        } catch {
            logger.error("Library metadata repair failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func sourceFileName(url: URL, resourceName: String?, localizedName: String?) -> String {
        // A file provider can expose a temporary UUID URL while retaining a
        // human-readable resource name. Use only names supplied by the source.
        for candidate in [url.lastPathComponent, resourceName, localizedName] {
            if let name = MetadataFallback.usableText(candidate),
               MetadataFallback.originalFileNameText(name).title != nil {
                return name
            }
        }
        // Keep actual provenance even if unusable; the title resolver rejects it.
        return url.lastPathComponent
    }

    static func applyLegacyRepair(to song: Song, metadata: ExtractedMetadata?, originalFileName: String?) {
        func existingValue(_ value: String, placeholder: String) -> String? {
            guard let usable = MetadataFallback.usableText(value), usable != placeholder else { return nil }
            return usable
        }
        let text = MetadataFallback.resolve(
            title: existingValue(song.title, placeholder: MetadataFallback.unknownTitle)
                ?? existingValue(metadata?.title ?? "", placeholder: MetadataFallback.unknownTitle),
            artist: existingValue(song.artist, placeholder: MetadataFallback.unknownArtist)
                ?? existingValue(metadata?.artist ?? "", placeholder: MetadataFallback.unknownArtist),
            album: existingValue(song.album, placeholder: MetadataFallback.unknownAlbum)
                ?? existingValue(metadata?.album ?? "", placeholder: MetadataFallback.unknownAlbum),
            originalFileName: originalFileName
        )
        song.title = text.title
        song.artist = text.artist
        song.album = text.album
        song.originalFileName = originalFileName
        if let metadata, metadata.duration > 0 { song.duration = metadata.duration }
        if let artwork = metadata?.artworkData { song.artworkData = artwork }
        song.metadataVersion = currentMetadataVersion
    }

    static func fileURL(for song: Song) throws -> URL {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("ImportedAudio", isDirectory: true)
        return folder.appendingPathComponent(song.fileName)
    }
}
