import Foundation
import SwiftUI

/// 穴埋め用の文章（`POST /api/passages`）の型。設計は docs/plans/fill-blank-passages.md
nonisolated enum PassageAPI {
    /// 文章を作る語。`id` は結果を受け取るための目印（サーバーは中身を見ない）
    struct Word: Codable, Equatable, Sendable {
        var id: String
        var word: String
        var pos: PartOfSpeech
        var meaning: String
        var example: String
    }

    struct Request: Encodable, Sendable {
        var words: [Word]
    }

    struct Result: Decodable, Equatable, Sendable {
        var id: String
        /// 作れなかった語は空（例文で出す）
        var passages: [Passage]
    }

    struct Response: Decodable, Sendable {
        var results: [Result]
    }
}

/// 文章を取ってくる。本番は `PassageClient`、テストと画面確認は偽物
protocol PassageFetching: Sendable {
    func fetch(_ words: [PassageAPI.Word]) async throws -> [PassageAPI.Result]
}

/// `POST /api/passages` を呼ぶ。エラーは AI チェックと同じ `WordAssistError` で返す
nonisolated struct PassageClient: PassageFetching {
    static let path = "api/passages"
    /// サーバーは AI を最長 55 秒 × 再試行 1 回 + 作り直し 1 回まで待つ
    static let timeout: TimeInterval = 180

    let config: ServerConfig
    let session: URLSession

    init(config: ServerConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetch(_ words: [PassageAPI.Word]) async throws -> [PassageAPI.Result] {
        var request = URLRequest(url: config.url(path: Self.path), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(PassageAPI.Request(words: words))

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
        if let error = WordAssistClient.error(forStatus: http.statusCode) { throw error }
        do {
            return try JSONDecoder().decode(PassageAPI.Response.self, from: data).results
        } catch {
            throw WordAssistError.invalidResponse
        }
    }
}

extension EnvironmentValues {
    /// 穴埋め用の文章の取り先。サーバーの設定が無ければ nil（文章を作らず例文で出す）
    @Entry var passageFetcher: (any PassageFetching)?
}
