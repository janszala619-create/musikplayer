import XCTest
import SwiftData
import UIKit
@testable import LocalMusic

@MainActor
final class CoverArtworkTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Song.self, Playlist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func image() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 600)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 600))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func defaults() -> UserDefaults {
        let name = "cover-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testMatchingRejectsOtherArtistsAndSongVersions() throws {
        let query = try XCTUnwrap(CoverQuery(title: "My Song", artist: "Artist", album: "Preferred Album"))
        let fixture = Data(#"{"recordings":[{"title":"My Song (Live)","artist-credit":[{"artist":{"name":"Artist"}}],"releases":[{"id":"11111111-1111-1111-1111-111111111111","title":"Live"}]},{"title":"My Song","artist-credit":[{"artist":{"name":"Other Artist"}}],"releases":[{"id":"22222222-2222-2222-2222-222222222222","title":"Other"}]},{"title":"MY SONG","artist-credit":[{"name":"Artist","artist":{"name":"Artist"}}],"releases":[{"id":"33333333-3333-3333-3333-333333333333","title":"Single","status":"Official"},{"id":"44444444-4444-4444-4444-444444444444","title":"Preferred Album","status":"Official"}]}]}"#.utf8)
        let response = try JSONDecoder().decode(CoverSearchResponse.self, from: fixture)
        let candidates = response.candidates(for: query)
        XCTAssertEqual(candidates.map(\.title), ["Preferred Album", "Single"])
        XCTAssertNil(CoverQuery(title: "Track", artist: MetadataFallback.unknownArtist, album: ""))
        let tricky = try XCTUnwrap(CoverQuery(title: "A \"quote\" & a slash\\", artist: "Artist", album: ""))
        let search = try XCTUnwrap(URLComponents(url: tricky.searchURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        XCTAssertTrue(search.contains("\\\"quote\\\""))
        XCTAssertTrue(search.contains("slash\\\\"))
    }

    func testOfficialStudioReleaseIsPreferredToCompilationsAndLiveBootlegs() throws {
        let query = try XCTUnwrap(CoverQuery(title: "Track", artist: "Artist", album: ""))
        let fixture = Data(#"{"recordings":[{"title":"Track","disambiguation":"live at a concert","artist-credit":[{"artist":{"name":"Artist"}}],"releases":[{"id":"11111111-1111-1111-1111-111111111111","title":"Concert","status":"Official"}]},{"title":"Track","artist-credit":[{"artist":{"name":"Artist"}}],"releases":[{"id":"22222222-2222-2222-2222-222222222222","title":"Bootleg","status":"Bootleg"},{"id":"33333333-3333-3333-3333-333333333333","title":"Compilation","status":"Official","release-group":{"id":"99999999-9999-9999-9999-999999999999","secondary-types":["Compilation"]}},{"id":"44444444-4444-4444-4444-444444444444","title":"Studio Album","status":"Official"}]}]}"#.utf8)
        let response = try JSONDecoder().decode(CoverSearchResponse.self, from: fixture)
        XCTAssertEqual(response.candidates(for: query).map(\.title), ["Studio Album", "Compilation"])
        let term = URLComponents(url: query.searchURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        XCTAssertTrue(term?.contains("status:official") == true)
    }

    func testMissingCoversAreFilledAndExistingPhotosArePreserved() async throws {
        let store = try container()
        let context = store.mainContext
        let missing = Song(title: "Track", artist: "Artist", album: "Album", duration: 1, fileName: "missing.mp3")
        let existing = Song(title: "Other", artist: "Artist", album: "Album", duration: 1, fileName: "other.mp3", artworkData: Data([7]))
        let unknown = Song(title: "Unknown", artist: MetadataFallback.unknownArtist, album: "", duration: 1, fileName: "unknown.mp3")
        for song in [missing, existing, unknown] { context.insert(song) }
        try context.save()
        let result = CoverResult(data: try image(), releaseID: UUID(), album: "Album")
        let lookup = CoverStub(result: result)
        let service = CoverArtworkService(catalog: lookup, defaults: defaults())
        await service.fillMissing(in: context)
        let queries = await lookup.queries
        XCTAssertEqual(queries.count, 1)
        XCTAssertEqual(queries.first?.title, "Track")
        let cover = try XCTUnwrap(missing.artworkData)
        let rendered = try XCTUnwrap(UIImage(data: cover))
        XCTAssertLessThanOrEqual(max(rendered.size.width, rendered.size.height), 800)
        XCTAssertEqual(missing.artworkSourceURL, result.sourceURL.absoluteString)
        XCTAssertEqual(existing.artworkData, Data([7]))
        XCTAssertNil(unknown.artworkData)
        XCTAssertTrue(service.searchingIDs.isEmpty)
        // Embedded metadata repair must not replace a downloaded or selected cover.
        MusicImportService.applyLegacyRepair(to: missing, metadata: nil, originalFileName: nil)
        XCTAssertEqual(missing.artworkData, cover)
    }

    func testNoMatchAndNetworkFailureUseCooldownWithoutChangingSong() async throws {
        for fail in [false, true] {
            let store = try container()
            let song = Song(title: "Track", artist: "Artist", album: "", duration: 1, fileName: "song.mp3")
            store.mainContext.insert(song)
            try store.mainContext.save()
            let lookup = CoverStub(result: nil, failing: fail)
            let service = CoverArtworkService(catalog: lookup, defaults: defaults())
            await service.fillMissing(in: store.mainContext)
            await service.fillMissing(in: store.mainContext)
            let count = await lookup.queries.count
            XCTAssertEqual(count, 1)
            XCTAssertNil(song.artworkData)
            XCTAssertEqual(song.title, "Track")
            XCTAssertTrue(service.searchingIDs.isEmpty)
        }
    }

    func testLateDownloadCannotOverwritePhotoEditedMetadataOrDeletedSong() throws {
        let store = try container()
        let context = store.mainContext
        let song = Song(title: "Track", artist: "Artist", album: "", duration: 1, fileName: "song.mp3")
        context.insert(song)
        try context.save()
        let query = try XCTUnwrap(CoverArtworkService.query(for: song))
        let data = try image()
        let result = CoverResult(data: data, releaseID: UUID(), album: "Album")
        let service = CoverArtworkService(catalog: CoverStub(result: result), defaults: defaults())
        try service.savePhoto(data, to: song, in: context)
        let selected = song.artworkData
        XCTAssertFalse(try service.apply(result, to: song, expectedQuery: query, replaceExisting: false, in: context))
        XCTAssertEqual(song.artworkData, selected)
        XCTAssertNil(song.artworkSourceURL)
        song.title = "Changed title"
        try context.save()
        XCTAssertFalse(try service.apply(result, to: song, expectedQuery: query, replaceExisting: true, in: context))
        let changedQuery = try XCTUnwrap(CoverArtworkService.query(for: song))
        context.delete(song)
        try context.save()
        XCTAssertFalse(try service.apply(result, to: song, expectedQuery: changedQuery, replaceExisting: true, in: context))
    }

    func testChosenCoverSurvivesStoreReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.store")
        let schema = Schema([Song.self, Playlist.self])
        let result = CoverResult(data: try image(), releaseID: UUID(), album: "Album")
        do {
            let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let song = Song(title: "Track", artist: "Artist", album: "", duration: 1, fileName: "song.mp3")
            store.mainContext.insert(song)
            try store.mainContext.save()
            let service = CoverArtworkService(catalog: CoverStub(result: result), defaults: defaults())
            XCTAssertTrue(try service.apply(result, to: song, expectedQuery: XCTUnwrap(CoverArtworkService.query(for: song)), replaceExisting: true, in: store.mainContext))
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let song = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Song>()).first)
        XCTAssertNotNil(song.artworkData.flatMap { UIImage(data: $0) })
        XCTAssertEqual(song.artworkSourceURL, result.sourceURL.absoluteString)
    }

    func testInvalidImagesNeverReplaceSavedCover() throws {
        let store = try container()
        let original = try image()
        let song = Song(title: "Track", artist: "Artist", album: "", duration: 1, fileName: "song.mp3", artworkData: original)
        store.mainContext.insert(song)
        try store.mainContext.save()
        let service = CoverArtworkService(defaults: defaults(), allowsAutomaticLookup: false)
        XCTAssertThrowsError(try service.savePhoto(Data("not an image".utf8), to: song, in: store.mainContext))
        XCTAssertEqual(song.artworkData, original)
    }

    func testCatalogUsesAnotherReleaseIfFirstHasNoCover() async throws {
        let png = try image()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverURLProtocol.self]
        CoverURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.contains("Audyn/") == true)
            if request.url?.host == "musicbrainz.org" {
                return (200, Data(#"{"recordings":[{"title":"Track","artist-credit":[{"artist":{"name":"Artist"}}],"releases":[{"id":"11111111-1111-1111-1111-111111111111","title":"First"},{"id":"22222222-2222-2222-2222-222222222222","title":"Second"}]}]}"#.utf8))
            }
            if request.url?.path.contains("11111111") == true { return (404, Data()) }
            return (200, png)
        }
        defer { CoverURLProtocol.handler = nil }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let catalog = CoverCatalog(session: session, requestInterval: 0)
        let query = try XCTUnwrap(CoverQuery(title: "Track", artist: "Artist", album: ""))
        let found = try await catalog.lookup(query)
        XCTAssertEqual(found?.album, "Second")
        XCTAssertEqual(found?.data, png)
    }

    func testCatalogFallsBackToCanonicalAlbumCover() async throws {
        let png = try image()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoverURLProtocol.self]
        CoverURLProtocol.handler = { request in
            if request.url?.host == "musicbrainz.org" {
                return (200, Data(#"{"recordings":[{"title":"Track","artist-credit":[{"artist":{"name":"Artist"}}],"releases":[{"id":"11111111-1111-1111-1111-111111111111","title":"Album","status":"Official","release-group":{"id":"22222222-2222-2222-2222-222222222222"}}]}]}"#.utf8))
            }
            if request.url?.path.hasPrefix("/release-group/") == true { return (200, png) }
            return (404, Data())
        }
        defer { CoverURLProtocol.handler = nil }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let catalog = CoverCatalog(session: session, requestInterval: 0)
        let query = try XCTUnwrap(CoverQuery(title: "Track", artist: "Artist", album: ""))
        let found = try await catalog.lookup(query)
        XCTAssertEqual(found?.album, "Album")
        XCTAssertEqual(found?.data, png)
    }
}

private actor CoverStub: CoverLookingUp {
    let result: CoverResult?
    let failing: Bool
    private(set) var queries: [CoverQuery] = []
    init(result: CoverResult?, failing: Bool = false) { self.result = result; self.failing = failing }
    func lookup(_ query: CoverQuery) async throws -> CoverResult? {
        queries.append(query)
        if failing { throw URLError(.notConnectedToInternet) }
        return result
    }
}

private final class CoverURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler, let url = request.url else { throw URLError(.badURL) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
