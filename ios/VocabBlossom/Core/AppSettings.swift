import Foundation
import Observation

/// ユーザー設定。学習進捗と違い単純な値だけなので `UserDefaults` に置く。
@Observable
final class AppSettings {
    enum Key {
        static let level = "settings.level"
        static let newWordsPerDay = "settings.newWordsPerDay"
        static let soundEnabled = "settings.soundEnabled"
        static let hasOnboarded = "settings.hasOnboarded"
    }

    static let newWordsPerDayChoices = [5, 10, 15, 20, 30, 50, 100]
    static let defaultNewWordsPerDay = 10
    static let minReviewLimitPerDay = 60
    /// 1 語は開花までに 5 回戻ってくるので、定常状態の復習数は新規語 × 5 になる。
    /// 余裕を持たせて 6 倍を上限にする
    static let reviewLimitFactor = 6

    /// 復習の 1 日上限。設定項目にはせず、新規語数から決める。
    ///
    /// 別々に設定できるようにすると「復習上限 < 新規語 × 5」に設定してしまい、
    /// `SessionBuilder` の抑制ルールで新規語が出なくなる事故が起きるため。
    static func reviewLimit(forNewWordsPerDay count: Int) -> Int {
        max(minReviewLimitPerDay, count * reviewLimitFactor)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        level = CefrLevel(rawValue: defaults.string(forKey: Key.level) ?? "") ?? .a1
        newWordsPerDay = defaults.object(forKey: Key.newWordsPerDay) as? Int
            ?? Self.defaultNewWordsPerDay
        soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
    }

    /// 新規語を出すレベル。変更しても学習済みの進捗・復習スケジュールは保持される
    var level: CefrLevel {
        didSet { defaults.set(level.rawValue, forKey: Key.level) }
    }

    var newWordsPerDay: Int {
        didSet { defaults.set(newWordsPerDay, forKey: Key.newWordsPerDay) }
    }

    /// 復習の 1 日上限。サボって溜まっても圧殺されないための調整弁
    var reviewLimitPerDay: Int {
        Self.reviewLimit(forNewWordsPerDay: newWordsPerDay)
    }

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) }
    }
}
