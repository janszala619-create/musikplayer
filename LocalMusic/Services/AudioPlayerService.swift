import AVFoundation
import Combine
import Observation

@MainActor
@Observable
final class AudioPlayerService {
    private var player: AVPlayer?
    private var endCancellable: AnyCancellable?

    private(set) var currentSongID: UUID?
    private(set) var isPlaying = false
    var errorMessage: String?

    func play(_ song: Song) {
        do {
            let url = try MusicImportService.fileURL(for: song)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PlaybackError.fileNotFound
            }
            try configureAudioSession()
            player?.pause()
            let newPlayer = AVPlayer(url: url)
            player = newPlayer
            currentSongID = song.id
            observeEnd(of: newPlayer)
            newPlayer.play()
            isPlaying = true
        } catch {
            isPlaying = false
            errorMessage = error.localizedDescription
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    var currentTime: TimeInterval {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
        return max(0, seconds)
    }

    func seek(by seconds: TimeInterval) {
        guard let player else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        let target = min(max(0, currentTime + seconds), duration.isFinite ? duration : currentTime)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
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
                self?.isPlaying = false
            }
    }
}

private enum PlaybackError: LocalizedError {
    case fileNotFound
    var errorDescription: String? { "Die importierte Audiodatei wurde nicht gefunden." }
}
