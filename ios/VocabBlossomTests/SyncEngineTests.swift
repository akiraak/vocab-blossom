import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: AppModel.schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private let t0 = Date(syncMillis: 1_800_000_000_000)

private func at(_ seconds: Double) -> Date {
    t0.addingTimeInterval(seconds)
}

private func response(
    cursor: Int = 1,
    reset: Bool = false,
    groups: [SyncAPI.Group] = [],
    customWords: [SyncAPI.CustomWord] = [],
    deletions: [SyncAPI.Deletion] = []
) -> SyncAPI.Response {
    SyncAPI.Response(
        cursor: cursor, reset: reset, groups: groups, customWords: customWords, deletions: deletions
    )
}

/// 送った内容をそのまま受け入れたときのサーバーの返事
private func echo(_ request: SyncAPI.Request, cursor: Int = 1) -> SyncAPI.Response {
    response(
        cursor: cursor, groups: request.groups, customWords: request.customWords,
        deletions: request.deletions
    )
}

private func serverCustom(
    _ wordId: String,
    word: String = "homeroom",
    updatedAt: Date
) -> SyncAPI.CustomWord {
    SyncAPI.CustomWord(
        wordId: wordId, word: word, meaning: "\(word) の意味", pos: .noun,
        example: "", exampleJa: "", createdAt: t0, updatedAt: updatedAt
    )
}

private func fetchAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
    try context.fetch(FetchDescriptor<T>())
}

@Suite("同期: 送る差分")
struct SyncEngineRequestTests {
    let context: ModelContext
    let editor: GroupEditor
    let engine: SyncEngine

    init() throws {
        context = try makeContext()
        editor = GroupEditor(context: context)
        engine = SyncEngine(context: context)
    }

    @Test("まだ同期していないグループ・自作語はすべて送る。グループの ID は小文字")
    func firstSyncSendsEverything() throws {
        let group = editor.createGroup(name: "Unit 1", now: t0)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(word: "homeroom", meaning: "ホームルーム"), addingTo: group, now: at(1)
        )

        let request = try engine.makeRequest(cursor: 0)

        #expect(request.cursor == 0)
        #expect(request.groups.map(\.id) == [group.id.uuidString.lowercased()])
        #expect(request.groups.first?.wordIds == [custom.wordId])
        #expect(request.customWords.map(\.wordId) == [custom.wordId])
        #expect(request.deletions.isEmpty)
    }

    @Test("サーバーが受け入れたら送らなくなり、また変えたら送る")
    func sendsOnlyChanges() throws {
        let group = editor.createGroup(name: "Unit 1", now: t0)
        let first = try engine.makeRequest(cursor: 0)
        try engine.apply(echo(first), sent: first)

        #expect(try engine.makeRequest(cursor: 1).groups.isEmpty)

        editor.rename(group, to: "Unit 2", now: at(10))
        let second = try engine.makeRequest(cursor: 1)
        #expect(second.groups.map(\.name) == ["Unit 2"])
    }

    @Test("ミリ秒未満の端数があっても、送り返された値で同期済みになる")
    func subMillisecondDates() throws {
        editor.createGroup(name: "Unit 1", now: t0.addingTimeInterval(0.000_4))
        let request = try engine.makeRequest(cursor: 0)
        let data = try SyncAPI.encoder.encode(echo(request))
        let decoded = try SyncAPI.decoder.decode(SyncAPI.Response.self, from: data)

        try engine.apply(decoded, sent: request)

        #expect(try engine.makeRequest(cursor: 1).groups.isEmpty)
    }

    @Test("日時はミリ秒の整数で書き出す")
    func encodesMilliseconds() throws {
        let request = SyncAPI.Request(
            cursor: 3,
            groups: [],
            customWords: [],
            deletions: [SyncAPI.Deletion(kind: .group, id: "x", deletedAt: Date(syncMillis: 1_234_567))]
        )
        let json = try #require(
            String(data: try SyncAPI.encoder.encode(request), encoding: .utf8)
        )
        #expect(json.contains("\"deletedAt\":1234567"))
        #expect(json.contains("\"kind\":\"group\""))
    }

    @Test("グループを消すと削除記録が残り、送り終えたら消える")
    func groupDeletionIsRecorded() throws {
        let group = editor.createGroup(name: "Unit 1", now: t0)
        let groupId = group.id.syncId
        editor.delete(group, now: at(5))

        let request = try engine.makeRequest(cursor: 0)
        #expect(request.groups.isEmpty)
        #expect(request.deletions == [SyncAPI.Deletion(kind: .group, id: groupId, deletedAt: at(5))])

        try engine.apply(echo(request), sent: request)
        #expect(try fetchAll(SyncDeletion.self, context).isEmpty)
    }

    @Test("自作語を消すと削除記録が残り、外したグループの updatedAt も進む")
    func customWordDeletionIsRecorded() throws {
        let group = editor.createGroup(name: "Unit 1", now: t0)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(word: "homeroom", meaning: "ホームルーム"), addingTo: group, now: at(1)
        )
        let wordId = custom.wordId
        let first = try engine.makeRequest(cursor: 0)
        try engine.apply(echo(first), sent: first)

        editor.deleteCustomWord(id: wordId, now: at(10))

        let request = try engine.makeRequest(cursor: 1)
        #expect(request.deletions.map(\.id) == [wordId])
        #expect(request.groups.map(\.wordIds) == [[]])
        #expect(request.groups.first?.updatedAt == at(10))
    }

    @Test("通信している間に消したものの削除記録は残る")
    func deletionDuringRequestStays() throws {
        let first = editor.createGroup(name: "A", now: t0)
        editor.delete(first, now: at(1))
        let request = try engine.makeRequest(cursor: 0)

        let second = editor.createGroup(name: "B", now: at(2))
        editor.delete(second, now: at(3))
        try engine.apply(echo(request), sent: request)

        let left = try fetchAll(SyncDeletion.self, context)
        #expect(left.map(\.recordId) == [second.id.syncId])
    }
}

@Suite("同期: 受け取った変更の反映")
struct SyncEngineApplyTests {
    let context: ModelContext
    let editor: GroupEditor
    let engine: SyncEngine
    let empty = SyncAPI.Request(cursor: 0, groups: [], customWords: [], deletions: [])

    init() throws {
        context = try makeContext()
        editor = GroupEditor(context: context)
        engine = SyncEngine(context: context)
    }

    @Test("管理画面で作ったグループと自作語が入り、同期済みになる")
    func insertsNewRecords() throws {
        let id = UUID()
        let incoming = SyncAPI.Group(
            id: id.syncId, name: "管理画面", wordIds: ["a1-0001", "custom-x"],
            createdAt: t0, updatedAt: at(1)
        )
        try engine.apply(
            response(groups: [incoming], customWords: [serverCustom("custom-x", updatedAt: at(1))]),
            sent: empty
        )

        let group = try #require(try fetchAll(WordGroup.self, context).first)
        #expect(group.id == id)
        #expect(group.name == "管理画面")
        #expect(group.wordIds == ["a1-0001", "custom-x"])
        #expect(!group.needsSync)
        let custom = try #require(editor.customWord(id: "custom-x"))
        #expect(custom.word == "homeroom")
        #expect(!custom.needsSync)
    }

    @Test("サーバーの方が新しければ上書きし、手元の方が新しければ残して次に送る")
    func lastWriterWins() throws {
        let group = editor.createGroup(name: "手元", now: at(10))
        let older = SyncAPI.Group(
            id: group.id.syncId, name: "古い", wordIds: [], createdAt: t0, updatedAt: at(5)
        )
        try engine.apply(response(groups: [older]), sent: empty)
        #expect(group.name == "手元")
        #expect(group.needsSync)

        let newer = SyncAPI.Group(
            id: group.id.syncId, name: "新しい", wordIds: ["a1-0001"], createdAt: t0, updatedAt: at(20)
        )
        try engine.apply(response(groups: [newer]), sent: empty)
        #expect(group.name == "新しい")
        #expect(group.wordIds == ["a1-0001"])
        #expect(!group.needsSync)
    }

    @Test("グループの削除が届くとグループだけ消える")
    func groupDeletionArrives() throws {
        let group = editor.createGroup(name: "Unit 1", now: t0)
        editor.add(wordIds: ["a1-0001"], to: group, now: at(1))
        let deletion = SyncAPI.Deletion(kind: .group, id: group.id.syncId, deletedAt: at(2))

        try engine.apply(response(deletions: [deletion]), sent: empty)

        #expect(try fetchAll(WordGroup.self, context).isEmpty)
        #expect(try fetchAll(SyncDeletion.self, context).isEmpty)
    }

    @Test("手元の方が新しければ、届いた削除では消さない")
    func newerLocalSurvivesDeletion() throws {
        let group = editor.createGroup(name: "Unit 1", now: at(10))
        let deletion = SyncAPI.Deletion(kind: .group, id: group.id.syncId, deletedAt: at(5))

        try engine.apply(response(deletions: [deletion]), sent: empty)

        #expect(try fetchAll(WordGroup.self, context).count == 1)
    }

    @Test("自作語の削除が届くと、グループの中・進捗・回答ログからも消える")
    func customWordDeletionArrives() throws {
        let group = editor.createGroup(name: "Unit 1", now: t0)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(word: "homeroom", meaning: "ホームルーム"), addingTo: group, now: at(1)
        )
        let wordId = custom.wordId
        context.insert(
            WordProgress(wordId: wordId, stage: 1, dueAt: t0, learnedAt: t0, updatedAt: t0)
        )
        context.insert(
            AnswerLog(
                wordId: wordId, answeredAt: t0, dateKey: "2027-01-15", correct: true,
                quizType: .enToJa, kind: .new, stageAfter: 1
            )
        )
        try context.save()

        let deletion = SyncAPI.Deletion(kind: .customWord, id: wordId, deletedAt: at(5))
        try engine.apply(response(deletions: [deletion]), sent: empty)

        #expect(editor.customWord(id: wordId) == nil)
        #expect(group.wordIds.isEmpty)
        #expect(try fetchAll(WordProgress.self, context).isEmpty)
        #expect(try fetchAll(AnswerLog.self, context).isEmpty)
        // 削除はサーバーから来たので、送り返す削除記録は作らない
        #expect(try fetchAll(SyncDeletion.self, context).isEmpty)
    }

    @Test("手元でまだ送っていない削除の方が新しければ、届いたレコードは当てない")
    func pendingDeletionBlocksOlderRecord() throws {
        let group = editor.createGroup(name: "Unit 1", now: t0)
        let groupId = group.id.syncId
        let request = try engine.makeRequest(cursor: 0)
        // 送った後（通信中）に消した
        editor.delete(group, now: at(10))

        try engine.apply(echo(request), sent: request)

        #expect(try fetchAll(WordGroup.self, context).isEmpty)
        #expect(try fetchAll(SyncDeletion.self, context).map(\.recordId) == [groupId])
    }

    @Test("届いたグループに、手元で消してまだ送っていない自作語があれば抜く")
    func pendingCustomDeletionIsFilteredFromGroups() throws {
        editor.deleteCustomWord(id: "custom-gone", now: at(10))
        let incoming = SyncAPI.Group(
            id: UUID().syncId, name: "Unit 1", wordIds: ["a1-0001", "custom-gone"],
            createdAt: t0, updatedAt: at(1)
        )

        try engine.apply(response(groups: [incoming]), sent: empty)

        let group = try #require(try fetchAll(WordGroup.self, context).first)
        #expect(group.wordIds == ["a1-0001"])
    }

    @Test("サーバーの DB が作り直されていたら（reset）全件を未送信に戻す")
    func resetMarksAllForResend() throws {
        editor.createGroup(name: "Unit 1", now: t0)
        let first = try engine.makeRequest(cursor: 0)
        try engine.apply(echo(first), sent: first)
        #expect(try engine.makeRequest(cursor: 1).groups.isEmpty)

        try engine.apply(response(cursor: 0, reset: true), sent: empty)

        #expect(try engine.makeRequest(cursor: 0).groups.count == 1)
    }
}
