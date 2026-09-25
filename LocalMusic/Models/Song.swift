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
    @Attribute(.externalStorage) var artworkData: Data?
    var importedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        fileName: String,
        artworkData: Data? = nil,
        importedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileName = fileName
        self.artworkData = artworkData
        self.importedAt = importedAt
    }
}
