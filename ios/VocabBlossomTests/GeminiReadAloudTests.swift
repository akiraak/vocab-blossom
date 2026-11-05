import AVFoundation
import Foundation
import Testing

@testable import VocabBlossom

// MARK: - 偽物

/// 無音の WAV（24kHz mono 16bit）
nonisolated private func silentWAV(seconds: Double = 0.1, sampleRate: Int = 24000) -> Data {
    let pcm = Data(count: Int(seconds * Double(sampleRate)) * 2)
    var wav = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
    }
    wav.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + pcm.count))
    wav.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))
    append(UInt16(2))
    append(UInt16(16))
    wav.append(contentsOf: Array("data".utf8))
    append(UInt32(pcm.count))
    wav.append(pcm)
    return wav
}

/// 頼まれた文を覚えて、無音の WAV を返すサーバーの偽物。決めた文だけ失敗させられる
private final class FakeSpeechFetcher: SpeechFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [SpeechAPI.Request] = []
    private var failingTexts: Set<String> = []
    private var failAll = false
    private var currentVersion = "v1"
    private let error: WordAssistError

    init(error: WordAssistError = .offline) {
        self.error = error
    }

    var recorded: [SpeechAPI.Request] { lock.withLock { calls } }

    func fail(_ texts: Set<String>) { lock.withLock { failingTexts = texts } }
    func failEverything(_ value: Bool) { lock.withLock { failAll = value } }

    func fetch(_ request: SpeechAPI.Request) async throws -> SpeechAPI.Audio {
        let (fails, version) = lock.withLock {
            calls.append(request)
            return (failAll || failingTexts.contains(request.text), currentVersion)
        }
        if fails { throw error }
        return SpeechAPI.Audio(wav: silentWAV(), version: version)
    }
}

/// 鳴らしたファイルを覚える。既定はすぐ鳴らし終える。`holds` なら `stop` まで鳴らし続ける
private final class FakeAudioPlayer: ReadAloudAudioPlaying {
    var holds = false
    private(set) var played: [URL] = []
    private(set) var stopCount = 0
    private var waiting: CheckedContinuation<Bool, Never>?

    func play(_ url: URL) async -> Bool {
        played.append(url)
        if holds {
            return await withCheckedContinuation { waiting = $0 }
        }
        await Task.yield()
        return true
    }

    func stop() {
        stopCount += 1
        let continuation = waiting
        waiting = nil
        continuation?.resume(returning: false)
    }
}

/// 内蔵の声の偽物。頼まれた文を覚えて、すぐ読み終えたことにする
private final class InstantFallbackSpeaker: ReadAloudSpeaking {
    var hasJapaneseVoice = false
    var onInterruption: (() -> Void)?
    private(set) var spoken: [[ReadAloudLine]] = []
    private(set) var finishCount = 0

    func speak(
        _ lines: [ReadAloudLine],
        onLineStart: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
        spoken.append(lines)
        Task {
            lines.indices.forEach(onLineStart)
            onFinish()
        }
    }

    func stop() {}

    func finish() {
        finishCount += 1
    }
}

private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

private func line(_ kind: ReadAloudLine.Kind, _ text: String) -> ReadAloudLine {
    ReadAloudLine(kind: kind, text: text, spokenText: text, senseIndex: 0)
}

private func lines(_ word: String) -> [ReadAloudLine] {
    [
        line(.word, word),
        line(.meaning, "\(word) の意味"),
        line(.example, "This is \(word)."),
        line(.exampleJa, "これは \(word) です。"),
    ]
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "read-aloud-test-\(UUID().uuidString)")
}

private func temporaryStore() -> ReadAloudVoiceStore {
    ReadAloudVoiceStore(directory: temporaryDirectory())
}

/// 条件がそろうまで待つ（最大 5 秒）
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<500 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private struct Harness {
    let speaker: GeminiReadAloudSpeaker
    let fetcher: FakeSpeechFetcher
    let audio: FakeAudioPlayer
    let fallback: InstantFallbackSpeaker
    let store: ReadAloudVoiceStore
    let clock: Box<Date>

    init(
        fetcher: FakeSpeechFetcher = FakeSpeechFetcher(),
        withFetcher: Bool = true,
        speakers: [SpeechAPI.Speaker] = [.chobi]
    ) {
        let audio = FakeAudioPlayer()
        let fallback = InstantFallbackSpeaker()
        let store = temporaryStore()
        let clock = Box(Date(timeIntervalSince1970: 1_000_000))
        let queue = Box(speakers)
        self.speaker = GeminiReadAloudSpeaker(
            fallback: fallback, store: store, audio: audio,
            fetcher: withFetcher ? fetcher : nil,
            randomSpeaker: {
                // 決めた並びを順に返し、尽きたら最後のものを返し続ける
                queue.value.count > 1 ? queue.value.removeFirst() : (queue.value.first ?? .chobi)
            },
            now: { clock.value },
            lineGap: .zero, itemGap: .zero
        )
        self.fetcher = fetcher
        self.audio = audio
        self.fallback = fallback
        self.store = store
        self.clock = clock
    }

    /// 1 語を読み終えるまで待ち、読み始めた文の位置を返す
    @discardableResult
    func speakToEnd(_ lines: [ReadAloudLine]) async -> [Int] {
        let started = Box<[Int]>([])
        await withCheckedContinuation { continuation in
            speaker.speak(
                lines,
                onLineStart: { started.value.append($0) },
                onFinish: { continuation.resume() }
            )
        }
        return started.value
    }
}

// MARK: - 声

@Suite("読み上げの声（Gemini）")
struct GeminiReadAloudSpeakerTests {
    @Test("サーバーの音声を順に鳴らし、文ごとに onLineStart、最後に onFinish")
    func playsServerAudio() async {
        let harness = Harness()
        let started = await harness.speakToEnd(lines("apple"))

        #expect(started == [0, 1, 2, 3])
        #expect(harness.audio.played.count == 4)
        #expect(harness.fallback.spoken.isEmpty)
        let requests = harness.fetcher.recorded
        #expect(Set(requests.map(\.kind)) == [.word, .japanese, .example])
        #expect(requests.allSatisfy { $0.speaker == .chobi })
        #expect(Set(requests.map(\.text)) == Set(lines("apple").map(\.spokenText)))
    }

    @Test("文の種類はサーバーの種類に直す（意味・和訳は japanese）")
    func requestKinds() {
        let kinds = lines("apple").map { GeminiReadAloudSpeaker.request(for: $0, speaker: .naruko).kind }
        #expect(kinds == [.word, .japanese, .example, .japanese])
    }

    @Test("残した音声は次から使い、サーバーへは頼まない")
    func usesCache() async {
        let harness = Harness()
        await harness.speakToEnd(lines("apple"))
        await harness.speakToEnd(lines("apple"))
        #expect(harness.fetcher.recorded.count == 4)
        #expect(harness.audio.played.count == 8)
    }

    @Test("取れなかった文だけ内蔵の声で読む")
    func fallsBackPerLine() async {
        let harness = Harness()
        harness.fetcher.fail(["apple の意味"])
        let started = await harness.speakToEnd(lines("apple"))

        #expect(started == [0, 1, 2, 3])
        #expect(harness.fallback.spoken.map { $0.map(\.text) } == [["apple の意味"]])
        #expect(harness.audio.played.count == 3)
    }

    @Test("失敗したらしばらくはサーバーへ頼まず内蔵の声で読み、時間がたてばまた頼む")
    func pausesAfterFailure() async {
        let harness = Harness(fetcher: FakeSpeechFetcher(error: .unavailable))
        harness.fetcher.failEverything(true)
        await harness.speakToEnd(lines("apple"))
        let afterFirst = harness.fetcher.recorded.count
        #expect(harness.fallback.spoken.count == 4)

        await harness.speakToEnd(lines("banana"))
        #expect(harness.fetcher.recorded.count == afterFirst)
        #expect(harness.fallback.spoken.count == 8)

        harness.fetcher.failEverything(false)
        harness.clock.value = harness.clock.value.addingTimeInterval(301)
        await harness.speakToEnd(lines("banana"))
        #expect(harness.fetcher.recorded.count == afterFirst + 4)
        #expect(harness.fallback.spoken.count == 8)
    }

    @Test("サーバーの設定が無ければ、すべて内蔵の声に任せる")
    func withoutServer() async {
        let harness = Harness(withFetcher: false)
        #expect(harness.speaker.hasJapaneseVoice == false)
        await harness.speakToEnd(lines("apple"))
        #expect(harness.fallback.spoken.map(\.count) == [4])
        #expect(harness.audio.played.isEmpty)

        harness.speaker.finish()
        #expect(harness.fallback.finishCount == 1)
    }

    @Test("サーバーがあれば日本語も読める")
    func japaneseWithServer() {
        #expect(Harness().speaker.hasJapaneseVoice)
    }

    @Test("止めたら鳴らすのをやめ、前の分の onFinish は呼ばない")
    func stopSilences() async {
        let harness = Harness()
        harness.audio.holds = true
        let finished = Box(false)
        harness.speaker.speak(lines("apple"), onLineStart: { _ in }, onFinish: { finished.value = true })
        await waitUntil { harness.audio.played.count == 1 }
        #expect(harness.audio.played.count == 1)

        harness.speaker.stop()
        for _ in 0..<20 { await Task.yield() }
        #expect(harness.audio.played.count == 1)
        #expect(finished.value == false)
    }

    @Test("3 語続けて同じ人にはしない")
    func alternatesSpeakers() async {
        let harness = Harness(speakers: [.chobi])
        for word in ["a", "b", "c", "d"] {
            await harness.speakToEnd(lines(word))
        }
        let speakerByWord = Dictionary(
            harness.fetcher.recorded.filter { $0.kind == .word }.map { ($0.text, $0.speaker) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(speakerByWord == ["a": .chobi, "b": .chobi, "c": .naruko, "d": .chobi])
    }

    @Test("片方の人の音声だけそろっていれば、そろっている方で読む")
    func prefersReadySpeaker() async {
        let harness = Harness(speakers: [.naruko, .chobi])
        await harness.speakToEnd(lines("apple"))
        await harness.speakToEnd(lines("apple"))
        #expect(harness.fetcher.recorded.count == 4)
        #expect(harness.fetcher.recorded.allSatisfy { $0.speaker == .naruko })
    }

    @Test("prepare で、これから読む語の音声を 2 人分取っておく")
    func prefetchesBothSpeakers() async {
        let harness = Harness()
        harness.speaker.prepare([lines("apple"), lines("banana")])
        await waitUntil { harness.fetcher.recorded.count == 16 }

        let expected = Set(
            SpeechAPI.Speaker.allCases.flatMap { speaker in
                (lines("apple") + lines("banana")).map {
                    GeminiReadAloudSpeaker.request(for: $0, speaker: speaker)
                }
            }
        )
        #expect(Set(harness.fetcher.recorded) == expected)
        #expect(harness.fetcher.recorded.count == 16)

        // 取っておいた音声で読む（サーバーへは頼まない）
        await harness.speakToEnd(lines("banana"))
        #expect(harness.fetcher.recorded.count == 16)
    }
}

// MARK: - 置き場

@Suite("読み上げの音声の置き場")
struct ReadAloudVoiceStoreTests {
    private let request = SpeechAPI.Request(text: "apple", speaker: .chobi, kind: .word)

    @Test("鍵は版・読む人・種類・文のどれかが変われば変わる")
    func keys() {
        let base = ReadAloudVoiceStore.key(version: "v1", request: request)
        #expect(ReadAloudVoiceStore.key(version: "v1", request: request) == base)
        #expect(ReadAloudVoiceStore.key(version: "v2", request: request) != base)
        var other = request
        other.speaker = .naruko
        #expect(ReadAloudVoiceStore.key(version: "v1", request: other) != base)
        other = request
        other.kind = .example
        #expect(ReadAloudVoiceStore.key(version: "v1", request: other) != base)
        other = request
        other.text = "apples"
        #expect(ReadAloudVoiceStore.key(version: "v1", request: other) != base)
    }

    @Test("WAV を m4a にして残し、同じ文は次から残したものを返す")
    func savesAsAAC() throws {
        let store = temporaryStore()
        #expect(store.cachedURL(for: request) == nil)

        let url = try store.save(SpeechAPI.Audio(wav: silentWAV(seconds: 0.5), version: "v1"), for: request)
        #expect(url.pathExtension == "m4a")
        #expect(store.cachedURL(for: request) == url)

        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        #expect(abs(seconds - 0.5) < 0.1)
    }

    @Test("版は覚えておき（作り直しても使える）、版が変われば古い音声は使わない")
    func versions() throws {
        let directory = temporaryDirectory()
        let store = ReadAloudVoiceStore(directory: directory)
        _ = try store.save(SpeechAPI.Audio(wav: silentWAV(), version: "v1"), for: request)

        let reopened = ReadAloudVoiceStore(directory: directory)
        #expect(reopened.cachedURL(for: request) != nil)

        // 同じ人・種類で新しい版の音声が届いたら、前の版の音声は使わない
        let other = SpeechAPI.Request(text: "banana", speaker: .chobi, kind: .word)
        _ = try reopened.save(SpeechAPI.Audio(wav: silentWAV(), version: "v2"), for: other)
        #expect(reopened.cachedURL(for: request) == nil)
        #expect(reopened.cachedURL(for: other) != nil)
        // 別の人の版は変わらない
        #expect(reopened.version(for: SpeechAPI.Request(text: "x", speaker: .naruko, kind: .word)) == nil)
    }

    @Test("置き場が無ければ残さない（一時ファイルで鳴らす）")
    func withoutDirectory() throws {
        let store = ReadAloudVoiceStore(directory: nil)
        let url = try store.save(SpeechAPI.Audio(wav: silentWAV(), version: "v1"), for: request)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(store.cachedURL(for: request) == nil)
    }
}

// MARK: - 通信

@Suite("読み上げの声: 通信")
struct SpeechClientTests {
    private let config = ServerConfig(baseURL: URL(string: "https://vocab.example.com")!, apiKey: "secret")

    @Test("Bearer つきで文・人・種類を送り、WAV と版を受け取る")
    func sendsAndReceives() async throws {
        let sent = RequestCapture()
        let wav = silentWAV()
        let headers = ["Content-Type": "audio/wav", "X-Speech-Version": "abc123"]
        let session = StubURLProtocol.session(headers: headers) { request, body in
            sent.set(request, body)
            return (200, wav)
        }
        let audio = try await SpeechClient(config: config, session: session)
            .fetch(SpeechAPI.Request(text: "sit down", speaker: .naruko, kind: .word))

        #expect(audio.wav == wav)
        #expect(audio.version == "abc123")
        let (request, body) = try #require(sent.value)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://vocab.example.com/api/speech")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let sentJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sentJSON == ["text": "sit down", "speaker": "naruko", "kind": "word"])
    }

    @Test("状態コードは AI チェックと同じエラーにする")
    func statusErrors() async {
        let cases: [(Int, WordAssistError)] = [
            (401, .unauthorized), (429, .rateLimited), (502, .failed), (503, .unavailable),
        ]
        for (status, expected) in cases {
            let session = StubURLProtocol.session { _, _ in (status, Data("{}".utf8)) }
            await #expect(throws: expected) {
                try await SpeechClient(config: config, session: session)
                    .fetch(SpeechAPI.Request(text: "a", speaker: .chobi, kind: .word))
            }
        }
    }

    @Test("版のヘッダが無い返事は受け取らない")
    func requiresVersion() async {
        let session = StubURLProtocol.session(headers: ["Content-Type": "audio/wav"]) { _, _ in
            (200, silentWAV())
        }
        await #expect(throws: WordAssistError.invalidResponse) {
            try await SpeechClient(config: config, session: session)
                .fetch(SpeechAPI.Request(text: "a", speaker: .chobi, kind: .word))
        }
    }
}
