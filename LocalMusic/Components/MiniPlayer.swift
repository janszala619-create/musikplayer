import SwiftUI

struct MiniPlayer: View {
    let song: Song?
    let onTap: () -> Void
    @Environment(AudioPlayerService.self) private var player

    var body: some View {
        if let song {
            HStack(spacing: 12) {
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        ArtworkView(data: song.artworkData, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Player für \(song.title) öffnen")
                Spacer()
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(player.isPlaying ? "Pausieren" : "Wiedergabe starten")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
