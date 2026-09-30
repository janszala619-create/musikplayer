import Foundation
import SwiftData

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var songIDs: [UUID] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, songIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        var seen = Set<UUID>()
        self.songIDs = songIDs.filter { seen.insert($0).inserted }
    }

    func songs(in library: [Song]) -> [Song] {
        let indexed = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        return songIDs.compactMap { indexed[$0] }
    }

    func add(_ songs: [Song]) {
        var existing = Set(songIDs)
        for song in songs where existing.insert(song.id).inserted {
            songIDs.append(song.id)
        }
    }
}
