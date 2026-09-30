import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@MainActor
struct LibraryView: View {
    @Environment(AudioPlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.importedAt, order: .reverse) private var songs: [Song]
    @State private var isImporting = false
    @State private var importError: ImportAlert?

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView("Deine Bibliothek ist leer", systemImage: "music.note", description: Text("Tippe auf Importieren, um Musik lokal zu speichern."))
                } else {
                    List {
                        Section {
                            ForEach(songs) { song in PlaySongButton(song: song) }
                                .onDelete(perform: deleteSongs)
                        } footer: {
                            if songs.contains(where: { $0.displayTitle == MetadataFallback.unknownTitle }) {
                                Text("Bei alten Imports ohne Originalnamen und Titel-Tags lässt sich der Name nicht wiederherstellen. Den Eintrag nach links wischen, löschen und die Originaldatei erneut importieren.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bibliothek")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(appVersion).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("app.version")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Importieren", systemImage: "plus") { isImporting = true }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { @MainActor in
                    for url in urls {
                        do {
                            try await MusicImportService.importFile(from: url, into: modelContext)
                        } catch {
                            importError = ImportAlert(message: error.localizedDescription)
                            break
                        }
                    }
                }
            case .failure(let error):
                importError = ImportAlert(message: error.localizedDescription)
            }
        }
        .alert(item: $importError) { alert in
            Alert(title: Text("Bibliothek"), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func deleteSongs(at offsets: IndexSet) {
        let selected = offsets.map { songs[$0] }
        let deletingCurrentSong = selected.contains { $0.id == player.currentSongID }
        do {
            try MusicImportService.deleteSongs(selected, from: modelContext)
            if deletingCurrentSong { player.stop() }
        } catch {
            importError = ImportAlert(message: error.localizedDescription)
        }
    }
}

private struct ImportAlert: Identifiable {
    let id = UUID()
    let message: String
}
