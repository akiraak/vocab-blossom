import AVFoundation
import OSLog

/// 読み上げと効果音で共有する `AVAudioSession` の準備。
///
/// マナーモードでも学習音声が鳴るよう `.playback` にする。
/// カテゴリ設定・有効化は他アプリの再生中や通話中だと失敗するので、
/// 一度失敗したまま黙り続けないよう、成功するまで毎回やり直す。
///
/// 使い道は 2 つ:
/// - 学習（提示カード・回答後カードの読み上げ・効果音）: ほかのアプリの音を小さくするだけ（`.duckOthers`）
/// - グループの読み上げ: ほかのアプリの音を止める（オプション無し）。読み上げ中は学習の側から無効化させない
final class LearningAudioSession {
    static let shared = LearningAudioSession()

    enum Purpose {
        case learning
        case readAloud

        var options: AVAudioSession.CategoryOptions {
            switch self {
            case .learning: [.duckOthers]
            case .readAloud: []
            }
        }
    }

    private nonisolated let log = Logger(
        subsystem: "com.akiraak.VocabBlossom", category: "audio-session"
    )
    /// 今カテゴリを設定してある使い道（nil は未設定・設定に失敗）
    private var configuredPurpose: Purpose?
    /// グループの読み上げが音声セッションを使っている間は true
    private(set) var isReadAloudActive = false

    private init() {}

    /// 音を出す直前に呼ぶ。通話や他アプリの割り込みで無効化されるので、毎回有効化し直す
    func activate(for purpose: Purpose = .learning) {
        // 読み上げ中は、学習側の読み上げ・効果音のためにカテゴリを変えない
        let purpose: Purpose = isReadAloudActive ? .readAloud : purpose
        if purpose == .readAloud { isReadAloudActive = true }

        let session = AVAudioSession.sharedInstance()
        if configuredPurpose != purpose {
            do {
                try session.setCategory(.playback, mode: .spokenAudio, options: purpose.options)
                configuredPurpose = purpose
            } catch {
                configuredPurpose = nil
                log.error("音声カテゴリの設定に失敗: \(error.localizedDescription)")
            }
        }
        do {
            try session.setActive(true)
        } catch {
            log.error("音声セッションの有効化に失敗: \(error.localizedDescription)")
        }
    }

    /// ほかのアプリの音量を戻す。失敗しても実害はない（次の有効化で立て直す）。
    ///
    /// 学習側からの無効化は、グループの読み上げ中なら何もしない（読み上げが止まってしまうため）
    func deactivate(for purpose: Purpose = .learning) {
        switch purpose {
        case .learning:
            guard !isReadAloudActive else { return }
        case .readAloud:
            guard isReadAloudActive else { return }
            isReadAloudActive = false
        }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: [.notifyOthersOnDeactivation]
            )
        } catch {
            log.debug("音声セッションの無効化に失敗: \(error.localizedDescription)")
        }
    }
}
