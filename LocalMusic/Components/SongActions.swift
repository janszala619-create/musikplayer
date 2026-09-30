import SwiftUI
import SwiftData

private enum SongSheet: String, Identifiable {
    case metadata, playlist
    var id: String { rawValue }
}

@MainActor
struct SongActions: View {
    let song: Song
    @Environment(\.modelContext) private var context
    @State private var sheet: SongSheet?
    @State private var error: String?

    var body: some View {
        Menu {
            Button(song.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen",
                   systemImage: song.isFavorite ? "heart.slash" : "heart") {
                do { try LibraryStore.toggleFavorite(song, in: context) }
                catch { self.error = error.localizedDescription }
            }
            Button("Zu Playlist hinzufügen", systemImage: "text.badge.plus") { sheet = .playlist }
            Button("Titel und Künstler bearbeiten", systemImage: "pencil") { sheet = .metadata }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Optionen für \(song.displayTitle)")
        .sheet(item: $sheet) { destination in
            switch destination {
            case .metadata: SongMetadataEditor(song: song)
            case .playlist: AddToPlaylistView(song: song)
            }
        }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
}

@MainActor
struct SongMetadataEditor: View {
    let song: Song
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var error: String?

    init(song: Song) {
        self.song = song
        _title = State(initialValue: song.displayTitle)
        _artist = State(initialValue: song.artist == MetadataFallback.unknownArtist ? "" : song.artist)
        _album = State(initialValue: song.album == MetadataFallback.unknownAlbum ? "" : song.album)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Songdaten") {
                    TextField("Titel", text: $title).accessibilityIdentifier("song.edit.title")
                    TextField("Künstler", text: $artist).accessibilityIdentifier("song.edit.artist")
                    TextField("Album (optional)", text: $album)
                }
                Section {
                    if let original = song.originalFileName {
                        LabeledContent("Originaldatei", value: original)
                    }
                } footer: {
                    Text("Die Angaben werden in Audyn gespeichert. Deine Audiodatei behält ihren ursprünglichen Namen.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Song bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        do {
                            try LibraryStore.update(song, title: title, artist: artist, album: album, in: context)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

@MainActor
struct AddToPlaylistView: View {
    let song: Song
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Neue Playlist") {
                    TextField("Playlist-Name", text: $name)
                    Button("Erstellen und Song hinzufügen", systemImage: "plus") {
                        do {
                            try LibraryStore.createPlaylist(name: name, songs: [song], in: context)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Deine Playlists") {
                    if playlists.isEmpty { Text("Noch keine Playlists").foregroundStyle(.secondary) }
                    ForEach(playlists) { playlist in
                        Button {
                            do {
                                playlist.add([song])
                                try LibraryStore.save(context)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        } label: {
                            HStack {
                                Text(playlist.name)
                                Spacer()
                                if playlist.songIDs.contains(song.id) { Image(systemName: "checkmark") }
                            }
                        }
                        .disabled(playlist.songIDs.contains(song.id))
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Zu Playlist hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
