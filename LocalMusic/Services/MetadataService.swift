import AVFoundation
import Foundation
import UIKit

struct ExtractedMetadata: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkData: Data?
}

struct ResolvedSongText: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
}

enum MetadataFallback {
    static let unknownTitle = "Unbekannter Titel"
    static let unknownArtist = "Unbekannter Künstler"
    static let unknownAlbum = "Unbekanntes Album"

    static func isUUIDLike(_ value: String) -> Bool {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = (candidate as NSString).deletingPathExtension
        if candidate.lowercased().hasPrefix("urn:uuid:") {
            candidate = String(candidate.dropFirst(9))
        }
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        return candidate.range(
            of: "^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{32})$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func usableText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isUUIDLike(trimmed) else { return nil }
        return trimmed
    }

    static func originalFileNameText(_ fileName: String?) -> (title: String?, artist: String?) {
        guard let fileName = usableText(fileName),
              let stem = usableText((fileName as NSString).deletingPathExtension) else {
            return (nil, nil)
        }
        // Split at the first meaningful exact separator, preserving other hyphens.
        var searchStart = stem.startIndex
        while let separator = stem.range(of: " - ", range: searchStart..<stem.endIndex) {
            let artist = usableText(String(stem[..<separator.lowerBound]))
            let title = usableText(String(stem[separator.upperBound...]))
            if let artist, let title { return (title, artist) }
            searchStart = separator.upperBound
        }
        return (stem, nil)
    }

    static func resolve(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        originalFileName: String?
    ) -> ResolvedSongText {
        let fileText = originalFileNameText(originalFileName)
        return ResolvedSongText(
            title: usableText(title) ?? fileText.title ?? unknownTitle,
            artist: usableText(artist) ?? fileText.artist ?? unknownArtist,
            album: usableText(album) ?? unknownAlbum
        )
    }
}

enum MetadataService {
    static func read(from url: URL, originalFileName: String?) async throws -> ExtractedMetadata {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // Optional tag failures must not fail a usable audio import.
        guard try await asset.load(.isPlayable),
              !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw MusicImportError.unsupportedFile
        }
        var metadata = (try? await asset.load(.commonMetadata)) ?? []
        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        for format in formats {
            if let items = try? await asset.loadMetadata(for: format) {
                metadata.append(contentsOf: items)
            }
        }
        let text = await readText(from: metadata, originalFileName: originalFileName)
        let artwork = await readArtwork(from: metadata)
        let duration = try? await asset.load(.duration)
        let seconds = duration?.seconds ?? 0
        return ExtractedMetadata(
            title: text.title,
            artist: text.artist,
            album: text.album,
            duration: seconds.isFinite ? max(0, seconds) : 0,
            artworkData: artwork
        )
    }

    static func readText(from items: [AVMetadataItem], originalFileName: String?) async -> ResolvedSongText {
        let title = await firstUsableString(in: items, key: .commonKeyTitle, identifiers: [
            .id3MetadataTitleDescription, .iTunesMetadataSongName,
            .quickTimeMetadataTitle, .quickTimeUserDataFullName
        ])
        let artist = await firstUsableString(in: items, key: .commonKeyArtist, identifiers: [
            .id3MetadataLeadPerformer, .iTunesMetadataArtist,
            .quickTimeMetadataArtist, .quickTimeUserDataArtist
        ])
        let album = await firstUsableString(in: items, key: .commonKeyAlbumName, identifiers: [
            .id3MetadataAlbumTitle, .iTunesMetadataAlbum,
            .quickTimeMetadataAlbum, .quickTimeUserDataAlbum
        ])
        return MetadataFallback.resolve(title: title, artist: artist, album: album, originalFileName: originalFileName)
    }

    private static func firstUsableString(
        in items: [AVMetadataItem], key: AVMetadataKey, identifiers: [AVMetadataIdentifier]
    ) async -> String? {
        for item in matchingItems(in: items, key: key, identifiers: identifiers) {
            // A bad first candidate must not hide a later valid tag.
            if let value = try? await item.load(.stringValue),
               let usable = MetadataFallback.usableText(value) {
                return usable
            }
        }
        return nil
    }

    static func readArtwork(from items: [AVMetadataItem]) async -> Data? {
        for item in matchingItems(in: items, key: .commonKeyArtwork, identifiers: [
            .id3MetadataAttachedPicture, .iTunesMetadataCoverArt, .quickTimeMetadataArtwork
        ]) {
            if let data = try? await item.load(.dataValue), !data.isEmpty, UIImage(data: data) != nil {
                return data
            }
        }
        return nil
    }

    private static func matchingItems(
        in items: [AVMetadataItem], key: AVMetadataKey, identifiers: [AVMetadataIdentifier]
    ) -> [AVMetadataItem] {
        let common = items.filter { $0.commonKey == key }
        let specific = identifiers.flatMap { identifier in
            items.filter { $0.commonKey != key && $0.identifier == identifier }
        }
        return common + specific
    }
}
