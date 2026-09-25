import SwiftUI
import SwiftData

@MainActor
struct AppShellView: View {
    @Environment(AudioPlayerService.self) private var player
    @Query(sort: \Song.importedAt, order: .reverse) private var songs: [Song]

    private var currentSong: Song? {
        songs.first { $0.id == player.currentSongID }
    }

    var body: some View {
        TabView {
            HomeView(songs: songs)
                .tabItem { Label("Home", systemImage: "house") }
            SearchView(songs: songs)
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Bibliothek", systemImage: "books.vertical") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayer(song: currentSong)
        }
        .alert("Wiedergabe nicht möglich", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "Unbekannter Fehler")
        }
    }
}
