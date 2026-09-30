import XCTest
import AVFoundation
import SwiftData
import UIKit
@testable import LocalMusic

final class LocalMusicTests: XCTestCase {
    func testSongKeepsItsMetadata() {
        let song = Song(title: "Titel", artist: "Künstler", album: "Album", duration: 123, fileName: "song.mp3")
        XCTAssertEqual(song.title, "Titel")
        XCTAssertEqual(song.duration, 123)
    }

    func testArtistTitleFilename() {
        let text = MetadataFallback.resolve(originalFileName: "Kobosil - You Need The Drug.mp4")
        XCTAssertEqual(text.artist, "Kobosil")
        XCTAssertEqual(text.title, "You Need The Drug")
    }

    func testPlainFilename() {
        let text = MetadataFallback.resolve(originalFileName: "Track Name.m4a")
        XCTAssertEqual(text.title, "Track Name")
        XCTAssertEqual(text.artist, "Unbekannter Künstler")
    }

    func testOrdinaryHyphensArePreserved() {
        let text = MetadataFallback.resolve(originalFileName: "AC-DC - High-Voltage - Live.mp3")
        XCTAssertEqual(text.artist, "AC-DC")
        XCTAssertEqual(text.title, "High-Voltage - Live")
        XCTAssertEqual(MetadataFallback.resolve(originalFileName: "High-Voltage.mp3").title, "High-Voltage")
        XCTAssertEqual(MetadataFallback.resolve(originalFileName: "Artist-Title.mp3").artist, MetadataFallback.unknownArtist)
    }

    func testWhitespace() {
        let text = MetadataFallback.resolve(title: " \n\t", artist: "  ", album: "\n", originalFileName: "  Kobosil   -   You Need The Drug  .mp4 ")
        XCTAssertEqual(text.artist, "Kobosil")
        XCTAssertEqual(text.title, "You Need The Drug")
        XCTAssertEqual(text.album, MetadataFallback.unknownAlbum)
        let embedded = MetadataFallback.resolve(title: "  Valid Title\n", artist: " Artist \t", album: " Album ", originalFileName: nil)
        XCTAssertEqual(embedded, ResolvedSongText(title: "Valid Title", artist: "Artist", album: "Album"))
    }

    func testUUIDDetection() {
        for value in [
            "80AD5352-3973-492B-B6D1-FFEB12C7947A", "80ad5352-3973-492b-b6d1-ffeb12c7947a.mp4",
            " {80AD5352-3973-492B-B6D1-FFEB12C7947A} ", "80AD53523973492BB6D1FFEB12C7947A",
            "urn:uuid:80AD5352-3973-492B-B6D1-FFEB12C7947A"
        ] { XCTAssertTrue(MetadataFallback.isUUIDLike(value), value) }
        XCTAssertFalse(MetadataFallback.isUUIDLike("High-Voltage"))
        XCTAssertFalse(MetadataFallback.isUUIDLike("80AD5352-3973-492B-B6D1-FFEB12C7947Z"))
    }

    func testUUIDNeverBecomesFallbackTitle() {
        let uuid = UUID().uuidString
        let text = MetadataFallback.resolve(title: uuid, originalFileName: "\(uuid).mp3")
        XCTAssertEqual(text.title, MetadataFallback.unknownTitle)
        XCTAssertEqual(text.artist, MetadataFallback.unknownArtist)
        XCTAssertEqual(MetadataFallback.resolve(title: uuid, originalFileName: "Kobosil - Song.mp4").title, "Song")
        XCTAssertEqual(MetadataFallback.resolve(originalFileName: nil).title, MetadataFallback.unknownTitle)
    }

    func testEmbeddedTitleAndArtistResolveIndependently() {
        let text = MetadataFallback.resolve(title: "Embedded Title", originalFileName: "Kobosil - Worse Filename.mp4")
        XCTAssertEqual(text.title, "Embedded Title")
        XCTAssertEqual(text.artist, "Kobosil")
        let artistOnly = MetadataFallback.resolve(artist: "Embedded Artist", originalFileName: "Kobosil - Filename Title.mp4")
        XCTAssertEqual(artistOnly.artist, "Embedded Artist")
        XCTAssertEqual(artistOnly.title, "Filename Title")
        XCTAssertEqual(MetadataFallback.resolve(title: "Good Title", originalFileName: "\(UUID().uuidString).m4a").title, "Good Title")
    }

    func testEmptySeparatorSidesDontProduceEmptyFields() {
        for name in [" - Track.mp3", "Artist - .m4a", " .mp3"] {
            let text = MetadataFallback.resolve(originalFileName: name)
            XCTAssertFalse(text.title.isEmpty)
            XCTAssertEqual(text.artist, MetadataFallback.unknownArtist)
        }
    }

    func testLaterValidMetadataCandidateWinsOverBadTags() async {
        let text = await MetadataService.readText(from: [
            tag(.commonIdentifierTitle, "  " as NSString),
            tag(.id3MetadataTitleDescription, UUID().uuidString as NSString),
            tag(.iTunesMetadataSongName, "Real Title" as NSString),
            tag(.id3MetadataLeadPerformer, "Real Artist" as NSString),
            tag(.iTunesMetadataAlbum, "Real Album" as NSString)
        ], originalFileName: "Bad Filename.mp3")
        XCTAssertEqual(text, ResolvedSongText(title: "Real Title", artist: "Real Artist", album: "Real Album"))
    }

    func testArtworkSkipsInvalidCandidate() async throws {
        let cover = try await MainActor.run { try makeCover() }
        let artwork = await MetadataService.readArtwork(from: [
            tag(.commonIdentifierArtwork, Data([0, 1, 2]) as NSData),
            tag(.id3MetadataAttachedPicture, cover as NSData)
        ])
        XCTAssertEqual(artwork, cover)
        let missing = await MetadataService.readArtwork(from: [])
        XCTAssertNil(missing)
    }

    @MainActor
    func testLegacyRepairFromOriginalName() {
        let song = Song(title: UUID().uuidString, artist: MetadataFallback.unknownArtist, album: MetadataFallback.unknownAlbum, duration: 42, fileName: "\(UUID().uuidString).mp4", originalFileName: "Kobosil - You Need The Drug.mp4")
        MusicImportService.applyLegacyRepair(to: song, metadata: nil, originalFileName: song.originalFileName)
        XCTAssertEqual(song.title, "You Need The Drug")
        XCTAssertEqual(song.artist, "Kobosil")
        XCTAssertEqual(song.duration, 42)
        XCTAssertEqual(song.metadataVersion, MusicImportService.currentMetadataVersion)
    }

    @MainActor
    func testLegacyRepairWithoutProvenanceDoesNotInventMetadata() {
        let id = UUID()
        let song = Song(id: id, title: id.uuidString, artist: MetadataFallback.unknownArtist, album: MetadataFallback.unknownAlbum, duration: 42, fileName: "\(id.uuidString).mp3")
        XCTAssertEqual(song.displayTitle, MetadataFallback.unknownTitle)
        MusicImportService.applyLegacyRepair(to: song, metadata: nil, originalFileName: nil)
        XCTAssertEqual(song.title, MetadataFallback.unknownTitle)
        XCTAssertEqual(song.id, id)
        XCTAssertEqual(song.fileName, "\(id.uuidString).mp3")
        XCTAssertEqual(song.duration, 42)
        XCTAssertNil(song.originalFileName)
    }

    @MainActor
    func testLegacyRepairPreservesGoodFields() throws {
        let song = Song(title: "Keep Title", artist: "Keep Artist", album: "Keep Album", duration: 42, fileName: "song.m4a")
        let cover = try makeCover()
        let metadata = ExtractedMetadata(title: "Other Title", artist: "Other Artist", album: "Other Album", duration: 0, artworkData: cover)
        MusicImportService.applyLegacyRepair(to: song, metadata: metadata, originalFileName: "Other - Name.m4a")
        XCTAssertEqual(song.title, "Keep Title")
        XCTAssertEqual(song.artist, "Keep Artist")
        XCTAssertEqual(song.album, "Keep Album")
        XCTAssertEqual(song.duration, 42)
        XCTAssertEqual(song.artworkData, cover)
    }

    @MainActor
    func testLegacyRepairCanRecoverEmbeddedTitleWithoutOriginalName() {
        let song = Song(title: UUID().uuidString, artist: MetadataFallback.unknownArtist, album: MetadataFallback.unknownAlbum, duration: 0, fileName: "\(UUID().uuidString).mp3")
        let metadata = ExtractedMetadata(title: "Recovered Title", artist: "Recovered Artist", album: "Album", duration: 123, artworkData: nil)
        MusicImportService.applyLegacyRepair(to: song, metadata: metadata, originalFileName: nil)
        XCTAssertEqual(song.title, "Recovered Title")
        XCTAssertEqual(song.artist, "Recovered Artist")
        XCTAssertEqual(song.duration, 123)
    }

    @MainActor
    func testRepairIsPersistedAndOnlyRunsOnce() async throws {
        let container = try ModelContainer(for: Song.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let song = Song(title: UUID().uuidString, artist: MetadataFallback.unknownArtist, album: MetadataFallback.unknownAlbum, duration: 42, fileName: "\(UUID().uuidString).m4a", originalFileName: "Kobosil - Song.m4a")
        context.insert(song)
        try context.save()
        await MusicImportService.repairLegacySongs(in: context)
        let persisted = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Song>()).first)
        XCTAssertEqual(persisted.title, "Song")
        XCTAssertEqual(persisted.originalFileName, "Kobosil - Song.m4a")
        song.title = "Edited Title"
        await MusicImportService.repairLegacySongs(in: context)
        XCTAssertEqual(song.title, "Edited Title")
    }

    @MainActor
    func testM4AAndMP4ImportPersistsOriginalNameArtworkAndDuration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wav = try makeWAV(in: directory)
        let cover = try makeCover()
        let m4a = directory.appendingPathComponent("Kobosil - You Need The Drug.m4a")
        try await export(from: wav, to: m4a, preset: AVAssetExportPresetAppleM4A, type: .m4a, metadata: [
            tag(.iTunesMetadataSongName, "Embedded Title" as NSString),
            tag(.iTunesMetadataAlbum, "Embedded Album" as NSString),
            tag(.iTunesMetadataCoverArt, cover as NSData)
        ])
        let mp4 = directory.appendingPathComponent("Kobosil - You Need The Drug.mp4")
        try await export(from: m4a, to: mp4, preset: AVAssetExportPresetPassthrough, type: .mp4, metadata: [])
        let container = try ModelContainer(for: Song.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        for source in [m4a, mp4] {
            try await MusicImportService.importFile(from: source, into: container.mainContext)
        }
        let songs = try ModelContext(container).fetch(FetchDescriptor<Song>())
        defer { for song in songs { if let url = try? MusicImportService.fileURL(for: song) { try? FileManager.default.removeItem(at: url) } } }
        XCTAssertEqual(songs.count, 2)
        let importedM4A = try XCTUnwrap(songs.first { $0.originalFileName == m4a.lastPathComponent })
        XCTAssertEqual(importedM4A.title, "Embedded Title")
        XCTAssertEqual(importedM4A.artist, "Kobosil")
        XCTAssertEqual(importedM4A.album, "Embedded Album")
        XCTAssertEqual(importedM4A.artworkData, cover)
        let importedMP4 = try XCTUnwrap(songs.first { $0.originalFileName == mp4.lastPathComponent })
        XCTAssertEqual(importedMP4.title, "You Need The Drug")
        XCTAssertEqual(importedMP4.artist, "Kobosil")
        for song in songs {
            XCTAssertTrue(MetadataFallback.isUUIDLike(song.fileName))
            XCTAssertFalse(MetadataFallback.isUUIDLike(song.title))
            XCTAssertEqual(song.duration, 1, accuracy: 0.15)
            XCTAssertTrue(FileManager.default.fileExists(atPath: try MusicImportService.fileURL(for: song).path))
        }
    }

    @MainActor
    func testInvalidAudioImportLeavesNoDatabaseEntry() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let container = try ModelContainer(for: Song.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        do {
            try await MusicImportService.importFile(from: url, into: container.mainContext)
            XCTFail("Unusable audio must fail")
        } catch {
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Song>()).isEmpty)
        }
    }

    @MainActor
    func testMP3ImportReadsID3TagsAndDuration() async throws {
        // Self-generated 0.25-second silent MPEG audio with ID3v2.3 tags (FFmpeg/LAME).
        // Embedded bytes keep this test independent of bundled resources or CI tools.
        let data = try XCTUnwrap(Data(base64Encoded: "SUQzAwAAAAAAa1RJVDIAAAAUAAAARW1iZWRkZWQgTVAzIFRpdGxlAFRQRTEAAAAMAAAATVAzIEFydGlzdABUQUxCAAAACwAAAE1QMyBBbGJ1bQBUU1NFAAAADgAAAExhdmY2MS43LjEwMAAAAAAAAAAAAAAA//sQxAADwAABpAAAACAAADSAAAAETEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFX/+xLEKYPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFX/+xDEU4PAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVf/7EsR9A8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVf/7EMSnA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBV//sSxNCDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sQxNYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+xLE1YPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+xDE1gPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7EsTVg8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV"))
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp3")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let container = try ModelContainer(for: Song.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try await MusicImportService.importFile(from: source, into: container.mainContext)
        let song = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Song>()).first)
        defer { if let url = try? MusicImportService.fileURL(for: song) { try? FileManager.default.removeItem(at: url) } }
        XCTAssertEqual(song.title, "Embedded MP3 Title")
        XCTAssertEqual(song.artist, "MP3 Artist")
        XCTAssertEqual(song.album, "MP3 Album")
        XCTAssertGreaterThan(song.duration, 0.2)
        XCTAssertLessThan(song.duration, 0.5)
        XCTAssertNil(song.artworkData)
        XCTAssertEqual(song.originalFileName, source.lastPathComponent)
    }

    @MainActor
    func testExistingStoreMigratesWithoutLosingSongsOrArtwork() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("library.store")
        let id = UUID()
        let cover = try makeCover()
        do {
            let schema = Schema([LegacyStore.Song.self])
            let legacy = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
            legacy.mainContext.insert(LegacyStore.Song(id: id, artworkData: cover))
            try legacy.mainContext.save()
        }
        let schema = Schema([Song.self])
        let migrated = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
        let song = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Song>()).first)
        XCTAssertEqual(song.id, id)
        XCTAssertEqual(song.title, id.uuidString)
        XCTAssertEqual(song.duration, 42)
        XCTAssertEqual(song.artworkData, cover)
        XCTAssertNil(song.originalFileName)
        XCTAssertEqual(song.metadataVersion, 0)
        XCTAssertEqual(song.displayTitle, MetadataFallback.unknownTitle)
    }

    private func tag(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        return item
    }

    @MainActor
    private func makeCover() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func makeWAV(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("source.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0..<44100 { samples[index] = Float(sin(Double(index) * 2 * .pi * 440 / 44100) * 0.1) }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ])
        try file.write(from: buffer)
        return url
    }

    @MainActor
    private func export(from source: URL, to destination: URL, preset: String, type: AVFileType, metadata: [AVMetadataItem]) async throws {
        let session = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: preset))
        session.outputURL = destination
        session.outputFileType = type
        session.metadata = metadata
        await session.export()
        XCTAssertEqual(session.status, .completed, session.error?.localizedDescription ?? "Export failed")
        if let error = session.error { throw error }
    }
}

// Exact pre-fix persistent fields, used only to verify lightweight migration on disk.
private enum LegacyStore {
    @Model
    final class Song {
        @Attribute(.unique) var id: UUID
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var fileName: String
        @Attribute(.externalStorage) var artworkData: Data?
        var importedAt: Date

        init(id: UUID, artworkData: Data) {
            self.id = id
            self.title = id.uuidString
            self.artist = "Unbekannter Künstler"
            self.album = "Unbekanntes Album"
            self.duration = 42
            self.fileName = "\(id.uuidString).mp3"
            self.artworkData = artworkData
            self.importedAt = .now
        }
    }
}
