import AVFoundation
import Foundation
import OSLog

/// OS 内蔵 TTS で声を出す部分。Gemini の声（`GeminiReadAloudSpeaker`）が取れない文を読む。
///
/// 「読み終えたら次の語へ」のために読み終わりを知らせ、日本語の声でも読む
final class ReadAloudSpeechEngine: NSObject, ReadAloudSpeaking {
    /// グループの読み上げ（ほかのアプリの音を止める）
    static let shared = ReadAloudSpeechEngine(purpose: .readAloud)
    /// 学習中の読み上げで、Gemini の声が取れない文を読む（ほかのアプリの音は小さくするだけ）
    static let quiz = ReadAloudSpeechEngine(purpose: .learning)

    /// 音声セッションの使い道
    private let purpose: LearningAudioSession.Purpose

    private nonisolated let log = Logger(
        subsystem: "com.akiraak.VocabBlossom", category: "read-aloud"
    )

    var onInterruption: (() -> Void)?

    /// 読み上げ中のインスタンス。読み終えて次の語へ進むときは使い回し、途中で止めたら作り直す
    /// （`AVSpeechSynthesizer` は発話が実際に始まる前に止めると、内部状態が詰まって以後鳴らなくなることがあるため）
    private var synthesizer: AVSpeechSynthesizer?
    /// 停止直後に解放すると落ちることがあるので、1 つ前だけ生かしておく
    private var previousSynthesizer: AVSpeechSynthesizer?

    /// 読んでいる文の並び。読み終えた・止めたら nil
    private var request: Request?
    private var deactivateTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private struct Request {
        /// 読み終わりの知らせと照らし合わせるので、読み終えるまで保持する（解放後に ID が使い回されないように）
        var utterances: [AVSpeechUtterance]
        var utteranceIds: [ObjectIdentifier] { utterances.map(ObjectIdentifier.init) }
        var onLineStart: (Int) -> Void
        var onFinish: () -> Void
    }

    /// 「ふつう」のときの速さ。見出し語は既定値（0.5）だと初学者には速いので少し落とす。
    /// 例文は Gemini の声を速くしたのに合わせて既定値にした（2026-11-12）。日本語は実機で聞いて決める
    static let wordRate: Float = 0.42
    static let sentenceRate: Float = 0.5
    static let japaneseRate: Float = 0.5
    /// 設定画面で選んだ速さ。文を読み始めるたびに読む
    private let speed: () -> ReadAloudSpeed = { ReadAloudSpeed.current() }

    /// 設定の速さをかけた `AVSpeechUtterance.rate`。内蔵の声の rate は倍率と比例しないので、だいたいの合わせ方
    nonisolated static func utteranceRate(_ base: Float, speed: ReadAloudSpeed) -> Float {
        let rate = base * Float(speed.rawValue)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }
    /// 文と文の間・語と語の間（秒）
    private let lineGap: TimeInterval = 0.25
    private let itemGap: TimeInterval = 0.8

    private let englishVoice: AVSpeechSynthesisVoice? =
        AVSpeechSynthesisVoice(language: "en-US")
        ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("en") }
    private let japaneseVoice: AVSpeechSynthesisVoice? =
        AVSpeechSynthesisVoice(language: "ja-JP")
        ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix("ja") }

    var hasJapaneseVoice: Bool { japaneseVoice != nil }

    private init(purpose: LearningAudioSession.Purpose) {
        self.purpose = purpose
        super.init()
        observeAudioSession()
    }

    func speak(
        _ lines: [ReadAloudLine],
        onLineStart: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
        deactivateTask?.cancel()
        LearningAudioSession.shared.activate(for: purpose)

        // 読んでいる途中で次を頼まれた（前後の語へ動いた）なら、止めて作り直す
        if request != nil { discardSynthesizer() }

        let utterances = lines.enumerated().map { offset, line in
            makeUtterance(line, isLast: offset == lines.count - 1)
        }
        guard !utterances.isEmpty else {
            request = nil
            Task { onFinish() }
            return
        }

        let synthesizer = synthesizer ?? makeSynthesizer()
        request = Request(
            utterances: utterances,
            onLineStart: onLineStart,
            onFinish: onFinish
        )
        log.info("読み上げ開始: \(utterances.map(\.speechString).joined(separator: " / "))")
        utterances.forEach(synthesizer.speak)
    }

    func stop() {
        request = nil
        discardSynthesizer()
    }

    func finish() {
        stop()
        // 読み上げ中に無効化すると失敗したり詰まったりするので、少し待ってから
        deactivateTask?.cancel()
        deactivateTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, request == nil else { return }
            LearningAudioSession.shared.deactivate(for: purpose)
        }
    }

    // MARK: -

    private func makeSynthesizer() -> AVSpeechSynthesizer {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        self.synthesizer = synthesizer
        return synthesizer
    }

    private func discardSynthesizer() {
        guard let current = synthesizer else { return }
        current.stopSpeaking(at: .immediate)
        synthesizer = nil
        previousSynthesizer = current
    }

    private func makeUtterance(_ line: ReadAloudLine, isLast: Bool) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: line.spokenText)
        switch line.kind {
        case .word:
            utterance.voice = englishVoice
            utterance.rate = Self.utteranceRate(Self.wordRate, speed: speed())
        case .example:
            utterance.voice = englishVoice
            utterance.rate = Self.utteranceRate(Self.sentenceRate, speed: speed())
        case .meaning, .exampleJa:
            utterance.voice = japaneseVoice
            utterance.rate = Self.utteranceRate(Self.japaneseRate, speed: speed())
        }
        utterance.postUtteranceDelay = isLast ? itemGap : lineGap
        return utterance
    }

    private func handleStart(synthesizer: ObjectIdentifier, utterance: ObjectIdentifier) {
        guard synthesizer == self.synthesizer.map(ObjectIdentifier.init),
              let request,
              let line = request.utteranceIds.firstIndex(of: utterance) else { return }
        request.onLineStart(line)
    }

    private func handleFinish(synthesizer: ObjectIdentifier, utterance: ObjectIdentifier) {
        guard synthesizer == self.synthesizer.map(ObjectIdentifier.init),
              let request,
              utterance == request.utteranceIds.last else { return }
        self.request = nil
        request.onFinish()
    }

    /// 通話・ほかのアプリの再生が始まったとき、イヤホンが抜けたときに知らせる
    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType.flatMap(AVAudioSession.InterruptionType.init) == .began else { return }
            MainActor.assumeIsolated { self?.interrupted(reason: "割り込み") }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = rawReason.flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.interrupted(reason: "出力先が外れた") }
        })
    }

    private func interrupted(reason: String) {
        guard purpose == .readAloud, LearningAudioSession.shared.isReadAloudActive else { return }
        log.info("読み上げを一時停止: \(reason)")
        onInterruption?()
    }
}

extension ReadAloudSpeechEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let synthesizerId = ObjectIdentifier(synthesizer)
        let utteranceId = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.handleStart(synthesizer: synthesizerId, utterance: utteranceId)
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let synthesizerId = ObjectIdentifier(synthesizer)
        let utteranceId = ObjectIdentifier(utterance)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.handleFinish(synthesizer: synthesizerId, utterance: utteranceId)
            }
        }
    }
}
