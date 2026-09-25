import Foundation
import SwiftData

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
    private static let supportedExtensions: Set<String> = ["m4a", "mp3", "mp4", "m4v", "aac", "wav"]

    static func importFile(from sourceURL: URL, into context: ModelContext) async throws {
        guard supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw MusicImportError.unsupportedFile
        }

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

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
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        do {
            let metadata = try await MetadataService.read(from: destinationURL)
            let song = Song(
                id: id,
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                duration: metadata.duration,
                fileName: destinationName,
                artworkData: metadata.artworkData
            )
            context.insert(song)
            try context.save()
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
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
