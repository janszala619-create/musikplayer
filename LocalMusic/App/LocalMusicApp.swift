import SwiftUI
import SwiftData

@main
@MainActor
struct LocalMusicApp: App {
    @State private var player = AudioPlayerService()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(player)
                .preferredColorScheme(.dark)
                .tint(.mint)
        }
        .modelContainer(for: [Song.self, Playlist.self])
    }
}
