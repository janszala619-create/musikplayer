import Foundation
import SwiftUI
import SwiftData

struct SongRow: View {
    let song: Song
    @Environment(AudioPlayerService.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(data: song.artworkData)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(player.currentSongID == song.id ? Color.mint : Color.primary)
                    .lineLimit(1)
                Text(song.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if song.isFavorite {
                Image(systemName: "heart.fill").font(.caption).foregroundStyle(.mint)
                    .accessibilityLabel("Favorit")
            }
            Text(playbackTime(song.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

func playbackTime(_ interval: TimeInterval) -> String {
    let seconds = interval.isFinite ? max(0, Int(interval)) : 0
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

@MainActor
struct PlaySongButton: View {
    let song: Song
    var queue: [Song] = []
    @Environment(AudioPlayerService.self) private var player

    var body: some View {
        HStack(spacing: 8) {
            Button { player.play(song, in: queue.isEmpty ? [song] : queue) } label: {
                SongRow(song: song)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(song.displayTitle) wiedergeben")
            SongActions(song: song)
        }
    }
}
