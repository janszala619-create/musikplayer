import SwiftUI
import SwiftData

@MainActor
struct HomeView: View {
    let songs: [Song]
    @Query(sort: \Playlist.createdAt, order: .reverse) private var playlists: [Playlist]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Deine Musik. Immer dabei.").font(.title2.bold())
                        Text("Lokal gespeichert, bereit zum Abspielen.").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        NavigationLink { SongCollectionView(title: "Deine Favoriten", favoritesOnly: true) } label: {
                            shortcut("Favoriten", symbol: "heart.fill")
                        }
                        NavigationLink { SongCollectionView(title: "Alle Songs") } label: {
                            shortcut("Alle Songs", symbol: "music.note.list")
                        }
                    }
                    .buttonStyle(.plain)
                    if !playlists.isEmpty {
                        Text("Deine Playlists").font(.title2.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(playlists) { playlist in
                                    NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            CollectionArtwork(songs: playlist.songs(in: songs), size: 140)
                                            Text(playlist.name).font(.headline).lineLimit(2)
                                            Text("\(playlist.songIDs.count) Songs").font(.caption).foregroundStyle(.secondary)
                                        }
                                        .frame(width: 140, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Text("Zuletzt importiert").font(.title2.bold())
                    if songs.isEmpty {
                        ContentUnavailableView("Noch keine Musik", systemImage: "music.note", description: Text("Importiere deine ersten Dateien in der Bibliothek."))
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(songs.prefix(8)) { song in
                                PlaySongButton(song: song, queue: songs)
                                if song.id != songs.prefix(8).last?.id { Divider().padding(.leading, 64) }
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(20)
            }
            .navigationTitle("Home")
            .background(Color.black)
        }
    }

    private func shortcut(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.mint)
            Text(title).font(.subheadline.bold())
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
