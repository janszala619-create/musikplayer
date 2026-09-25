import SwiftUI

struct HomeView: View {
    let songs: [Song]

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView("Noch keine Musik", systemImage: "music.note.list", description: Text("Importiere deine ersten Dateien in der Bibliothek."))
                } else {
                    List(songs.prefix(8)) { song in
                        PlaySongButton(song: song)
                    }
                }
            }
            .navigationTitle("Home")
        }
    }
}

struct PlaySongButton: View {
    let song: Song
    @Environment(AudioPlayerService.self) private var player

    var body: some View {
        Button { player.play(song) } label: { SongRow(song: song) }
            .buttonStyle(.plain)
            .accessibilityLabel("\(song.title) wiedergeben")
    }
}
