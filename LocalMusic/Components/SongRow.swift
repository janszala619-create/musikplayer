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
            Text(song.duration, format: .time(pattern: .minuteSecond))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
