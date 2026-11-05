import Foundation

/// 自作語の AI チェック・穴埋めの文章に使う Claude のモデル。rawValue はサーバーへ送るモデル ID。
/// サーバーの許可リスト（server/src/ai/models.ts）とそろえる。設計は docs/plans/archive/ai-model-settings.md
nonisolated enum ClaudeModel: String, CaseIterable, Identifiable, Sendable {
    case opus55 = "claude-opus-5-5"
    case sonnet55 = "claude-sonnet-5-5"

    static let defaultModel: ClaudeModel = .opus55

    var id: String { rawValue }

    var label: String {
        switch self {
        case .opus55: "Opus 5.5（高品質）"
        case .sonnet55: "Sonnet 5.5（速い・安い）"
        }
    }
}

/// 読み上げの声（Gemini TTS）のモデル。rawValue はサーバーへ送るモデル ID
nonisolated enum TTSModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case flash38 = "gemini-3.8-flash-tts"
    case flashLite38 = "gemini-3.8-flash-lite-tts"

    static let defaultModel: TTSModel = .flash38

    var id: String { rawValue }

    var label: String {
        switch self {
        case .flash38: "Gemini 3.8 Flash（標準）"
        case .flashLite38: "Gemini 3.8 Flash-Lite（速い・安い）"
        }
    }
}

/// 設定画面で選んだモデル。サーバーへ送るときに読む（`AppSettings` と同じ UserDefaults の値）
nonisolated enum AIModelPreference {
    enum Key {
        static let claudeModel = "settings.claudeModel"
        static let ttsModel = "settings.ttsModel"
    }

    static func claudeModel(defaults: UserDefaults = .standard) -> ClaudeModel {
        defaults.string(forKey: Key.claudeModel).flatMap(ClaudeModel.init(rawValue:)) ?? .defaultModel
    }

    static func ttsModel(defaults: UserDefaults = .standard) -> TTSModel {
        defaults.string(forKey: Key.ttsModel).flatMap(TTSModel.init(rawValue:)) ?? .defaultModel
    }
}
