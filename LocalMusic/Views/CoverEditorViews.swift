import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

@MainActor
struct CoverSearchView: View {
    let song: Song
    @Environment(CoverArtworkService.self) private var artwork
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var result: CoverResult?
    @State private var query: CoverQuery?
    @State private var searching = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text(song.displayTitle).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(song.artist).foregroundStyle(.secondary)
                    if searching {
                        ProgressView("Cover wird gesucht …").padding(40)
                    } else if let result {
                        ArtworkView(data: result.data, size: 240)
                        Text(result.album).font(.headline).multilineTextAlignment(.center)
                        Link("MusicBrainz / Cover Art Archive", destination: result.sourceURL).font(.caption)
                        Button("Cover übernehmen") { save(result) }.buttonStyle(.borderedProminent)
                    } else {
                        ArtworkView(data: song.artworkData, size: 200)
                    }
                    if let message { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    Button("Erneut suchen", systemImage: "arrow.clockwise") {
                        Task { await search() }
                    }
                    .disabled(searching)
                }
                .frame(maxWidth: .infinity).padding(24)
            }
            .navigationTitle("Cover suchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
        }
        .task { await search() }
    }

    private func search() async {
        guard !searching else { return }
        searching = true
        defer { searching = false }
        result = nil
        message = nil
        guard let query = CoverArtworkService.query(for: song) else {
            message = CoverLookupError.missingMetadata.localizedDescription
            return
        }
        self.query = query
        do {
            let found = try await artwork.lookup(query)
            try Task.checkCancellation()
            result = found
            if found == nil { message = "Kein passendes Cover gefunden. Prüfe Titel und Künstler oder wähle ein eigenes Bild." }
        } catch is CancellationError {
            return
        } catch { message = error.localizedDescription }
    }

    private func save(_ result: CoverResult) {
        guard let query else { return }
        do {
            if try artwork.apply(result, toSongID: song.id, expectedQuery: query, replaceExisting: true, in: context) {
                dismiss()
            } else { message = "Die Songdaten haben sich geändert. Suche das Cover bitte erneut." }
        } catch { message = error.localizedDescription }
    }
}

@MainActor
struct CoverPhotoView: View {
    let song: Song
    @Environment(CoverArtworkService.self) private var artwork
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var loading = false
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ArtworkView(data: imageData ?? song.artworkData, size: 240)
                    if loading { ProgressView("Bild wird geladen …") }
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label("Aus Fotos auswählen", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent).disabled(loading)
                    Button("Aus Dateien auswählen", systemImage: "folder") { importing = true }
                        .buttonStyle(.bordered).disabled(loading)
                    Text("Das Bild wird als Cover in Audyn gespeichert und für die Anzeige verkleinert.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let message { Text(message).foregroundStyle(.red).multilineTextAlignment(.center) }
                }
                .frame(maxWidth: .infinity).padding(24)
            }
            .navigationTitle("Eigenes Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let imageData else { return }
                        do { try artwork.savePhoto(imageData, to: song, in: context); dismiss() }
                        catch { message = error.localizedDescription }
                    }
                    .disabled(imageData == nil || loading)
                }
            }
        }
        .task(id: selection) {
            guard let selection else { return }
            loading = true
            message = nil
            defer { loading = false }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self) else { throw CoverLookupError.invalidImage }
                try Task.checkCancellation()
                imageData = try CoverImage.prepared(data)
            } catch is CancellationError { return }
            catch { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 30_000_000 else { throw CoverLookupError.imageTooLarge }
                imageData = try CoverImage.prepared(Data(contentsOf: url))
                message = nil
            } catch { message = error.localizedDescription }
        }
    }
}
