import AVFoundation
import Foundation
import OSLog

/// 英語の読み上げ（OS 内蔵 TTS）。
///
/// 「目 + 耳」のセットで単語に触れさせるため、提示カード・回答後カード・
/// リスニングクイズから呼ばれる。
final class SpeechService {
    static let shared = SpeechService()

    private let log = Logger(subsystem: "com.akiraak.VocabBlossom", category: "speech")
    private let synthesizer = AVSpeechSynthesizer()

    /// 停止の完了を待ってから話し始めるためのタスク
    private var flushTask: Task<Void, Never>?
    private var isCategoryConfigured = false

    /// 単語の読み上げ速度。既定値だと初学者には速いので少し落とす
    private let wordRate: Float = 0.42
    private let sentenceRate: Float = 0.45

    /// 端末に英語の音声が無いと日本語音声で英文を読んでしまうので、明示的に選んでおく
    private lazy var englishVoice: AVSpeechSynthesisVoice? = {
        AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("en") }
    }()

    private init() {}

    /// 単語だけを読む。
    func speak(word: String) {
        enqueue([(word, wordRate)])
    }

    /// 単語 → 例文 の順に読む。リスニングクイズと提示カードで使う。
    func speak(word: String, example: String) {
        enqueue([(word, wordRate), (example, sentenceRate)])
    }

    /// 読み上げを止め、ほかのアプリの音量を元に戻す。
    func stop() {
        flushTask?.cancel()
        flushTask = nil
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
    }

    private func enqueue(_ items: [(text: String, rate: Float)]) {
        prepareSession()
        let utterances = items
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(makeUtterance)
        guard !utterances.isEmpty else { return }

        flushTask?.cancel()
        flushTask = nil

        guard synthesizer.isSpeaking || synthesizer.isPaused else {
            utterances.forEach(synthesizer.speak)
            return
        }

        // `stopSpeaking` は非同期で、停止しきる前に `speak` すると新しい発話が捨てられる。
        // 実際に止まるまで待ってから積み直す（読み上げが途中から鳴らなくなる原因だった）。
        synthesizer.stopSpeaking(at: .immediate)
        flushTask = Task {
            for _ in 0..<20 where synthesizer.isSpeaking {
                try? await Task.sleep(for: .milliseconds(20))
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled else { return }
            utterances.forEach(synthesizer.speak)
        }
    }

    private func makeUtterance(text: String, rate: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = englishVoice
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.25
        return utterance
    }

    /// マナーモードでも学習音声が鳴るよう `.playback` にする。
    ///
    /// カテゴリ設定・有効化は他アプリの再生中や通話中だと失敗する。
    /// 一度失敗したまま黙り続けないよう、成功するまで毎回やり直す。
    private func prepareSession() {
        let session = AVAudioSession.sharedInstance()
        if !isCategoryConfigured {
            do {
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                isCategoryConfigured = true
            } catch {
                log.error("音声カテゴリの設定に失敗: \(error.localizedDescription)")
            }
        }
        // 通話や他アプリの割り込みでセッションは無効化される。読み上げのたびに有効化し直す
        do {
            try session.setActive(true)
        } catch {
            log.error("音声セッションの有効化に失敗: \(error.localizedDescription)")
        }
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: [.notifyOthersOnDeactivation]
            )
        } catch {
            log.debug("音声セッションの無効化に失敗: \(error.localizedDescription)")
        }
    }
}
