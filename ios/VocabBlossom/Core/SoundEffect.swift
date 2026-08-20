import AVFoundation
import Foundation

/// 正解・不正解の効果音の波形。
///
/// 音声ファイルは同梱せず、クイズ番組式の「ピンポン / ブッブー」をコードで合成する
/// （アセット管理を増やさず、音の調整も数値の変更で済ませるため）。
/// システムサウンドはマナーモードで鳴らないので、読み上げと同じ `.playback` セッションで鳴らす。
enum SoundEffect: CaseIterable {
    case correct
    case incorrect

    static let sampleRate = 22_050

    /// 純音の重ね合わせで作る 1 音。
    struct Segment {
        /// 基本周波数（Hz）。0 なら休符
        var frequency: Double
        /// 長さ（秒）
        var duration: Double
        /// 倍音（基本周波数の倍率と音量）。音色はここで作る
        var partials: [(multiple: Double, level: Double)] = [(1, 1)]
        /// 音量（0〜1）。倍音の合計と掛けてもクリップしない値にする
        var amplitude: Double = 0
        /// true なら鳴らした直後から減衰させる（チャイム）。false は一定音量（ブザー）
        var decays: Bool = true
    }

    /// チャイムの音色: 正弦波 + かすかな 2 倍音で澄んだ「ピン」にする
    private static let chime: [(multiple: Double, level: Double)] = [(1, 1.0), (2, 0.25)]
    /// ブザーの音色: 奇数倍音を重ねて「ブー」にする。
    /// iPhone のスピーカーは低域が出ないので、倍音側で聞こえを確保する
    private static let buzz: [(multiple: Double, level: Double)] = [(1, 1.0), (3, 0.33), (5, 0.2)]

    var segments: [Segment] {
        switch self {
        case .correct:
            // 「ピンポン」: 4 度上がる 2 音（G5 → C6）
            [
                Segment(frequency: 784.0, duration: 0.12, partials: Self.chime, amplitude: 0.55),
                Segment(frequency: 1046.5, duration: 0.32, partials: Self.chime, amplitude: 0.55),
            ]
        case .incorrect:
            // 「ブッブー」: 低いブザー 2 連。2 音目を長くして「終わり」を出す
            [
                Segment(frequency: 196.0, duration: 0.12, partials: Self.buzz,
                        amplitude: 0.4, decays: false),
                Segment(frequency: 0, duration: 0.06),
                Segment(frequency: 196.0, duration: 0.22, partials: Self.buzz,
                        amplitude: 0.4, decays: false),
            ]
        }
    }

    /// 全セグメントを 1 本の波形（-1〜1 のサンプル列）にする。
    func samples(sampleRate: Int = SoundEffect.sampleRate) -> [Float] {
        var result: [Float] = []
        for segment in segments {
            let count = Int(segment.duration * Double(sampleRate))
            guard segment.frequency > 0, segment.amplitude > 0 else {
                result.append(contentsOf: repeatElement(0, count: count))
                continue
            }
            for index in 0..<count {
                let time = Double(index) / Double(sampleRate)
                let tone = segment.partials.reduce(0.0) { sum, partial in
                    sum + partial.level
                        * sin(2 * .pi * segment.frequency * partial.multiple * time)
                }
                let envelope = Self.envelope(
                    at: time, duration: segment.duration, decays: segment.decays
                )
                result.append(Float(tone * segment.amplitude * envelope))
            }
        }
        return result
    }

    /// 16bit モノラルの WAV に包む。`AVAudioPlayer` にそのまま渡せる
    func wavData(sampleRate: Int = SoundEffect.sampleRate) -> Data {
        Self.wavData(samples: samples(sampleRate: sampleRate), sampleRate: sampleRate)
    }

    /// 音量カーブ。鳴り始めと終わりを無音に近づけて「プチッ」というノイズを出さない
    private static func envelope(at time: Double, duration: Double, decays: Bool) -> Double {
        let attack = min(time / 0.005, 1)
        if decays {
            let remain = 1 - time / duration
            return attack * remain * remain
        }
        let release = min((duration - time) / 0.01, 1)
        return min(attack, release)
    }

    static func wavData(samples: [Float], sampleRate: Int) -> Data {
        var body = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            append(UInt16(bitPattern: Int16(clamped * 32_767)), to: &body)
        }

        var data = Data(capacity: 44 + body.count)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + body.count), to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)                 // fmt チャンクの長さ
        append(UInt16(1), to: &data)                  // リニア PCM
        append(UInt16(1), to: &data)                  // モノラル
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)     // バイトレート
        append(UInt16(2), to: &data)                  // ブロック境界
        append(UInt16(16), to: &data)                 // ビット深度
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(body.count), to: &data)
        data.append(body)
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}

/// 効果音の再生。合成した WAV をあらかじめ読み込んでおき、鳴らすだけの薄い層。
final class SoundEffectService {
    static let shared = SoundEffectService()

    private let players: [SoundEffect: AVAudioPlayer]

    init() {
        players = Dictionary(
            uniqueKeysWithValues: SoundEffect.allCases.compactMap { effect in
                guard let player = try? AVAudioPlayer(data: effect.wavData()) else { return nil }
                player.prepareToPlay()
                return (effect, player)
            }
        )
    }

    func play(_ effect: SoundEffect) {
        guard let player = players[effect] else { return }
        LearningAudioSession.shared.activate()
        player.currentTime = 0
        player.play()
    }
}
