import SwiftUI

@MainActor
struct SearchView: View {
    let songs: [Song]
    @State private var query = ""

    private var results: [Song] {
        guard !query.isEmpty else { return songs }
        return songs.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
                || $0.album.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { song in PlaySongButton(song: song, queue: results) }
                .overlay {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .navigationTitle("Suche")
                .searchable(text: $query, prompt: "Titel, Künstler oder Album")
        }
    }
}
