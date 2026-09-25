import Foundation
import SwiftUI

struct SongRow: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(data: song.artworkData)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).lineLimit(1)
                Text("\(song.artist) · \(song.album)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(durationText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var durationText: String {
        let totalSeconds = max(0, Int(song.duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
