import SwiftUI
import SwiftData

@MainActor
struct FullPlayerView: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AudioPlayerService.self) private var player
    @Query private var library: [Song]
    @State private var seeking = false
    @State private var seekPosition: Double = 0
    @State private var error: String?

    private var currentSong: Song { library.first { $0.id == player.currentSongID } ?? song }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 26) {
                        ArtworkView(data: currentSong.artworkData, size: min(geometry.size.width - 48, 320))
                            .shadow(color: .mint.opacity(0.12), radius: 30, y: 12)
                            .accessibilityLabel("Cover von \(currentSong.displayTitle)")
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(currentSong.displayTitle).font(.title2.bold()).lineLimit(3)
                                Text(currentSong.artist).font(.title3).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                do { try LibraryStore.toggleFavorite(currentSong, in: context) }
                                catch { self.error = error.localizedDescription }
                            } label: {
                                Image(systemName: currentSong.isFavorite ? "heart.fill" : "heart")
                                    .font(.title2).foregroundStyle(currentSong.isFavorite ? Color.mint : Color.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(currentSong.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
                        }
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            VStack(spacing: 6) {
                                Slider(value: Binding(
                                    get: { seeking ? seekPosition : min(player.currentTime, max(currentSong.duration, 1)) },
                                    set: { seekPosition = $0 }
                                ), in: 0...max(currentSong.duration, 1)) { editing in
                                    if editing {
                                        seekPosition = player.currentTime
                                        seeking = true
                                    } else {
                                        player.seek(to: seekPosition)
                                        seeking = false
                                    }
                                }
                                .accessibilityLabel("Wiedergabeposition")
                                HStack {
                                    Text(playbackTime(seeking ? seekPosition : player.currentTime))
                                    Spacer()
                                    Text(playbackTime(currentSong.duration))
                                }
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button { player.toggleShuffle() } label: {
                                Image(systemName: "shuffle").foregroundStyle(player.isShuffling ? Color.mint : Color.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(player.isShuffling ? "Shuffle ausschalten" : "Shuffle einschalten")
                            Spacer()
                            Button { player.previous() } label: {
                                Image(systemName: "backward.end.fill").font(.title2).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Vorheriger Song")
                            Spacer()
                            Button(action: player.togglePlayPause) {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title).frame(width: 72, height: 72)
                                    .background(.mint, in: Circle()).foregroundStyle(.black)
                            }
                            .accessibilityLabel(player.isPlaying ? "Pausieren" : "Wiedergabe starten")
                            Spacer()
                            Button { player.next() } label: {
                                Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Nächster Song")
                            Spacer()
                            Button { player.cycleRepeat() } label: {
                                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.mint)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(player.repeatMode.label)
                        }
                        .buttonStyle(.plain)
                        HStack {
                            Label("Lokal gespeichert", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            SongActions(song: currentSong)
                        }
                        if let source = currentSong.artworkSourceURL, let url = URL(string: source) {
                            Link("Coverquelle: MusicBrainz / Cover Art Archive", destination: url)
                                .font(.caption)
                        }
                        if player.queue.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Warteschlange").font(.headline)
                                ForEach(player.queue) { queued in
                                    Button { player.play(queued, in: player.queue) } label: {
                                        SongRow(song: queued)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .background(
                    LinearGradient(colors: [.teal.opacity(0.25), .black], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea()
                )
            }
            .navigationTitle("Wiedergabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen", systemImage: "chevron.down") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: player.currentSongID) { _, _ in seeking = false }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(error ?? "") }
    }
}
