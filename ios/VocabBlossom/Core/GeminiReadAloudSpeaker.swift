import AVFoundation
import Foundation
import OSLog

/// 音声ファイルを 1 つ鳴らす部分。テストでは偽物に差し替える
protocol ReadAloudAudioPlaying: AnyObject {
    /// 鳴らし終えたら true。鳴らせなかった・`stop` で止めたら false
    func play(_ url: URL) async -> Bool
    func stop()
}

/// グループの読み上げを、サーバー（Gemini TTS）で作った Chobi / Naruko の声で読む。
///
/// - 1 語ごとに読む人をランダムに選ぶ（3 語続けて同じ人にはしない）。1 語の中は同じ人が読む
/// - 音声は端末に残し（`ReadAloudVoiceStore`）、次の数語は 2 人分を先に取っておく（`prepare`）
/// - 音声が取れない文（オフライン・サーバーの失敗・キー未設定）は、その文だけ OS 内蔵の声（`fallback`）で読む
/// - サーバーの設定が無ければ（`fetcher == nil`）、すべて内蔵の声で読む
///
/// 設計は docs/plans/read-aloud-gemini-voice.md
final class GeminiReadAloudSpeaker: ReadAloudSpeaking {
    static let shared = GeminiReadAloudSpeaker(
        fallback: ReadAloudSpeechEngine.shared,
        store: .shared,
        audio: SystemReadAloudAudioPlayer()
    )

    private nonisolated let log = Logger(subsystem: "com.akiraak.VocabBlossom", category: "read-aloud")

    /// 音声の取り先。サーバーの設定が無ければ nil（内蔵の声だけで読む）
    var fetcher: (any SpeechFetching)?
    var onInterruption: (() -> Void)?

    /// Gemini は日本語も読める。サーバーが使えないときに備えて内蔵の声の有無も見る
    var hasJapaneseVoice: Bool { fetcher != nil || fallback.hasJapaneseVoice }

    private let fallback: any ReadAloudSpeaking
    private let store: ReadAloudVoiceStore
    private let audio: any ReadAloudAudioPlaying
    private let randomSpeaker: () -> SpeechAPI.Speaker
    private let now: () -> Date
    /// 文の間・語の間（秒）。内蔵の声（`ReadAloudSpeechEngine`）とそろえる
    private let lineGap: Duration
    private let itemGap: Duration

    /// 前の `speak` の知らせを無視するための番号。読み始めるたび・止めるたびに進める
    private var generation = 0
    private var runTask: Task<Void, Never>?
    /// 内蔵の声で 1 文読んでいる間の待ち。止めたときに手で戻す
    private var fallbackWait: CheckedContinuation<Void, Never>?
    private var deactivateTask: Task<Void, Never>?
    /// 最近読んだ人（3 語続けて同じ人にしないため）
    private var recentSpeakers: [SpeechAPI.Speaker] = []

    /// 取りに行っている途中の音声（同じ文を二重に頼まない）
    private var inFlight: [SpeechAPI.Request: Task<URL?, Never>] = [:]
    private var prefetchQueue: [SpeechAPI.Request] = []
    private var prefetchRunning = 0
    /// 失敗が続くときに、しばらくサーバーへ頼まない（その間は内蔵の声で読む）
    private var unavailableUntil: Date?

    static let maxPrefetchConcurrency = 2

    init(
        fallback: any ReadAloudSpeaking,
        store: ReadAloudVoiceStore,
        audio: any ReadAloudAudioPlaying,
        fetcher: (any SpeechFetching)? = nil,
        randomSpeaker: @escaping () -> SpeechAPI.Speaker = {
            SpeechAPI.Speaker.allCases.randomElement() ?? .chobi
        },
        now: @escaping () -> Date = Date.init,
        lineGap: Duration = .milliseconds(250),
        itemGap: Duration = .milliseconds(800)
    ) {
        self.fallback = fallback
        self.store = store
        self.audio = audio
        self.fetcher = fetcher
        self.randomSpeaker = randomSpeaker
        self.now = now
        self.lineGap = lineGap
        self.itemGap = itemGap
    }

    // MARK: - ReadAloudSpeaking

    func speak(
        _ lines: [ReadAloudLine],
        onLineStart: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
        // 割り込み（通話・イヤホンが抜けた）は内蔵の声の側で見張っている。どちらで読んでいても知らせを受ける
        fallback.onInterruption = { [weak self] in self?.onInterruption?() }
        guard fetcher != nil else {
            fallback.speak(lines, onLineStart: onLineStart, onFinish: onFinish)
            return
        }

        cancelRun()
        deactivateTask?.cancel()
        SpeechService.shared.stop()
        LearningAudioSession.shared.activate(for: .readAloud)

        let speaker = chooseSpeaker(for: lines)
        let audios = lines.map { audioTask(for: Self.request(for: $0, speaker: speaker)) }
        let current = generation
        log.info("読み上げ開始（\(speaker.rawValue)）: \(lines.map(\.spokenText).joined(separator: " / "))")
        runTask = Task { [weak self] in
            await self?.run(
                lines, audios: audios, generation: current, onLineStart: onLineStart, onFinish: onFinish
            )
        }
    }

    func prepare(_ upcoming: [[ReadAloudLine]]) {
        guard fetcher != nil else { return }
        // 先の語ほど後ろ。語ごとに 2 人分（今の語は、選ばなかった人の分も取っておく）
        prefetchQueue = upcoming.flatMap { lines in
            SpeechAPI.Speaker.allCases.flatMap { speaker in
                lines.map { Self.request(for: $0, speaker: speaker) }
            }
        }
        pumpPrefetch()
    }

    func stop() {
        guard fetcher != nil else {
            fallback.stop()
            return
        }
        cancelRun()
    }

    func finish() {
        guard fetcher != nil else {
            fallback.finish()
            return
        }
        cancelRun()
        prefetchQueue = []
        // 鳴らしている途中で無効化すると失敗したり詰まったりするので、少し待ってから
        deactivateTask?.cancel()
        deactivateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, self?.runTask == nil else { return }
            LearningAudioSession.shared.deactivate(for: .readAloud)
        }
    }

    // MARK: - 読む

    static func request(for line: ReadAloudLine, speaker: SpeechAPI.Speaker) -> SpeechAPI.Request {
        SpeechAPI.Request(text: line.spokenText, speaker: speaker, kind: kind(of: line))
    }

    private static func kind(of line: ReadAloudLine) -> SpeechAPI.Kind {
        switch line.kind {
        case .word: .word
        case .example: .example
        case .meaning, .exampleJa: .japanese
        }
    }

    private func run(
        _ lines: [ReadAloudLine],
        audios: [Task<URL?, Never>],
        generation current: Int,
        onLineStart: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) async {
        for (index, line) in lines.enumerated() {
            let url = await audios[index].value
            guard generation == current else { return }
            onLineStart(index)

            var played = false
            if let url {
                played = await audio.play(url)
                guard generation == current else { return }
                if !played {
                    // 鳴らせなかった（壊れたファイルなど）。消して次は作り直す
                    store.remove(url)
                }
            }
            if !played {
                // 内蔵の声は読み終えたあとに語の間をとるので、こちらでは間をとらない
                await speakWithFallback(line)
                guard generation == current else { return }
                continue
            }

            try? await Task.sleep(for: index == lines.count - 1 ? itemGap : lineGap)
            guard generation == current else { return }
        }
        runTask = nil
        onFinish()
    }

    private func speakWithFallback(_ line: ReadAloudLine) async {
        await withCheckedContinuation { continuation in
            fallbackWait = continuation
            fallback.speak([line], onLineStart: { _ in }, onFinish: { [weak self] in
                self?.resumeFallbackWait()
            })
        }
    }

    private func resumeFallbackWait() {
        let continuation = fallbackWait
        fallbackWait = nil
        continuation?.resume()
    }

    /// 読んでいる途中でも止める。前の分の知らせ（onLineStart・onFinish）はもう呼ばない
    private func cancelRun() {
        generation += 1
        runTask?.cancel()
        runTask = nil
        audio.stop()
        fallback.stop()
        resumeFallbackWait()
    }

    /// 1 語を読む人。ランダムだが、2 語続けて同じ人なら次はもう 1 人にする。
    /// 片方の音声だけそろっている（もう片方は取れていない）なら、そろっている方で読む
    private func chooseSpeaker(for lines: [ReadAloudLine]) -> SpeechAPI.Speaker {
        var speaker = randomSpeaker()
        if recentSpeakers.count >= 2, let last = recentSpeakers.last,
           recentSpeakers.suffix(2).allSatisfy({ $0 == last }) {
            speaker = Self.other(than: last)
        }
        let ready = SpeechAPI.Speaker.allCases.filter { candidate in
            lines.allSatisfy { store.cachedURL(for: Self.request(for: $0, speaker: candidate)) != nil }
        }
        if ready.count == 1, let only = ready.first {
            speaker = only
        }
        recentSpeakers = Array((recentSpeakers + [speaker]).suffix(2))
        return speaker
    }

    private static func other(than speaker: SpeechAPI.Speaker) -> SpeechAPI.Speaker {
        speaker == .chobi ? .naruko : .chobi
    }

    // MARK: - 音声を取る

    private var isServerAvailable: Bool {
        guard let until = unavailableUntil else { return true }
        return now() >= until
    }

    /// 文の音声。残してあればそれ、無ければサーバーへ頼む（取れなければ nil）
    private func audioTask(for request: SpeechAPI.Request) -> Task<URL?, Never> {
        if let url = store.cachedURL(for: request) {
            return Task { url }
        }
        if let running = inFlight[request] { return running }
        guard let fetcher, isServerAvailable else { return Task { nil } }

        let store = store
        let task = Task<URL?, Never> { [weak self] in
            do {
                let audio = try await fetcher.fetch(request)
                return try await Task.detached { try store.save(audio, for: request) }.value
            } catch {
                self?.serverFailed(error, request: request)
                return nil
            }
        }
        inFlight[request] = task
        Task { [weak self] in
            _ = await task.value
            self?.inFlight[request] = nil
        }
        return task
    }

    private func serverFailed(_ error: any Error, request: SpeechAPI.Request) {
        // キー未設定・認証の失敗・上限はしばらく直らないので長めに休む。通信の失敗は短く
        let pause: TimeInterval
        switch error as? WordAssistError {
        case .unavailable, .unauthorized, .rateLimited: pause = 300
        default: pause = 30
        }
        unavailableUntil = now().addingTimeInterval(pause)
        prefetchQueue = []
        log.error("読み上げの音声を取れなかった（\(Int(pause)) 秒は内蔵の声で読む）: \(request.text) \(error.localizedDescription)")
    }

    private func pumpPrefetch() {
        while prefetchRunning < Self.maxPrefetchConcurrency, isServerAvailable, !prefetchQueue.isEmpty {
            let request = prefetchQueue.removeFirst()
            guard store.cachedURL(for: request) == nil, inFlight[request] == nil else { continue }
            let task = audioTask(for: request)
            prefetchRunning += 1
            Task { [weak self] in
                _ = await task.value
                guard let self else { return }
                prefetchRunning -= 1
                pumpPrefetch()
            }
        }
    }
}

/// `AVAudioPlayer` で 1 ファイルずつ鳴らす
final class SystemReadAloudAudioPlayer: NSObject, ReadAloudAudioPlaying, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Bool, Never>?

    func play(_ url: URL) async -> Bool {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.delegate = self
        self.player = player
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let started = player.play()
            if !started {
                self.player = nil
                resume(false)
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        resume(false)
    }

    private func resume(_ finished: Bool) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: finished)
    }

    private func handleEnd(of playerId: ObjectIdentifier, successfully: Bool) {
        guard player.map(ObjectIdentifier.init) == playerId else { return }
        player = nil
        resume(successfully)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerId = ObjectIdentifier(player)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.handleEnd(of: playerId, successfully: flag) }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let playerId = ObjectIdentifier(player)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.handleEnd(of: playerId, successfully: false) }
        }
    }
}
