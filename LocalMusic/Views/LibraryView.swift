import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum LibraryFilter: String, CaseIterable {
    case playlists = "Playlists", songs = "Songs"
}

private enum LibrarySheet: Identifiable {
    case create
    var id: String { "create" }
}

@MainActor
struct LibraryView: View {
    @Environment(AudioPlayerService.self) private var player
    @Environment(\.modelContext) private var context
    @Query(sort: \Song.importedAt, order: .reverse) private var songs: [Song]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]
    @State private var filter = LibraryFilter.playlists
    @State private var query = ""
    @State private var sheet: LibrarySheet?
    @State private var isImporting = false
    @State private var busy = false
    @State private var error: String?
    @State private var deletingPlaylist: Playlist?
    @AppStorage("automaticCoverSearch") private var automaticCoverSearch = true

    private var filteredSongs: [Song] { songs.filter { matches($0.displayTitle) || matches($0.artist) } }
    private var filteredPlaylists: [Playlist] { playlists.filter { matches($0.name) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Button { isImporting = true } label: {
                            Label(busy ? "Import läuft …" : "Importieren", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(busy)
                        Button { sheet = .create } label: {
                            Label("Erstellen", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    Picker("Bibliothek anzeigen", selection: $filter) {
                        ForEach(LibraryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                if filter == .playlists {
                    Section {
                        NavigationLink {
                            SongCollectionView(title: "Deine Favoriten", favoritesOnly: true)
                        } label: {
                            HStack(spacing: 14) {
                                CollectionArtwork(songs: [], symbol: "heart.fill", size: 68)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Deine Favoriten").font(.headline)
                                    Text("\(songs.filter(\.isFavorite).count) Songs").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        ForEach(filteredPlaylists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                PlaylistRow(playlist: playlist, songs: playlist.songs(in: songs))
                            }
                            .swipeActions {
                                Button("Löschen", role: .destructive) { deletingPlaylist = playlist }
                            }
                        }
                    } header: {
                        Text("Deine Sammlungen")
                    } footer: {
                        if playlists.isEmpty {
                            Text("Erstelle deine erste Playlist und füge Songs aus deiner Bibliothek hinzu.")
                        }
                    }
                } else {
                    Section {
                        ForEach(filteredSongs) { song in
                            PlaySongButton(song: song, queue: filteredSongs)
                        }
                        .onDelete(perform: deleteSongs)
                    } header: {
                        HStack {
                            Text("\(filteredSongs.count) Songs")
                            Spacer()
                            Button("Alle abspielen", systemImage: "play.fill") { player.playAll(filteredSongs) }
                                .disabled(filteredSongs.isEmpty)
                        }
                    } footer: {
                        if songs.isEmpty { Text("Importiere Musik über die Dateien-App, um loszulegen.") }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Bibliothek")
            .searchable(text: $query, prompt: filter == .playlists ? "Playlists suchen" : "Titel oder Künstler suchen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Cover automatisch suchen", isOn: $automaticCoverSearch)
                    } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Bibliothek-Einstellungen")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text(appVersion).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("app.version")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Playlist erstellen", systemImage: "plus") { sheet = .create }
                }
            }
            .sheet(item: $sheet) { _ in PlaylistEditorView() }
            .confirmationDialog("Playlist löschen?", isPresented: Binding(
                get: { deletingPlaylist != nil }, set: { if !$0 { deletingPlaylist = nil } }
            ), titleVisibility: .visible) {
                Button("Playlist löschen", role: .destructive) {
                    guard let playlist = deletingPlaylist else { return }
                    context.delete(playlist)
                    save()
                    deletingPlaylist = nil
                }
            } message: { Text("Die Songs bleiben in deiner Bibliothek.") }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { @MainActor in
                    busy = true
                    defer { busy = false }
                    var failures: [String] = []
                    for url in urls {
                        do { try await MusicImportService.importFile(from: url, into: context) }
                        catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                    }
                    filter = .songs
                    if !failures.isEmpty { error = failures.joined(separator: "\n") }
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .alert("Bibliothek", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }

    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
    private func save() {
        do { try LibraryStore.save(context) } catch { self.error = error.localizedDescription }
    }
    private func deleteSongs(at offsets: IndexSet) {
        let selected = offsets.map { filteredSongs[$0] }
        do {
            try MusicImportService.deleteSongs(selected, from: context)
            player.removeFromQueue(ids: Set(selected.map(\.id)))
        } catch { self.error = error.localizedDescription }
    }
}
