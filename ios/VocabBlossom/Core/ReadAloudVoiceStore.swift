import AVFoundation
import CryptoKit
import Foundation
import OSLog

/// サーバー（Gemini TTS）で作った読み上げの音声を端末に残す置き場（`Library/Caches/read-aloud/`）。
///
/// 1 文 1 ファイル。鍵は「版・読む人・種類・文」のハッシュで、版はサーバーが返す `x-speech-version`
/// （モデル・声・スタイルが変われば変わる）。読む人と種類ごとに最後に見た版を覚えておき、
/// 版が変わったら古い音声は使わずに作り直す。WAV は大きいので AAC（m4a）にして残す。
/// Caches は OS に消されることがあるが、そのときは作り直すだけ
nonisolated final class ReadAloudVoiceStore: @unchecked Sendable {
    static let shared = ReadAloudVoiceStore(directory: defaultDirectory)

    static var defaultDirectory: URL? {
        try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "read-aloud", directoryHint: .isDirectory)
    }

    private let log = Logger(subsystem: "com.akiraak.VocabBlossom", category: "read-aloud")
    private let directory: URL?
    private let lock = NSLock()
    /// 「読む人/種類」→ 最後に見た版
    private var versions: [String: String]

    private static let versionsFileName = "versions.json"
    private static let extensions = ["m4a", "wav"]

    /// directory が nil なら何も残さない（毎回サーバーから取る）
    init(directory: URL?) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if let url = directory?.appending(path: Self.versionsFileName),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            versions = decoded
        } else {
            versions = [:]
        }
    }

    static func key(version: String, request: SpeechAPI.Request) -> String {
        let source = [version, request.speaker.rawValue, request.kind.rawValue, request.text]
            .joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func versionKey(_ request: SpeechAPI.Request) -> String {
        "\(request.speaker.rawValue)/\(request.kind.rawValue)"
    }

    func version(for request: SpeechAPI.Request) -> String? {
        lock.withLock { versions[Self.versionKey(request)] }
    }

    /// 残してある音声。今の版で作ったものが無ければ nil
    func cachedURL(for request: SpeechAPI.Request) -> URL? {
        guard let directory, let version = version(for: request) else { return nil }
        let key = Self.key(version: version, request: request)
        return Self.extensions
            .map { directory.appending(path: "\(key).\($0)") }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// サーバーから届いた音声を残し、置いた場所を返す。AAC にできなければ WAV のまま残す。
    /// 残せない（directory が nil など）ときは一時ファイルに書いて返す
    func save(_ audio: SpeechAPI.Audio, for request: SpeechAPI.Request) throws -> URL {
        let key = Self.key(version: audio.version, request: request)
        let base = directory ?? FileManager.default.temporaryDirectory
        let wavURL = base.appending(path: "\(key).partial.wav")
        try audio.wav.write(to: wavURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let finalURL: URL
        if let m4aURL = try? Self.placeAAC(from: wavURL, base: base, key: key) {
            finalURL = m4aURL
        } else {
            log.error("AAC への変換に失敗（WAV のまま残す）")
            finalURL = base.appending(path: "\(key).wav")
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.copyItem(at: wavURL, to: finalURL)
        }

        if directory != nil { remember(version: audio.version, for: request) }
        return finalURL
    }

    /// 壊れていて鳴らせなかった音声を消す（次は作り直す）
    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func remember(version: String, for request: SpeechAPI.Request) {
        let snapshot: [String: String]? = lock.withLock {
            guard versions[Self.versionKey(request)] != version else { return nil }
            versions[Self.versionKey(request)] = version
            return versions
        }
        guard let snapshot, let url = directory?.appending(path: Self.versionsFileName),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 変換してから置く（途中で落ちても半端なファイルを鳴らさないように）
    private static func placeAAC(from wavURL: URL, base: URL, key: String) throws -> URL {
        let partialURL = base.appending(path: "\(key).partial.m4a")
        try? FileManager.default.removeItem(at: partialURL)
        try convertToAAC(from: wavURL, to: partialURL)
        let url = base.appending(path: "\(key).m4a")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: partialURL, to: url)
        return url
    }

    static func convertToAAC(from wavURL: URL, to outputURL: URL) throws {
        let input = try AVAudioFile(forReading: wavURL)
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.fileFormat.sampleRate,
            AVNumberOfChannelsKey: input.fileFormat.channelCount,
        ]
        let output = try AVAudioFile(
            forWriting: outputURL, settings: settings,
            commonFormat: format.commonFormat, interleaved: format.isInterleaved
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
            throw CocoaError(.fileWriteUnknown)
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
        output.close()
    }
}
