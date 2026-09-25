import AVFoundation
import Foundation

struct ExtractedMetadata: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let artworkData: Data?
}

enum MetadataService {
    static func read(from url: URL) async throws -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.load(.commonMetadata)
        let duration = try await asset.load(.duration)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent

        func value(for key: AVMetadataKey) async throws -> String? {
            guard let item = metadata.first(where: { $0.commonKey == key }) else {
                return nil
            }
            return try await item.load(.stringValue)
        }

        let artwork: Data?
        if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }) {
            artwork = try await item.load(.dataValue)
        } else {
            artwork = nil
        }
        return ExtractedMetadata(
            title: try await value(for: .commonKeyTitle) ?? fallbackTitle,
            artist: try await value(for: .commonKeyArtist) ?? "Unbekannter Künstler",
            album: try await value(for: .commonKeyAlbumName) ?? "Unbekanntes Album",
            duration: duration.isNumeric ? duration.seconds : 0,
            artworkData: artwork
        )
    }
}

private extension CMTime {
    var isNumeric: Bool { !seconds.isNaN && !seconds.isInfinite }
}
