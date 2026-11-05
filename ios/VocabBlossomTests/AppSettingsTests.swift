import Foundation
import Testing

@testable import VocabBlossom

@Suite("設定")
struct AppSettingsTests {
    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")!)
    }

    @Test("初期値はレベル A1・新規 10 語・音声オン・効果音オン・未オンボーディング")
    func defaults() {
        let settings = makeSettings()
        #expect(settings.level == .a1)
        #expect(settings.newWordsPerDay == AppSettings.defaultNewWordsPerDay)
        #expect(settings.soundEnabled)
        #expect(settings.effectSoundEnabled)
        #expect(!settings.hasOnboarded)
    }

    @Test(
        "復習上限は新規語数の 6 倍（最低 60）に自動追従する",
        arguments: [(5, 60), (10, 60), (15, 90), (20, 120), (30, 180), (50, 300), (100, 600)]
    )
    func reviewLimitFollowsNewWords(newWordsPerDay: Int, expected: Int) {
        let settings = makeSettings()
        settings.newWordsPerDay = newWordsPerDay
        #expect(settings.reviewLimitPerDay == expected)
    }

    @Test("どの選択肢でも 復習上限 >= 新規語 × 5 を満たす（新規語が止まらない）")
    func reviewLimitAlwaysCoversSteadyState() {
        for count in AppSettings.newWordsPerDayChoices {
            // 1 語は開花までに 5 回戻ってくるので、定常状態の復習数は新規語 × 5
            #expect(AppSettings.reviewLimit(forNewWordsPerDay: count) >= count * 5)
        }
    }

    @Test("設定は UserDefaults に保存され、次回起動で復元される")
    func persistsAcrossInstances() {
        let name = "settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        settings.level = .a2
        settings.newWordsPerDay = 50
        settings.soundEnabled = false
        settings.effectSoundEnabled = false
        settings.hasOnboarded = true
        settings.claudeModel = .sonnet55
        settings.ttsModel = .flashLite38

        let restored = AppSettings(defaults: UserDefaults(suiteName: name)!)
        #expect(restored.level == .a2)
        #expect(restored.newWordsPerDay == 50)
        #expect(restored.reviewLimitPerDay == 300)
        #expect(!restored.soundEnabled)
        #expect(!restored.effectSoundEnabled)
        #expect(restored.hasOnboarded)
        #expect(restored.claudeModel == .sonnet55)
        #expect(restored.ttsModel == .flashLite38)
        // サーバーへ送るときも同じ値を読む
        #expect(AIModelPreference.claudeModel(defaults: UserDefaults(suiteName: name)!) == .sonnet55)
        #expect(AIModelPreference.ttsModel(defaults: UserDefaults(suiteName: name)!) == .flashLite38)
    }

    @Test("AI のモデルの既定は Opus 5.5 と Gemini 3.8 Flash。知らない値なら既定に戻す")
    func aiModelDefaults() {
        let name = "settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.claudeModel == .opus55)
        #expect(settings.ttsModel == .flash38)

        defaults.set("claude-haiku-5-5", forKey: AIModelPreference.Key.claudeModel)
        defaults.set("gemini-2.5-pro-preview-tts", forKey: AIModelPreference.Key.ttsModel)
        #expect(AIModelPreference.claudeModel(defaults: defaults) == .opus55)
        #expect(AIModelPreference.ttsModel(defaults: defaults) == .flash38)
    }
}
