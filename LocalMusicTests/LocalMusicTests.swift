import XCTest
@testable import LocalMusic

final class LocalMusicTests: XCTestCase {
    func testSongKeepsItsMetadata() {
        let song = Song(title: "Titel", artist: "Künstler", album: "Album", duration: 123, fileName: "song.mp3")
        XCTAssertEqual(song.title, "Titel")
        XCTAssertEqual(song.duration, 123)
    }
}
