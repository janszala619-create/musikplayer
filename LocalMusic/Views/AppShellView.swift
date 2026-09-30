import SwiftUI
import SwiftData

@MainActor
struct AppShellView: View {
    @Environment(AudioPlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.importedAt, order: .reverse) private var songs: [Song]
    @State private var playerSheetSong: Song?

    private var currentSong: Song? {
        songs.first { $0.id == player.currentSongID }
    }

    var body: some View {
        TabView {
            HomeView(songs: songs)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Home", systemImage: "house") }
            SearchView(songs: songs)
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
            LibraryView()
                .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
                .tabItem { Label("Bibliothek", systemImage: "books.vertical") }
        }
        .sheet(item: $playerSheetSong) { song in
            FullPlayerView(song: song)
        }
        .task {
            await MusicImportService.repairLegacySongs(in: modelContext)
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

    // Inset each tab's content, not the TabView itself: the native tab bar
    // retains its own safe area and remains visible/tappable below the player.
    private var miniPlayer: some View {
        MiniPlayer(song: currentSong) {
            playerSheetSong = currentSong
        }
    }
}
