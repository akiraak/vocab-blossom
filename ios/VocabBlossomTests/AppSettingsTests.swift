import AVFoundation
import Foundation
import Testing

@testable import VocabBlossom

@Suite("設定")
struct AppSettingsTests {
    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")!)
    }

    @Test("初期値はレベル A1・新規 10 語（どちらもバックアップ用）・音声オン・効果音オン・未オンボーディング")
    func defaults() {
        let settings = makeSettings()
        #expect(settings.level == .a1)
        #expect(settings.newWordsPerDay == AppSettings.defaultNewWordsPerDay)
        #expect(settings.soundEnabled)
        #expect(settings.effectSoundEnabled)
        #expect(!settings.hasOnboarded)
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
        settings.readAloudSpeed = .fast

        let restored = AppSettings(defaults: UserDefaults(suiteName: name)!)
        #expect(restored.level == .a2)
        #expect(restored.newWordsPerDay == 50)
        #expect(!restored.soundEnabled)
        #expect(!restored.effectSoundEnabled)
        #expect(restored.hasOnboarded)
        #expect(restored.claudeModel == .sonnet55)
        #expect(restored.ttsModel == .flashLite38)
        #expect(restored.readAloudSpeed == .fast)
        // 鳴らすときも同じ値を読む
        #expect(ReadAloudSpeed.current(defaults: UserDefaults(suiteName: name)!) == .fast)
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

    @Test("読み上げの速さの既定は「ふつう」（等速）。知らない値なら既定に戻す")
    func readAloudSpeedDefaults() {
        let defaults = UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")!
        #expect(AppSettings(defaults: defaults).readAloudSpeed == .normal)
        #expect(ReadAloudSpeed.normal.rawValue == 1.0)

        defaults.set(2.5, forKey: ReadAloudSpeed.key)
        #expect(ReadAloudSpeed.current(defaults: defaults) == .normal)
    }

    @Test("内蔵の声は、設定の速さをかけた速さで読む（上限・下限は超えない）")
    func builtInVoiceRate() {
        let base = ReadAloudSpeechEngine.sentenceRate
        #expect(ReadAloudSpeechEngine.utteranceRate(base, speed: .normal) == base)
        #expect(ReadAloudSpeechEngine.utteranceRate(base, speed: .fast) > base)
        #expect(ReadAloudSpeechEngine.utteranceRate(base, speed: .slow) < base)
        #expect(ReadAloudSpeechEngine.utteranceRate(0.9, speed: .veryFast) == AVSpeechUtteranceMaximumSpeechRate)
    }
}
