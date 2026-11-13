import Foundation
import Observation

/// ユーザー設定。学習進捗と違い単純な値だけなので `UserDefaults` に置く。
@Observable
final class AppSettings {
    enum Key {
        static let level = "settings.level"
        static let newWordsPerDay = "settings.newWordsPerDay"
        static let soundEnabled = "settings.soundEnabled"
        static let effectSoundEnabled = "settings.effectSoundEnabled"
        static let hasOnboarded = "settings.hasOnboarded"
    }

    static let defaultNewWordsPerDay = 10

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        level = CefrLevel(rawValue: defaults.string(forKey: Key.level) ?? "") ?? .a1
        newWordsPerDay = defaults.object(forKey: Key.newWordsPerDay) as? Int
            ?? Self.defaultNewWordsPerDay
        soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        effectSoundEnabled = defaults.object(forKey: Key.effectSoundEnabled) as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        readAloudSpeed = ReadAloudSpeed.current(defaults: defaults)
        claudeModel = AIModelPreference.claudeModel(defaults: defaults)
        ttsModel = AIModelPreference.ttsModel(defaults: defaults)
    }

    /// 前の版の「レベル」。もう学習には使わず、画面にも出さない。
    /// バックアップの形式を変えないよう、値の保存と書き出し・読み込みだけ残す
    var level: CefrLevel {
        didSet { defaults.set(level.rawValue, forKey: Key.level) }
    }

    /// 前の版の「1 日の新しい単語」。`level` と同じくバックアップのためだけに残す
    /// （学習の上限は `StudyLimits` の固定値）
    var newWordsPerDay: Int {
        didSet { defaults.set(newWordsPerDay, forKey: Key.newWordsPerDay) }
    }

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    /// 正解・不正解の効果音。読み上げとは独立に切れるようにする
    var effectSoundEnabled: Bool {
        didSet { defaults.set(effectSoundEnabled, forKey: Key.effectSoundEnabled) }
    }

    /// 読み上げの速さ。自動の読み上げにも、スピーカーのボタンにも効く
    var readAloudSpeed: ReadAloudSpeed {
        didSet { defaults.set(readAloudSpeed.rawValue, forKey: ReadAloudSpeed.key) }
    }

    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) }
    }

    /// 自作語の AI チェック・穴埋めの文章のモデル（サーバーがあるときだけ使う）
    var claudeModel: ClaudeModel {
        didSet { defaults.set(claudeModel.rawValue, forKey: AIModelPreference.Key.claudeModel) }
    }

    /// 読み上げの声のモデル（サーバーがあるときだけ使う）
    var ttsModel: TTSModel {
        didSet { defaults.set(ttsModel.rawValue, forKey: AIModelPreference.Key.ttsModel) }
    }
}

/// 読み上げの速さ。rawValue は再生の倍率（音程は変えない）。
/// 音声は作り直さず、鳴らすときに速める。docs/plans/read-aloud-faster.md
nonisolated enum ReadAloudSpeed: Double, CaseIterable, Identifiable, Sendable {
    case slow = 0.85
    case normal = 1.0
    case littleFast = 1.15
    case fast = 1.3
    case veryFast = 1.5

    static let defaultSpeed: ReadAloudSpeed = .normal
    static let key = "settings.readAloudSpeed"

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .slow: "ゆっくり"
        case .normal: "ふつう"
        case .littleFast: "少し速い"
        case .fast: "速い"
        case .veryFast: "とても速い"
        }
    }

    /// 設定画面で選んだ速さ。鳴らすときに読む（`AppSettings` と同じ UserDefaults の値）。知らない値なら既定に戻す
    static func current(defaults: UserDefaults = .standard) -> ReadAloudSpeed {
        (defaults.object(forKey: key) as? Double)
            .flatMap(ReadAloudSpeed.init(rawValue:)) ?? .defaultSpeed
    }
}
