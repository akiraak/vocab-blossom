import AVFoundation
import OSLog

/// 読み上げと効果音で共有する `AVAudioSession` の準備。
///
/// マナーモードでも学習音声が鳴るよう `.playback` にする。
/// カテゴリ設定・有効化は他アプリの再生中や通話中だと失敗するので、
/// 一度失敗したまま黙り続けないよう、成功するまで毎回やり直す。
final class LearningAudioSession {
    static let shared = LearningAudioSession()

    private nonisolated let log = Logger(
        subsystem: "com.akiraak.VocabBlossom", category: "audio-session"
    )
    private var isCategoryConfigured = false

    private init() {}

    /// 音を出す直前に呼ぶ。通話や他アプリの割り込みで無効化されるので、毎回有効化し直す
    func activate() {
        let session = AVAudioSession.sharedInstance()
        if !isCategoryConfigured {
            do {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                isCategoryConfigured = true
            } catch {
                log.error("音声カテゴリの設定に失敗: \(error.localizedDescription)")
            }
        }
        do {
            try session.setActive(true)
        } catch {
            log.error("音声セッションの有効化に失敗: \(error.localizedDescription)")
        }
    }

    /// ほかのアプリの音量を戻す。失敗しても実害はない（次の有効化で立て直す）
    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: [.notifyOthersOnDeactivation]
            )
        } catch {
            log.debug("音声セッションの無効化に失敗: \(error.localizedDescription)")
        }
    }
}
