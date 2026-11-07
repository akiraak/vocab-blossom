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
