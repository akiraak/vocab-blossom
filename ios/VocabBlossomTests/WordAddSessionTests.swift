import Foundation
import Testing

@testable import VocabBlossom

@Suite("単語を追加（画面の状態と確定）")
struct WordAddSessionTests {
    private func candidate(
        _ word: String,
        pos: PartOfSpeech = .verb,
        meaning: String = "通勤する",
        reason: WordAssistAPI.Reason = .exact,
        bundledId: String? = nil
    ) -> WordAssistAPI.Candidate {
        WordAssistAPI.Candidate(
            word: word, pos: pos, meaning: meaning,
            example: "I \(word) to work.", exampleJa: "私は通勤します。",
            reason: reason,
            bundled: bundledId.map { WordAssistAPI.Bundled(id: $0, word: word, meaning: meaning) }
        )
    }

    /// 作った自作語の ID を順に返す（`createCustomWord` の代わり）
    private final class Recorder {
        var created: [GroupEditor.WordDraft] = []
        func create(_ draft: GroupEditor.WordDraft) -> String {
            created.append(draft)
            return "custom-\(created.count)"
        }
    }

    @Test("グループに入っている語は選択に含めず、選べない")
    func addedWordsAreNotPicks() {
        var session = WordAddSession(addedIds: ["a1-0001"])
        #expect(session.pickCount == 0)
        #expect(session.isAdded("a1-0001"))
        session.toggle(.word("a1-0001"))
        #expect(session.pickCount == 0)
        #expect(!session.isSelected(.word("a1-0001")))
    }

    @Test("付け外しでき、確定では選んだ順に返す")
    func toggleKeepsOrder() {
        var session = WordAddSession(addedIds: [])
        session.toggle(.word("a1-0003"))
        session.toggle(.word("a1-0001"))
        session.toggle(.word("a1-0002"))
        session.toggle(.word("a1-0001"))
        #expect(session.pickCount == 2)
        let recorder = Recorder()
        #expect(session.commit(createCustomWord: recorder.create) == ["a1-0003", "a1-0002"])
        #expect(recorder.created.isEmpty)
    }

    @Test("AI の結果: 単語帳の語は案内に、無い語は下書きにし、入力どおりの最初の 1 つを選んでおく")
    func assistResultSplitsCandidates() throws {
        var session = WordAddSession(addedIds: [])
        session.startAssist(text: "commute")
        session.finishAssist(text: "commute", candidates: [
            candidate("commute", pos: .verb),
            candidate("commute", pos: .noun, meaning: "通勤"),
            candidate("community", pos: .noun, meaning: "地域社会", reason: .typo, bundledId: "a2-0100"),
        ])
        #expect(session.assist == .done(text: "commute"))
        #expect(session.suggestedWords == [.init(id: "a2-0100", reason: .typo)])
        #expect(session.newWords.map(\.draft.pos) == [.verb, .noun])
        let verb = try #require(session.newWords.first)
        #expect(verb.draft.meaning == "通勤する")
        #expect(verb.draft.example == "I commute to work.")
        #expect(session.isSelected(.newWord(verb.id)))
        #expect(session.pickCount == 1)
    }

    @Test("打ち間違いなど、入力どおりでない候補は自動で選ばない")
    func doesNotAutoSelectNonExact() {
        var session = WordAddSession(addedIds: [])
        session.startAssist(text: "beautifull")
        session.finishAssist(text: "beautifull", candidates: [
            candidate("beautiful", pos: .adjective, meaning: "美しい", reason: .typo, bundledId: "a1-0050"),
        ])
        #expect(session.pickCount == 0)
        #expect(session.newWords.isEmpty)
    }

    @Test("確定で、選んだ下書きだけを自作語にして選んだ順に返す")
    func commitCreatesSelectedNewWords() throws {
        var session = WordAddSession(addedIds: ["a1-0001"])
        session.toggle(.word("a1-0002"))
        session.startAssist(text: "commute")
        session.finishAssist(text: "commute", candidates: [
            candidate("commute", pos: .verb),
            candidate("commute", pos: .noun, meaning: "通勤"),
        ])
        session.toggle(.word("a1-0003"))
        let recorder = Recorder()
        let ids = session.commit(createCustomWord: recorder.create)
        #expect(ids == ["a1-0002", "custom-1", "a1-0003"])
        #expect(recorder.created.count == 1)
        #expect(recorder.created.first?.pos == .verb)
    }

    @Test("あとから別の語で調べ直したら、前の結果は捨てる")
    func ignoresStaleResult() {
        var session = WordAddSession(addedIds: [])
        session.startAssist(text: "commut")
        session.startAssist(text: "commute")
        session.finishAssist(text: "commut", candidates: [candidate("commut")])
        #expect(session.assist == .loading(text: "commute"))
        #expect(session.newWords.isEmpty)
        session.failAssist(text: "commut", message: "失敗")
        #expect(session.assist == .loading(text: "commute"))
    }

    @Test("調べ直しても、選んだ下書きは残り、同じ候補は 2 つ並ばない")
    func keepsSelectedNewWordsAcrossSearches() throws {
        var session = WordAddSession(addedIds: [])
        session.startAssist(text: "commute")
        session.finishAssist(text: "commute", candidates: [
            candidate("commute", pos: .verb),
            candidate("commute", pos: .noun, meaning: "通勤"),
        ])
        session.startAssist(text: "commute")
        session.finishAssist(text: "commute", candidates: [
            candidate("commute", pos: .verb),
            candidate("commute", pos: .noun, meaning: "通勤"),
        ])
        #expect(session.newWords.map(\.draft.pos) == [.verb, .noun])
        #expect(session.pickCount == 1)

        session.startAssist(text: "hobby")
        session.finishAssist(text: "hobby", candidates: [candidate("hobby", pos: .noun, meaning: "趣味")])
        #expect(session.newWords.map(\.draft.word) == ["commute", "hobby"])
        #expect(session.pickCount == 2)
    }

    @Test("下書きを直すと選んだことになり、確定では直した内容で作る")
    func updateNewWord() throws {
        var session = WordAddSession(addedIds: [])
        session.startAssist(text: "commute")
        session.finishAssist(text: "commute", candidates: [
            candidate("commute", pos: .verb),
            candidate("commute", pos: .noun, meaning: "通勤"),
        ])
        let noun = try #require(session.newWords.last)
        var fixed = noun.draft
        fixed.meaning = "通勤、通学"
        session.updateNewWord(noun.id, with: fixed)
        #expect(session.isSelected(.newWord(noun.id)))
        let recorder = Recorder()
        _ = session.commit(createCustomWord: recorder.create)
        #expect(recorder.created.map(\.meaning) == ["通勤する", "通勤、通学"])
    }

    @Test("下書きの代わりに単語帳の語を選べる")
    func replaceNewWordWithBundled() throws {
        var session = WordAddSession(addedIds: [])
        session.addNewWord(GroupEditor.WordDraft(word: "take", meaning: "取る", pos: .verb))
        let newWord = try #require(session.newWords.first)
        #expect(session.isSelected(.newWord(newWord.id)))
        session.replaceNewWord(newWord.id, withWord: "a1-0200")
        #expect(session.newWords.isEmpty)
        #expect(session.picks == [.word("a1-0200")])
    }
}
