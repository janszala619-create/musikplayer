import SwiftUI
import SwiftData

struct PlaylistRow: View {
    let playlist: Playlist
    let songs: [Song]
    var body: some View {
        HStack(spacing: 14) {
            CollectionArtwork(songs: songs, size: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.name).font(.headline).lineLimit(2)
                Text("Playlist · \(songs.count) Songs · \(playbackTime(songs.reduce(0) { $0 + $1.duration }))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

struct CollectionArtwork: View {
    let songs: [Song]
    var symbol = "music.note.list"
    var size: CGFloat = 120
    private var covers: [Data] { Array(songs.compactMap(\.artworkData).prefix(4)) }

    var body: some View {
        Group {
            if covers.count >= 4 {
                VStack(spacing: 2) {
                    HStack(spacing: 2) { tile(0); tile(1) }
                    HStack(spacing: 2) { tile(2); tile(3) }
                }
            } else if let data = covers.first {
                ArtworkView(data: data, size: size)
            } else {
                ZStack {
                    LinearGradient(colors: symbol == "heart.fill" ? [.indigo, .mint] : [.teal, .cyan.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: symbol).font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
    private func tile(_ index: Int) -> some View { ArtworkView(data: covers[index], size: (size - 2) / 2) }
}

@MainActor
struct PlaylistDetailView: View {
    let playlist: Playlist
    @Environment(\.modelContext) private var context
    @Environment(AudioPlayerService.self) private var player
    @Query private var library: [Song]
    @State private var query = ""
    @State private var sheet: PlaylistDetailSheet?
    @State private var error: String?
    private var songs: [Song] { playlist.songs(in: library) }
    private var visibleSongs: [Song] {
        songs.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 18) {
                    CollectionArtwork(songs: songs, size: 180)
                    Text(playlist.name).font(.title.bold()).multilineTextAlignment(.center)
                    Text("\(songs.count) Songs · \(playbackTime(songs.reduce(0) { $0 + $1.duration }))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    CollectionPlaybackControls(songs: songs)
                    Button("Songs hinzufügen", systemImage: "plus") { sheet = .songs }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .listRowBackground(Color.clear)
            Section {
                ForEach(visibleSongs) { song in PlaySongButton(song: song, queue: songs) }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { visibleSongs[$0].id })
                        playlist.songIDs.removeAll { ids.contains($0) }
                        save()
                    }
                    .onMove { offsets, destination in
                        var ordered = songs.map(\.id)
                        ordered.move(fromOffsets: offsets, toOffset: destination)
                        playlist.songIDs = ordered
                        save()
                    }
                    .moveDisabled(!query.isEmpty)
            } footer: {
                if songs.isEmpty { Text("Füge Songs hinzu, um deine Playlist zu füllen.") }
                else { Text("Mit Bearbeiten kannst du Songs verschieben oder aus dieser Playlist entfernen.") }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Playlist durchsuchen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(!query.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Playlist umbenennen", systemImage: "pencil") { sheet = .rename }
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .songs: PlaylistSongPicker(playlist: playlist)
            case .rename: PlaylistEditorView(playlist: playlist)
            }
        }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
    private func save() {
        do { try LibraryStore.save(context) } catch { self.error = error.localizedDescription }
    }
}

private enum PlaylistDetailSheet: String, Identifiable {
    case songs, rename
    var id: String { rawValue }
}

@MainActor
struct CollectionPlaybackControls: View {
    let songs: [Song]
    @Environment(AudioPlayerService.self) private var player
    var body: some View {
        HStack(spacing: 16) {
            Button { player.playAll(songs, shuffled: true) } label: {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button { player.playAll(songs) } label: {
                Label("Abspielen", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(songs.isEmpty)
    }
}

@MainActor
struct SongCollectionView: View {
    let title: String
    var favoritesOnly = false
    @Query(sort: \Song.importedAt, order: .reverse) private var library: [Song]
    @State private var query = ""
    private var songs: [Song] { library.filter { !favoritesOnly || $0.isFavorite } }
    private var results: [Song] {
        songs.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section {
                VStack(spacing: 18) {
                    CollectionArtwork(songs: [], symbol: favoritesOnly ? "heart.fill" : "music.note.list", size: 160)
                    Text("\(songs.count) Songs").foregroundStyle(.secondary)
                    CollectionPlaybackControls(songs: songs)
                }
                .frame(maxWidth: .infinity).padding(.vertical)
            }
            .listRowBackground(Color.clear)
            Section {
                ForEach(results) { song in PlaySongButton(song: song, queue: songs) }
            } footer: {
                if songs.isEmpty { Text("Markiere Songs über das Herz im Player oder das Song-Menü als Favoriten.") }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .searchable(text: $query, prompt: "Titel oder Künstler suchen")
    }
}

@MainActor
struct PlaylistEditorView: View {
    var playlist: Playlist?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: String?

    init(playlist: Playlist? = nil) {
        self.playlist = playlist
        _name = State(initialValue: playlist?.name ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist-Name") { TextField("Zum Beispiel: Unterwegs", text: $name) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(playlist == nil ? "Playlist erstellen" : "Playlist umbenennen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        do {
                            if let playlist {
                                playlist.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                try LibraryStore.save(context)
                            } else { try LibraryStore.createPlaylist(name: name, in: context) }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
struct PlaylistSongPicker: View {
    let playlist: Playlist
    @Query(sort: \Song.importedAt, order: .reverse) private var songs: [Song]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    @State private var query = ""
    @State private var error: String?
    private var results: [Song] {
        songs.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { song in
                    let added = playlist.songIDs.contains(song.id)
                    Button {
                        if selected.contains(song.id) { selected.remove(song.id) }
                        else { selected.insert(song.id) }
                    } label: {
                        HStack {
                            SongRow(song: song)
                            Image(systemName: added || selected.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(added ? Color.secondary : Color.mint)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(added)
                    .accessibilityLabel("\(song.displayTitle), \(added ? "bereits enthalten" : selected.contains(song.id) ? "ausgewählt" : "auswählen")")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .overlay { if songs.isEmpty { ContentUnavailableView("Noch keine Songs", systemImage: "music.note", description: Text("Importiere zuerst Musik in der Bibliothek.")) } }
            .navigationTitle("Songs hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Songs suchen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen (\(selected.count))") {
                        do {
                            playlist.add(songs.filter { selected.contains($0.id) })
                            try LibraryStore.save(context)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
