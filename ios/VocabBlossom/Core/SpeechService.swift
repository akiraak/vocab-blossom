import AVFoundation
import Foundation

/// 英語の読み上げ（OS 内蔵 TTS）。
///
/// 「目 + 耳」のセットで単語に触れさせるため、提示カード・回答後カード・
/// リスニングクイズから呼ばれる。
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private var sessionConfigured = false

    /// 単語の読み上げ速度。既定値だと初学者には速いので少し落とす
    private let wordRate: Float = 0.42
    private let sentenceRate: Float = 0.45

    private init() {}

    /// 単語だけを読む。
    func speak(word: String) {
        enqueue([(word, wordRate)])
    }

    /// 単語 → 例文 の順に読む。リスニングクイズと提示カードで使う。
    func speak(word: String, example: String) {
        enqueue([(word, wordRate), (example, sentenceRate)])
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func enqueue(_ items: [(String, Float)]) {
        configureSessionIfNeeded()
        synthesizer.stopSpeaking(at: .immediate)
        for (text, rate) in items {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = rate
            utterance.postUtteranceDelay = 0.25
            synthesizer.speak(utterance)
        }
    }

    /// マナーモードでも学習音声が鳴るよう `.playback` にする。
    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}
