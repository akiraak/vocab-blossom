import Foundation
import SwiftUI

/// 自作語を作る前の AI チェック（`POST /api/word-assist`）の型。設計は docs/plans/ai-word-assist.md
nonisolated enum WordAssistAPI {
    struct Request: Encodable, Sendable {
        var text: String
    }

    struct Response: Decodable, Equatable, Sendable {
        var text: String
        var candidates: [Candidate]
    }

    /// AI の候補。`bundled` があれば単語帳（同梱語）にある語
    struct Candidate: Decodable, Equatable, Sendable, Identifiable {
        var word: String
        var pos: PartOfSpeech
        var meaning: String
        var example: String
        var exampleJa: String
        var reason: Reason
        var bundled: Bundled?

        var id: String { word }
    }

    struct Bundled: Decodable, Equatable, Sendable {
        var id: String
        var word: String
        var meaning: String
    }

    /// 候補を出した理由。知らない値が来ても読めるよう `unknown` に落とす
    enum Reason: String, Decodable, Sendable {
        case exact, typo, inflection, variant, translation, unknown

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Reason(rawValue: raw) ?? .unknown
        }

        /// 候補に添える説明（`exact` などは添えない）
        var label: String? {
            switch self {
            case .typo: "綴りの誤りかもしれません"
            case .inflection: "変化した形のもとの形です"
            case .variant: "綴り・言い方の違いです"
            case .translation: "日本語から探しました"
            case .exact, .unknown: nil
            }
        }
    }
}

/// AI チェックで起きたこと。エディタにそのまま出せる文にする
enum WordAssistError: LocalizedError, Equatable {
    case unavailable
    case rateLimited
    case failed
    case unauthorized
    case server(status: Int)
    case invalidResponse
    case offline
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "サーバーで AI が使えません（ANTHROPIC_API_KEY が未設定）"
        case .rateLimited: "AI を短い間に使いすぎました。少し待ってからもう一度試してください"
        case .failed: "AI が答えられませんでした。もう一度試すか、そのまま入力してください"
        case .unauthorized: "サーバーに認証されませんでした（API キーを確認してください）"
        case .server(let status): "サーバーでエラーが起きました（\(status)）"
        case .invalidResponse: "サーバーの返事を読み取れませんでした"
        case .offline: "インターネットにつながっていません"
        case .network(let detail): "サーバーにつながりませんでした（\(detail)）"
        }
    }
}

/// `POST /api/word-assist` を呼ぶ。テストでは `URLProtocol` のスタブを入れた `URLSession` を渡す
nonisolated struct WordAssistClient: Sendable {
    static let path = "api/word-assist"
    /// サーバーは AI を最長 25 秒 × 再試行 1 回まで待つ
    static let timeout: TimeInterval = 60

    let config: ServerConfig
    let session: URLSession

    init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func suggest(_ text: String) async throws -> WordAssistAPI.Response {
        var request = URLRequest(url: config.url(path: Self.path), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(WordAssistAPI.Request(text: text))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw WordAssistError.offline
            default:
                throw WordAssistError.network(error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw WordAssistError.invalidResponse }
        if let error = Self.error(forStatus: http.statusCode) { throw error }
        do {
            return try JSONDecoder().decode(WordAssistAPI.Response.self, from: data)
        } catch {
            throw WordAssistError.invalidResponse
        }
    }

    /// 成功（2xx）なら nil
    static func error(forStatus status: Int) -> WordAssistError? {
        switch status {
        case 200..<300: nil
        case 401: .unauthorized
        case 429: .rateLimited
        case 502: .failed
        case 503: .unavailable
        default: .server(status: status)
        }
    }
}

extension EnvironmentValues {
    /// AI チェックの接続先。サーバーの設定が無ければ nil（エディタに AI の欄を出さない）
    @Entry var wordAssist: WordAssistClient?
}

extension WordAssistAPI.Candidate {
    /// 候補を意味 1 つ分として
    var sense: WordSense {
        WordSense(pos: pos, meaning: meaning, example: example, exampleJa: exampleJa)
    }
}

extension GroupEditor.WordDraft {
    /// AI の候補を下書きに入れる。`onlyEmpty` なら入力済みの欄は残し、空いている欄だけ埋める
    func applying(_ candidate: WordAssistAPI.Candidate, onlyEmpty: Bool) -> GroupEditor.WordDraft {
        var draft = self
        func fill(_ keyPath: WritableKeyPath<GroupEditor.WordDraft, String>, _ value: String) {
            if !onlyEmpty || draft[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft[keyPath: keyPath] = value
            }
        }
        fill(\.word, candidate.word)
        fill(\.meaning, candidate.meaning)
        // 例文と訳は組で入れる（片方だけ AI のものにすると食い違う）
        if !onlyEmpty || (draft.example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.exampleJa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            draft.example = candidate.example
            draft.exampleJa = candidate.exampleJa
        }
        draft.pos = candidate.pos
        return draft
    }
}
