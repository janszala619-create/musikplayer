import Foundation
import SwiftData
import Observation
import ImageIO
import UIKit

struct CoverQuery: Hashable, Sendable {
    let title: String
    let artist: String
    let album: String

    init?(title: String, artist: String, album: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty,
              title != MetadataFallback.unknownTitle, artist != MetadataFallback.unknownArtist else { return nil }
        self.title = title
        self.artist = artist
        self.album = album == MetadataFallback.unknownAlbum ? "" : album
    }

    var key: String {
        // Encode each field independently to keep delimiters in song names unambiguous.
        [title, artist, album].map { Data(Self.normalized($0).utf8).base64EncodedString() }.joined(separator: ":")
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    var searchURL: URL {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording")!
        components.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(escaped(title))\" AND artist:\"\(escaped(artist))\""),
            URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "25")
        ]
        return components.url!
    }
}

struct CoverResult: Sendable {
    let data: Data
    let releaseID: UUID
    let album: String
    var sourceURL: URL { URL(string: "https://musicbrainz.org/release/\(releaseID.uuidString.lowercased())")! }
}

struct CoverSearchResponse: Decodable {
    let recordings: [Recording]

    struct Recording: Decodable {
        let title: String
        let artistCredit: [Credit]
        let releases: [Release]?
        enum CodingKeys: String, CodingKey {
            case title, releases
            case artistCredit = "artist-credit"
        }
    }
    struct Credit: Decodable {
        let name: String?
        let artist: Artist
    }
    struct Artist: Decodable { let name: String }
    struct Release: Decodable {
        let id: UUID
        let title: String
        let status: String?
    }

    func candidates(for query: CoverQuery) -> [Release] {
        let title = CoverQuery.normalized(query.title)
        let artist = CoverQuery.normalized(query.artist)
        var seen = Set<UUID>()
        let matches = recordings.filter { recording in
            let credits = recording.artistCredit.map { CoverQuery.normalized($0.name ?? $0.artist.name) }
            return CoverQuery.normalized(recording.title) == title
                && (credits.contains(artist) || credits.joined(separator: " ") == artist)
        }.flatMap { $0.releases ?? [] }.filter { seen.insert($0.id).inserted }
        return matches.sorted { left, right in
            func priority(_ release: Release) -> Int {
                let albumMatch = !query.album.isEmpty && CoverQuery.normalized(release.title) == CoverQuery.normalized(query.album)
                return (albumMatch ? 2 : 0) + (release.status == "Official" ? 1 : 0)
            }
            return priority(left) > priority(right)
        }
    }
}

enum CoverLookupError: LocalizedError {
    case missingMetadata, invalidImage, imageTooLarge, serviceUnavailable
    var errorDescription: String? {
        switch self {
        case .missingMetadata: "Trage zuerst den richtigen Titel und Künstler ein, damit die Cover-Suche deinen Song finden kann."
        case .invalidImage: "Das Bild konnte nicht gelesen werden. Bitte wähle ein anderes Bild."
        case .imageTooLarge: "Dieses Bild ist zu groß. Bitte wähle eine kleinere Datei."
        case .serviceUnavailable: "Die Cover-Suche ist gerade nicht erreichbar. Versuche es später erneut."
        }
    }
}

protocol CoverLookingUp: Sendable {
    func lookup(_ query: CoverQuery) async throws -> CoverResult?
}

actor CoverCatalog: CoverLookingUp {
    private let session: URLSession
    private var nextRequestAt = Date.distantPast
    private let requestInterval: TimeInterval

    init(session: URLSession = .shared, requestInterval: TimeInterval = 1.1) {
        self.session = session
        self.requestInterval = requestInterval
    }

    func lookup(_ query: CoverQuery) async throws -> CoverResult? {
        // Reserve the slot before suspending: actor reentrancy must not bypass throttling.
        let slot = max(Date.now, nextRequestAt)
        nextRequestAt = slot.addingTimeInterval(requestInterval)
        let delay = slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        let searchData = try await fetch(query.searchURL, limit: 2_000_000)
        guard let searchData else { return nil }
        let response = try JSONDecoder().decode(CoverSearchResponse.self, from: searchData)
        for release in response.candidates(for: query).prefix(8) {
            try Task.checkCancellation()
            let url = URL(string: "https://coverartarchive.org/release/\(release.id.uuidString.lowercased())/front-500")!
            guard let data = try await fetch(url, limit: 8_000_000) else { continue }
            // Ignore broken image responses and continue with another matching release.
            guard CGImageSourceCreateWithData(data as CFData, nil) != nil else { continue }
            return CoverResult(data: data, releaseID: release.id, album: release.title)
        }
        return nil
    }

    private func fetch(_ url: URL, limit: Int) async throws -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Audyn/0.3.1 (https://github.com/janszala619-create/musikplayer)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CoverLookupError.serviceUnavailable }
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw CoverLookupError.serviceUnavailable }
        guard data.count <= limit else { throw CoverLookupError.imageTooLarge }
        return data
    }
}

@MainActor
enum CoverImage {
    static func prepared(_ data: Data) throws -> Data {
        guard data.count <= 30_000_000 else { throw CoverLookupError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
            throw CoverLookupError.invalidImage
        }
        return jpeg
    }
}

@MainActor
@Observable
final class CoverArtworkService {
    private let catalog: any CoverLookingUp
    private let defaults: UserDefaults
    let allowsAutomaticLookup: Bool
    private(set) var searchingIDs = Set<UUID>()

    init(catalog: any CoverLookingUp = CoverCatalog(), defaults: UserDefaults = .standard, allowsAutomaticLookup: Bool = true) {
        self.catalog = catalog
        self.defaults = defaults
        self.allowsAutomaticLookup = allowsAutomaticLookup
    }

    static func query(for song: Song) -> CoverQuery? {
        CoverQuery(title: song.displayTitle, artist: song.artist, album: song.album)
    }

    func lookup(_ query: CoverQuery) async throws -> CoverResult? { try await catalog.lookup(query) }

    func fillMissing(in context: ModelContext) async {
        guard allowsAutomaticLookup else { return }
        let songs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
        for song in songs {
            if Task.isCancelled { return }
            guard song.artworkData == nil, let query = Self.query(for: song), !searchingIDs.contains(song.id) else { continue }
            let retryKey = "cover.retry." + query.key
            if let retry = defaults.object(forKey: retryKey) as? Date, retry > .now { continue }
            searchingIDs.insert(song.id)
            do {
                let result = try await catalog.lookup(query)
                try Task.checkCancellation()
                if let result, try apply(result, to: song, expectedQuery: query, replaceExisting: false, in: context) {
                    defaults.removeObject(forKey: retryKey)
                } else {
                    defaults.set(Date.now.addingTimeInterval(7 * 24 * 3600), forKey: retryKey)
                }
            } catch is CancellationError {
                searchingIDs.remove(song.id)
                return
            } catch {
                // Network failures never interrupt audio importing or playback.
                if Task.isCancelled { searchingIDs.remove(song.id); return }
                defaults.set(Date.now.addingTimeInterval(3600), forKey: retryKey)
            }
            searchingIDs.remove(song.id)
        }
    }

    @discardableResult
    func apply(_ result: CoverResult, to song: Song, expectedQuery: CoverQuery, replaceExisting: Bool, in context: ModelContext) throws -> Bool {
        // A download may finish after a metadata edit, photo selection or song deletion.
        let id = song.id
        let descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
        guard try context.fetch(descriptor).contains(where: { $0.id == id }),
              Self.query(for: song) == expectedQuery,
              replaceExisting || song.artworkData == nil else { return false }
        let jpeg = try CoverImage.prepared(result.data)
        song.artworkData = jpeg
        song.artworkSourceURL = result.sourceURL.absoluteString
        try LibraryStore.save(context)
        return true
    }

    func savePhoto(_ data: Data, to song: Song, in context: ModelContext) throws {
        let jpeg = try CoverImage.prepared(data)
        song.artworkData = jpeg
        song.artworkSourceURL = nil
        try LibraryStore.save(context)
    }
}
