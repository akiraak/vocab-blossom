import Accelerate
import AVFoundation
import CryptoKit
import Foundation
import OSLog

/// サーバー（Gemini TTS）で作った読み上げの音声を端末に残す置き場（`Library/Caches/read-aloud/`）。
///
/// 1 文 1 ファイル。鍵は「版・モデル・読む人・種類・文」のハッシュで、版はサーバーが返す `x-speech-version`
/// （モデル・声・スタイルが変われば変わる）。モデル・読む人・種類ごとに最後に見た版を覚えておき、
/// 版が変わったら古い音声は使わずに作り直す。WAV は大きいので AAC（m4a）にして残す。
/// Caches は OS に消されることがあるが、そのときは作り直すだけ。
///
/// Gemini の音声はピークがほぼ上限（-1 dBFS 前後）で大きく、AAC にして鳴らすと上限を超えて
/// iPhone のスピーカーで割れて聞こえる。残すときに大きさをそろえ（RMS -20 dBFS、ピークは -4 dBFS まで）、
/// AAC は 64 kbps にする（2026-11-04、docs/plans/read-aloud-gemini-voice.md）
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
    private static let formatFileName = "format"
    private static let extensions = ["m4a", "wav"]

    /// 残し方（大きさのそろえ方・AAC の設定）の版。変えたら上げると、残してある音声をすべて消して作り直す
    /// 3: 鍵と版にモデルを入れた（設定画面で TTS のモデルを選べるようにした）
    static let formatVersion = "3"

    /// 大きさのそろえ方: 平均（RMS）を -20 dBFS に、ただしピークは -4 dBFS を超えない、上げるのは +6 dB まで
    static let targetRMS: Float = 0.1
    static let peakCeiling: Float = 0.631
    static let maxGain: Float = 2.0
    static let aacBitRate = 64_000

    /// directory が nil なら何も残さない（毎回サーバーから取る）
    init(directory: URL?) {
        self.directory = directory
        if let directory {
            Self.prepareDirectory(directory)
        }
        if let url = directory?.appending(path: Self.versionsFileName),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            versions = decoded
        } else {
            versions = [:]
        }
    }

    /// 置き場を作る。残し方の版が違えば（古いアプリで残した音声なら）中身を消す
    private static func prepareDirectory(_ directory: URL) {
        let manager = FileManager.default
        let formatURL = directory.appending(path: formatFileName)
        let current = (try? String(contentsOf: formatURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != formatVersion else { return }
        if let contents = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            contents.forEach { try? manager.removeItem(at: $0) }
        }
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(formatVersion.utf8).write(to: formatURL, options: .atomic)
    }

    static func key(version: String, request: SpeechAPI.Request) -> String {
        let source = [
            version, request.model.rawValue, request.speaker.rawValue, request.kind.rawValue, request.text,
        ].joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func versionKey(_ request: SpeechAPI.Request) -> String {
        "\(request.model.rawValue)/\(request.speaker.rawValue)/\(request.kind.rawValue)"
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

    /// 大きさをそろえる倍率（ピーク・RMS は 0〜1）
    static func normalizationGain(peak: Float, rms: Float) -> Float {
        guard peak > 0, rms > 0 else { return 1 }
        return min(targetRMS / rms, peakCeiling / peak, maxGain)
    }

    /// WAV を読み、大きさをそろえて AAC で書く（1 文は数秒なので、まとめて読む）
    static func convertToAAC(from wavURL: URL, to outputURL: URL) throws {
        let input = try AVAudioFile(forReading: wavURL)
        let format = input.processingFormat
        guard input.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length))
        else { throw CocoaError(.fileReadCorruptFile) }
        try input.read(into: buffer)
        normalize(buffer)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.fileFormat.sampleRate,
            AVNumberOfChannelsKey: input.fileFormat.channelCount,
            AVEncoderBitRateKey: aacBitRate,
        ]
        let output = try AVAudioFile(
            forWriting: outputURL, settings: settings,
            commonFormat: format.commonFormat, interleaved: format.isInterleaved
        )
        try output.write(from: buffer)
        output.close()
    }

    private static func normalize(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = vDSP_Length(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard count > 0 else { return }
        var peak: Float = 0
        var sumOfSquares: Float = 0
        for channel in 0..<channelCount {
            var channelPeak: Float = 0
            var channelSum: Float = 0
            vDSP_maxmgv(channels[channel], 1, &channelPeak, count)
            vDSP_svesq(channels[channel], 1, &channelSum, count)
            peak = max(peak, channelPeak)
            sumOfSquares += channelSum
        }
        let rms = (sumOfSquares / Float(Int(count) * channelCount)).squareRoot()
        var gain = normalizationGain(peak: peak, rms: rms)
        for channel in 0..<channelCount {
            vDSP_vsmul(channels[channel], 1, &gain, channels[channel], 1, count)
        }
    }
}
