import Foundation
import SwiftUI

@MainActor
struct FullPlayerView: View {
    let song: Song

    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayerService.self) private var player

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 12)

                ArtworkView(data: song.artworkData, size: 280)
                    .accessibilityLabel("Cover von \(song.title)")

                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(song.artist)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 8) {
                        ProgressView(value: min(player.currentTime, song.duration), total: max(song.duration, 1))
                        HStack {
                            Text(timeText(player.currentTime))
                            Spacer()
                            Text("-\(timeText(max(0, song.duration - player.currentTime)))")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 36) {
                    Button { player.seek(by: -15) } label: {
                        Image(systemName: "gobackward.15")
                    }
                    .accessibilityLabel("15 Sekunden zurück")

                    Button(action: player.togglePlayPause) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .frame(width: 72, height: 72)
                            .background(.primary, in: Circle())
                            .foregroundStyle(.background)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pausieren" : "Wiedergabe starten")

                    Button { player.seek(by: 15) } label: {
                        Image(systemName: "goforward.15")
                    }
                    .accessibilityLabel("15 Sekunden vor")
                }
                .font(.title2)

                Spacer()
            }
            .padding(.horizontal, 28)
            .navigationTitle("Wiedergabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
