import Foundation
import MediaPlayer
import Observation

/// 読み上げ中の語をロック画面・コントロールセンターに出し、そこからの操作（再生・一時停止・前後）を受ける。
///
/// 読み上げ画面を開いている間だけ `start`〜`stop` で有効にする
final class ReadAloudNowPlaying {
    private weak var player: ReadAloudPlayer?
    private var groupName = ""
    private var registrations: [(command: MPRemoteCommand, target: Any)] = []
    private var isActive = false

    func start(player: ReadAloudPlayer, groupName: String) {
        guard !isActive else { return }
        isActive = true
        self.player = player
        self.groupName = groupName
        registerCommands()
        observe()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        for registration in registrations {
            registration.command.removeTarget(registration.target)
        }
        registrations = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        player = nil
    }

    // MARK: -

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.play() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.togglePlay() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }
    }

    private func register(_ command: MPRemoteCommand, action: @escaping (ReadAloudPlayer) -> Void) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let player = self?.player else { return .noActionableNowPlayingItem }
                action(player)
                return .success
            }
        }
        registrations.append((command, target))
    }

    /// 語・再生状態が変わるたびに表示を描き直す
    private func observe() {
        guard isActive, let player else { return }
        withObservationTracking {
            update(player)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.observe() }
            }
        }
    }

    private func update(_ player: ReadAloudPlayer) {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = player.canGoNext
        center.previousTrackCommand.isEnabled = player.canGoPrevious

        guard let item = player.currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.word.word,
            MPMediaItemPropertyArtist: item.word.meaningSummary,
            MPMediaItemPropertyAlbumTitle: groupName,
            MPMediaItemPropertyAlbumTrackNumber: player.index + 1,
            MPMediaItemPropertyAlbumTrackCount: player.items.count,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
        ]
    }
}
