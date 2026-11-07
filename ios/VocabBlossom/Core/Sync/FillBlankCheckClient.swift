import Foundation
import SwiftUI

/// 穴埋めの選択肢の判定（`POST /api/fill-blank-checks`）の型。設計は docs/plans/archive/connective-fill-blank-check.md
nonisolated enum FillBlankCheckAPI {
    /// 判定する 1 問。`text` は見出し語の入った全文、`choices` は正解以外の選択肢の綴り
    struct Item: Codable, Equatable, Sendable {
        var id: String
        var text: String
        var answer: String
        var choices: [String]
    }

    struct Request: Encodable, Sendable {
        var items: [Item]
        /// 設定画面で選んだモデル（サーバーの許可リストにあるもの）
        var model: String
    }

    struct Result: Decodable, Equatable, Sendable {
        var id: String
        /// 空欄に入れても正しい文になる誤答肢の綴り
        var alsoCorrect: [String]
    }

    struct Response: Decodable, Sendable {
        var results: [Result]
    }
}

/// 選択肢を判定してもらう。本番は `FillBlankCheckClient`、テストは偽物
protocol FillBlankChecking: Sendable {
    func check(_ items: [FillBlankCheckAPI.Item]) async throws -> [FillBlankCheckAPI.Result]
}

/// `POST /api/fill-blank-checks` を呼ぶ。エラーは AI チェックと同じ `WordAssistError` で返す
nonisolated struct FillBlankCheckClient: FillBlankChecking {
    static let path = "api/fill-blank-checks"
    /// サーバーは AI を最長 35 秒 × 再試行 1 回まで待つ
    static let timeout: TimeInterval = 90

    let config: ServerConfig
    let session: URLSession
    /// 送るときに読む（設定を変えたら次の呼び出しから効く）
    let model: @Sendable () -> ClaudeModel

    init(
        config: ServerConfig,
        session: URLSession = .shared,
        model: @escaping @Sendable () -> ClaudeModel = { AIModelPreference.claudeModel() }
    ) {
        self.config = config
        self.session = session
        self.model = model
    }

    func check(_ items: [FillBlankCheckAPI.Item]) async throws -> [FillBlankCheckAPI.Result] {
        var request = URLRequest(url: config.url(path: Self.path), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            FillBlankCheckAPI.Request(items: items, model: model().rawValue)
        )

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
            return try JSONDecoder().decode(FillBlankCheckAPI.Response.self, from: data).results
        } catch {
            throw WordAssistError.invalidResponse
        }
    }
}

/// グループの穴埋めモードで、組み立て済みの問題の選択肢を判定し、ほかにも正解の語を問題に入れる。
///
/// 10 問ずつ、3 本まで並べて送る。失敗した分は判定なし（正解は出題した語だけ）のまま返す
enum FillBlankCheck {
    /// サーバーが 1 回に受け付ける問題数
    static let itemsPerRequest = 10
    static let parallelRequests = 3

    /// 判定に送る問題（id は問題の位置）。穴埋めでない問題・誤答肢の無い問題は送らない
    static func items(for quizzes: [Quiz]) -> [FillBlankCheckAPI.Item] {
        quizzes.enumerated().compactMap { index, quiz in
            guard let text = quiz.fillBlankSourceText else { return nil }
            let choices = quiz.choices.filter { $0.id != quiz.word.id }.map(\.word)
            guard !choices.isEmpty else { return nil }
            return FillBlankCheckAPI.Item(
                id: String(index), text: text, answer: quiz.word.word, choices: choices
            )
        }
    }

    /// 判定の結果を問題に入れる（綴りで誤答肢の語を引く）
    static func apply(_ results: [FillBlankCheckAPI.Result], to quizzes: [Quiz]) -> [Quiz] {
        var updated = quizzes
        for result in results {
            guard let index = Int(result.id), updated.indices.contains(index) else { continue }
            let quiz = updated[index]
            let spellings = Set(result.alsoCorrect.map(WordStore.normalizedSpelling))
            let ids = quiz.choices
                .filter { $0.id != quiz.word.id && spellings.contains(WordStore.normalizedSpelling($0.word)) }
                .map(\.id)
            if !ids.isEmpty { updated[index] = quiz.with(alsoCorrectWordIds: Set(ids)) }
        }
        return updated
    }

    /// 判定して、ほかにも正解の語を入れた問題を返す
    static func run(_ quizzes: [Quiz], checker: any FillBlankChecking) async -> [Quiz] {
        let items = items(for: quizzes)
        guard !items.isEmpty else { return quizzes }
        let chunks = stride(from: 0, to: items.count, by: itemsPerRequest).map {
            Array(items[$0..<min($0 + itemsPerRequest, items.count)])
        }
        var results: [FillBlankCheckAPI.Result] = []
        await withTaskGroup(of: [FillBlankCheckAPI.Result].self) { group in
            var next = 0
            func addNext() {
                guard next < chunks.count else { return }
                let chunk = chunks[next]
                next += 1
                group.addTask { (try? await checker.check(chunk)) ?? [] }
            }
            for _ in 0..<parallelRequests { addNext() }
            for await chunkResults in group {
                results.append(contentsOf: chunkResults)
                addNext()
            }
        }
        return apply(results, to: quizzes)
    }
}

extension EnvironmentValues {
    /// 穴埋めの選択肢の判定先。サーバーの設定が無ければ nil（判定せず、正解は出題した語だけ）
    @Entry var fillBlankChecker: (any FillBlankChecking)?
}
