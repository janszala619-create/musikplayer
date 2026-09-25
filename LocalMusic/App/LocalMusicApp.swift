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
        }
        .modelContainer(for: [Song.self])
    }
}
