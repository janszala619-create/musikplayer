import Foundation
import SwiftData

@MainActor
enum LibraryStore {
    static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }

    static func update(_ song: Song, title: String, artist: String, album: String, in context: ModelContext) throws {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { throw LibraryEditError.emptyTitle }
        song.title = cleanedTitle
        let cleanedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        song.artist = cleanedArtist.isEmpty ? MetadataFallback.unknownArtist : cleanedArtist
        song.album = cleanedAlbum.isEmpty ? MetadataFallback.unknownAlbum : cleanedAlbum
        song.hasManualMetadata = true
        song.metadataVersion = MusicImportService.currentMetadataVersion
        try save(context)
    }

    @discardableResult
    static func createPlaylist(name: String, songs: [Song] = [], in context: ModelContext) throws -> Playlist {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw LibraryEditError.emptyPlaylistName }
        let playlist = Playlist(name: cleaned)
        playlist.add(songs)
        context.insert(playlist)
        try save(context)
        return playlist
    }

    static func toggleFavorite(_ song: Song, in context: ModelContext) throws {
        song.isFavorite.toggle()
        try save(context)
    }
}

enum LibraryEditError: LocalizedError {
    case emptyTitle, emptyPlaylistName
    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Bitte trage einen Titel ein."
        case .emptyPlaylistName: "Bitte gib deiner Playlist einen Namen."
        }
    }
}
