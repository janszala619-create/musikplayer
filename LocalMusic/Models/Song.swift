import Foundation
import SwiftData

@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var fileName: String
    // Optional/defaulted additions permit SwiftData's lightweight store migration.
    var originalFileName: String? = nil
    var metadataVersion: Int = 0
    @Attribute(.externalStorage) var artworkData: Data?
    var importedAt: Date

    // Protect the first rendered frame, before the asynchronous legacy repair finishes.
    var displayTitle: String {
        MetadataFallback.resolve(title: title, originalFileName: originalFileName).title
    }

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        fileName: String,
        originalFileName: String? = nil,
        metadataVersion: Int = 0,
        artworkData: Data? = nil,
        importedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileName = fileName
        self.originalFileName = originalFileName
        self.metadataVersion = metadataVersion
        self.artworkData = artworkData
        self.importedAt = importedAt
    }
}
