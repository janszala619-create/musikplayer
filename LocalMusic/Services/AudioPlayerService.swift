import AVFoundation
import Combine
import Observation

enum PlaybackRepeat: String, CaseIterable {
    case off, all, one
    var label: String {
        switch self {
        case .off: "Wiederholen aus"
        case .all: "Alle Titel wiederholen"
        case .one: "Einen Titel wiederholen"
        }
    }
}

@MainActor
@Observable
final class AudioPlayerService {
    private var player: AVPlayer?
    private var endCancellable: AnyCancellable?
    private var originalQueue: [Song] = []
    private(set) var queue: [Song] = []
    private(set) var currentSongID: UUID?
    private(set) var isPlaying = false
    private(set) var isShuffling = false
    var repeatMode: PlaybackRepeat = .off
    var errorMessage: String?

    func play(_ song: Song, in songs: [Song] = []) {
        var seen = Set<UUID>()
        originalQueue = (songs.isEmpty ? [song] : songs).filter { seen.insert($0.id).inserted }
        if !originalQueue.contains(where: { $0.id == song.id }) { originalQueue.insert(song, at: 0) }
        queue = isShuffling ? [song] + originalQueue.filter { $0.id != song.id }.shuffled() : originalQueue
        start(song)
    }

    func playAll(_ songs: [Song], shuffled: Bool = false) {
        guard !songs.isEmpty else { return }
        isShuffling = shuffled
        guard let first = shuffled ? songs.randomElement() : songs.first else { return }
        play(first, in: songs)
    }

    private func start(_ song: Song) {
        do {
            let url = try MusicImportService.fileURL(for: song)
            guard FileManager.default.fileExists(atPath: url.path) else { throw PlaybackError.fileNotFound }
            try configureAudioSession()
            player?.pause()
            let newPlayer = Self.makePlayer(for: url)
            player = newPlayer
            currentSongID = song.id
            observeEnd(of: newPlayer)
            errorMessage = nil
            newPlayer.play()
            isPlaying = true
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            do {
                try configureAudioSession()
                if let duration = player.currentItem?.duration.seconds,
                   duration.isFinite, currentTime >= duration - 0.1 {
                    seek(to: 0)
                }
                player.play()
                isPlaying = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func next() { advance(automatic: false) }

    func playbackDidEnd() { advance(automatic: true) }

    private func advance(automatic: Bool) {
        guard let index = queue.firstIndex(where: { $0.id == currentSongID }) else { return }
        if automatic && repeatMode == .one {
            start(queue[index])
        } else if index + 1 < queue.count {
            start(queue[index + 1])
        } else if repeatMode == .all {
            start(queue[0])
        } else {
            player?.pause()
            isPlaying = false
        }
    }

    func previous() {
        if currentTime > 3 { seek(to: 0); return }
        guard let index = queue.firstIndex(where: { $0.id == currentSongID }) else { return }
        if index > 0 { start(queue[index - 1]) }
        else if repeatMode == .all, let last = queue.last { start(last) }
        else { seek(to: 0) }
    }

    func toggleShuffle() {
        isShuffling.toggle()
        guard let current = originalQueue.first(where: { $0.id == currentSongID }) else { return }
        queue = isShuffling
            ? [current] + originalQueue.filter { $0.id != current.id }.shuffled()
            : originalQueue
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func removeFromQueue(ids: Set<UUID>) {
        originalQueue.removeAll { ids.contains($0.id) }
        queue.removeAll { ids.contains($0.id) }
        if let currentSongID, ids.contains(currentSongID) { stop() }
    }

    static func makePlayer(for url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        return player
    }

    func stop() {
        player?.pause()
        player = nil
        endCancellable = nil
        currentSongID = nil
        isPlaying = false
        queue = []
        originalQueue = []
    }

    var currentTime: TimeInterval {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
        return max(0, seconds)
    }

    func seek(by seconds: TimeInterval) { seek(to: currentTime + seconds) }

    func seek(to seconds: TimeInterval) {
        guard let player, seconds.isFinite else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        let upper = duration.isFinite && duration > 0 ? duration : max(0, seconds)
        player.seek(to: CMTime(seconds: min(max(0, seconds), upper), preferredTimescale: 600))
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func observeEnd(of player: AVPlayer) {
        endCancellable = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.playbackDidEnd()
            }
    }
}

private enum PlaybackError: LocalizedError {
    case fileNotFound
    var errorDescription: String? { "Die importierte Audiodatei wurde nicht gefunden." }
}
