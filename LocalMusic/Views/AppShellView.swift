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
        VStack(spacing: 0) {
            TabView {
                HomeView(songs: songs)
                    .tabItem { Label("Home", systemImage: "house") }
                SearchView(songs: songs)
                    .tabItem { Label("Suche", systemImage: "magnifyingglass") }
                LibraryView()
                    .tabItem { Label("Bibliothek", systemImage: "books.vertical") }
            }

            MiniPlayer(song: currentSong) {
                playerSheetSong = currentSong
            }
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
}
