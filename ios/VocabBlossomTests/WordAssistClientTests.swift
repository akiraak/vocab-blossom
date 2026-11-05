import Foundation
import Testing

@testable import VocabBlossom

private let config = ServerConfig(baseURL: URL(string: "https://vocab.example.com")!, apiKey: "secret")

nonisolated private func json(_ text: String) -> Data { Data(text.utf8) }

nonisolated private let sampleResponse = """
{"text":"beautifull","candidates":[
 {"word":"beautiful","pos":"adjective","meaning":"美しい",
  "example":"What a beautiful day!","exampleJa":"なんて美しい日でしょう！","reason":"typo",
  "bundled":{"id":"a1-0050","word":"beautiful","meaning":"美しい","pos":"adjective","level":"A1"}},
 {"word":"bountiful","pos":"adjective","meaning":"豊富な",
  "example":"We had a bountiful harvest.","exampleJa":"豊作でした。",
  "reason":"something-new","bundled":null}
]}
"""

@Suite("AI チェック: 通信")
struct WordAssistClientTests {
    @Test("Bearer つきで text を送り、候補を読み取る（知らない理由は unknown）")
    func sendsAndDecodes() async throws {
        let sent = RequestCapture()
        let session = StubURLProtocol.session { request, body in
            sent.set(request, body)
            return (200, json(sampleResponse))
        }
        let response = try await WordAssistClient(config: config, session: session, model: { .sonnet55 })
            .suggest("beautifull")

        let (request, body) = try #require(sent.value)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://vocab.example.com/api/word-assist")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        let sentJSON = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sentJSON == ["text": "beautifull", "model": "claude-sonnet-5-5"])

        #expect(response.candidates.count == 2)
        #expect(response.candidates[0].bundled?.id == "a1-0050")
        #expect(response.candidates[0].reason == .typo)
        #expect(response.candidates[1].bundled == nil)
        #expect(response.candidates[1].reason == .unknown)
    }

    @Test("状態コードをエラーに分ける", arguments: [
        (401, WordAssistError.unauthorized),
        (429, .rateLimited),
        (502, .failed),
        (503, .unavailable),
        (500, .server(status: 500)),
    ])
    func mapsStatus(status: Int, expected: WordAssistError) async {
        let session = StubURLProtocol.session { _, _ in (status, json("{}")) }
        await #expect(throws: expected) {
            _ = try await WordAssistClient(config: config, session: session).suggest("x")
        }
    }

    @Test("読めない返事は invalidResponse")
    func invalidBody() async {
        let session = StubURLProtocol.session { _, _ in (200, json("{\"oops\":1}")) }
        await #expect(throws: WordAssistError.invalidResponse) {
            _ = try await WordAssistClient(config: config, session: session).suggest("x")
        }
    }
}

@Suite("AI チェック: 下書きへの反映")
struct WordAssistDraftTests {
    private let candidate = WordAssistAPI.Candidate(
        word: "serendipity", pos: .noun, meaning: "思いがけない幸運",
        example: "It was pure serendipity.", exampleJa: "まったくの偶然の幸運でした。",
        reason: .exact, bundled: nil
    )

    @Test("空いている欄だけ埋め、入力済みの欄は残す")
    func fillsOnlyEmpty() {
        let draft = GroupEditor.WordDraft(
            word: "serendipity", meaning: "  ", pos: .noun, example: "", exampleJa: ""
        )
        let filled = draft.applying(candidate, onlyEmpty: true)
        #expect(filled.word == "serendipity")
        #expect(filled.meaning == "思いがけない幸運")
        #expect(filled.example == "It was pure serendipity.")
        #expect(filled.exampleJa == "まったくの偶然の幸運でした。")

        let typed = GroupEditor.WordDraft(
            word: "serendipity", meaning: "幸運", pos: .noun, example: "My own.", exampleJa: ""
        )
        let kept = typed.applying(candidate, onlyEmpty: true)
        #expect(kept.meaning == "幸運")
        // 例文と訳は組で扱うので、例文があれば訳も AI では埋めない
        #expect(kept.example == "My own.")
        #expect(kept.exampleJa == "")
    }

    @Test("onlyEmpty でなければ AI の候補ですべて置き換える（「単語を追加」で候補を下書きにするとき）")
    func replacesAll() {
        let draft = GroupEditor.WordDraft(
            word: "serendipty", meaning: "幸運", pos: .verb, example: "x", exampleJa: "y"
        )
        let replaced = draft.applying(candidate, onlyEmpty: false)
        #expect(replaced == GroupEditor.WordDraft(
            word: "serendipity", meaning: "思いがけない幸運", pos: .noun,
            example: "It was pure serendipity.", exampleJa: "まったくの偶然の幸運でした。"
        ))
    }
}

/// スタブのハンドラ（別スレッド）から送られた要求を受け取る
nonisolated final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (URLRequest, Data)?

    func set(_ request: URLRequest, _ body: Data) {
        lock.withLock { stored = (request, body) }
    }

    var value: (URLRequest, Data)? { lock.withLock { stored } }
}
