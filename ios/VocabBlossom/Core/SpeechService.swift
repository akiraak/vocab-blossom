import AVFoundation
import Foundation
import OSLog

/// 英語の読み上げ（OS 内蔵 TTS）。
///
/// 「目 + 耳」のセットで単語に触れさせるため、提示カード・回答後カード・
/// リスニングクイズから呼ばれる。
final class SpeechService: NSObject {
    static let shared = SpeechService()

    /// 実機でしか起きない不具合を追えるよう、読み上げの開始・終了を残す。
    /// Console.app で `subsystem: com.akiraak.VocabBlossom` を見る
    private nonisolated let log = Logger(
        subsystem: "com.akiraak.VocabBlossom", category: "speech"
    )

    /// 読み上げ中のインスタンス。使い回さず、読み上げのたびに作り直す（理由は `enqueue`）
    private var synthesizer: AVSpeechSynthesizer?
    /// 停止直後に解放すると落ちることがあるので、1 つ前だけ生かしておく
    private var previousSynthesizer: AVSpeechSynthesizer?

    private var deactivateTask: Task<Void, Never>?

    /// 単語の読み上げ速度。既定値だと初学者には速いので少し落とす
    private let wordRate: Float = 0.42
    private let sentenceRate: Float = 0.45

    /// 端末に英語の音声が無いと日本語音声で英文を読んでしまうので、明示的に選んでおく
    private lazy var englishVoice: AVSpeechSynthesisVoice? = {
        AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("en") }
    }()

    private override init() {
        super.init()
    }

    /// 読み上げ中かどうか。詰まりの検出（テスト）に使う
    var isSpeaking: Bool {
        synthesizer?.isSpeaking ?? false
    }

    /// 単語だけを読む。
    func speak(word: String) {
        enqueue([(word, wordRate)])
    }

    /// 単語 → 例文 の順に読む。リスニングクイズと提示カードで使う。
    func speak(word: String, example: String) {
        enqueue([(word, wordRate), (example, sentenceRate)])
    }

    /// 読み上げを止め、少し待ってからほかのアプリの音量を戻す。
    func stop() {
        discardSynthesizer()
        scheduleDeactivate()
    }

    private func enqueue(_ items: [(text: String, rate: Float)]) {
        let utterances = items
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(makeUtterance)
        guard !utterances.isEmpty else { return }

        deactivateTask?.cancel()
        LearningAudioSession.shared.activate()

        // AVSpeechSynthesizer は「発話が実際に始まる前に stopSpeaking すると、
        // 内部状態が詰まって以後まったく鳴らなくなる」ことがある。
        // （提示カードが出た直後に「もう知ってる」を押す、のように素早く切り替えた場合）
        // 止めて使い回すのをやめ、読み上げのたびにインスタンスごと作り直すことで避ける。
        discardSynthesizer()
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        self.synthesizer = synthesizer
        log.info("読み上げ開始: \(utterances.map(\.speechString).joined(separator: " / "))")
        utterances.forEach(synthesizer.speak)
    }

    private func discardSynthesizer() {
        guard let current = synthesizer else { return }
        current.stopSpeaking(at: .immediate)
        synthesizer = nil
        // 1 つ前だけ保持し、さらに前のものはここで解放する（発話直後の解放を避ける）
        previousSynthesizer = current
    }

    private func makeUtterance(text: String, rate: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = englishVoice
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.25
        return utterance
    }

    /// 読み上げ中に無効化すると失敗したり音声が詰まったりするので、少し待ってから行う。
    private func scheduleDeactivate() {
        deactivateTask?.cancel()
        deactivateTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, synthesizer == nil else { return }
            LearningAudioSession.shared.deactivate()
        }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        log.info("発話開始: \(utterance.speechString)")
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        log.info("発話終了: \(utterance.speechString)")
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        log.info("発話中断: \(utterance.speechString)")
    }
}
