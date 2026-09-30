import SwiftUI
import SwiftData

@MainActor
struct MiniPlayer: View {
    let song: Song?
    let onTap: () -> Void
    @Environment(AudioPlayerService.self) private var player
    @Environment(\.modelContext) private var context
    @State private var error: String?

    var body: some View {
        if let song {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button(action: onTap) {
                        HStack(spacing: 12) {
                            ArtworkView(data: song.artworkData, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.displayTitle).font(.subheadline.bold()).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Player für \(song.displayTitle) öffnen")
                    .accessibilityIdentifier("miniPlayer.open")
                    Button {
                        do { try LibraryStore.toggleFavorite(song, in: context) }
                        catch { self.error = error.localizedDescription }
                    } label: {
                        Image(systemName: song.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(song.isFavorite ? Color.mint : Color.primary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(song.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
                    Button(action: player.togglePlayPause) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(player.isPlaying ? "Pausieren" : "Wiedergabe starten")
                    .accessibilityIdentifier("miniPlayer.playPause")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ProgressView(value: min(player.currentTime, max(song.duration, 1)), total: max(song.duration, 1))
                        .tint(.mint).padding(.horizontal, 12).padding(.bottom, 4)
                }
            }
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .alert("Speichern fehlgeschlagen", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
}
