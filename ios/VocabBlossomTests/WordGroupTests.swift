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

private func customEntry(_ id: String, word: String, pos: PartOfSpeech = .noun) -> WordEntry {
    WordEntry(
        id: id, word: word, pos: pos, level: nil, meaning: "\(word) の意味",
        example: "", exampleJa: ""
    )
}

@Suite("自作語を重ねた索引")
struct WordStoreCustomTests {
    let base = WordStore.shared

    @Test("自作語を ID で引け、全語の末尾に並ぶ")
    func customWordsResolve() {
        let custom = customEntry("custom-1", word: "homeroom")
        let store = base.including(customWords: [custom])

        #expect(store.word(id: "custom-1") == custom)
        #expect(store.word(id: "a1-0001") == base.word(id: "a1-0001"))
        #expect(store.allWords.count == base.allWords.count + 1)
        #expect(store.allWords.last == custom)
        #expect(store.customWords == [custom])
        #expect(base.word(id: "custom-1") == nil)
    }

    @Test("自作語はレベル別プール・デッキに混ざらない（毎日のおまかせに出ない）")
    func customWordsStayOutOfDailyPool() {
        let store = base.including(customWords: [customEntry("custom-1", word: "homeroom")])
        #expect(store.words(level: .a1).count == base.words(level: .a1).count)
        #expect(!store.newWordPool(level: .a1, order: .test).contains { $0.isCustom })
        #expect(store.decks == base.decks)
        #expect(store.deck(of: "custom-1") == nil)
    }

    @Test("差し替えても同梱語は重複しない")
    func replacingCustomWords() {
        let first = base.including(customWords: [customEntry("custom-1", word: "a")])
        let second = first.including(customWords: [customEntry("custom-2", word: "b")])
        #expect(second.allWords.count == base.allWords.count + 1)
        #expect(second.word(id: "custom-1") == nil)
        #expect(second.word(id: "custom-2") != nil)
    }

    @Test("ID の並びを引き直すと、見つからない ID は落ちる")
    func wordsByIds() {
        let words = base.words(ids: ["a1-0002", "custom-gone", "a1-0001"])
        #expect(words.map(\.id) == ["a1-0002", "a1-0001"])
    }

    @Test("同じ綴りの同梱語を大小文字・空白を無視して探す")
    func bundledWordLookup() throws {
        let action = try #require(base.word(id: "a1-0004"))
        #expect(base.bundledWord(spelledLike: "  \(action.word.uppercased()) ")?.id == action.id)
        #expect(base.bundledWord(spelledLike: "zzzz-not-a-word") == nil)
        #expect(base.bundledWord(spelledLike: " ") == nil)
    }
}

@Suite("グループ単位の学習の出題")
struct GroupStudyTests {
    let now = TestDate.at(2026, 8, 14)
    let store = WordStore.shared

    private func snapshot(_ id: String, stage: Int, dueOffset: Int) -> ProgressSnapshot {
        ProgressSnapshot(
            wordId: id, stage: stage, dueAt: DateUtil.startOfDay(DateUtil.addDays(now, dueOffset))
        )
    }

    private func plan(words: [String], progress: [ProgressSnapshot], limit: Int = 10) -> SessionPlan {
        GroupStudy.plan(
            GroupStudy.Input(
                now: now,
                words: store.words(ids: words),
                progress: progress,
                newWordsLimit: limit,
                reviewLimit: 60,
                order: .test
            )
        )
    }

    @Test("グループ内の期限が来た復習と未学習語だけが出る")
    func onlyGroupWords() {
        let result = plan(
            words: ["a1-0001", "a1-0002", "a1-0003", "a1-0004"],
            progress: [
                snapshot("a1-0001", stage: 2, dueOffset: -1),  // 期限切れ → 復習
                snapshot("a1-0002", stage: 3, dueOffset: 3),  // 期限前 → 出ない
                snapshot("a1-0100", stage: 2, dueOffset: -1),  // グループ外 → 出ない
            ]
        )
        #expect(result.reviewWordIds == ["a1-0001"])
        #expect(result.newWordIds == ["a1-0003", "a1-0004"])
        #expect(result.deferredReviewCount == 0)
    }

    @Test("新規語は追加順で、1 回の上限まで")
    func newWordsInOrderUpToLimit() {
        let ids = ["a1-0010", "a1-0003", "a1-0007", "a1-0001"]
        let result = plan(words: ids, progress: [], limit: 3)
        #expect(result.newWordIds == ["a1-0010", "a1-0003", "a1-0007"])
    }

    @Test("集計: 語数・学習済み・期限・開花")
    func summaryCounts() {
        let progress = [
            snapshot("a1-0001", stage: 5, dueOffset: 30),
            snapshot("a1-0002", stage: 2, dueOffset: 0),
            snapshot("a1-0100", stage: 2, dueOffset: -1),
        ]
        let summary = GroupStudy.summary(
            wordIds: ["a1-0001", "a1-0002", "a1-0003"],
            progressByWordId: Dictionary(uniqueKeysWithValues: progress.map { ($0.wordId, $0) }),
            now: now
        )
        #expect(summary == GroupStudy.Summary(total: 3, learned: 2, due: 1, blossomed: 1))
        #expect(summary.unlearned == 1)
    }
}

@Suite("グループと自作語の編集")
struct GroupEditorTests {
    let now = TestDate.at(2026, 8, 14)
    let context: ModelContext
    let editor: GroupEditor

    init() throws {
        context = try makeContext()
        editor = GroupEditor(context: context)
    }

    @Test("空の名前は既定名になり、前後の空白は落とす")
    func groupName() {
        #expect(editor.createGroup(name: "  ", now: now).name == "新しいグループ")
        #expect(editor.createGroup(name: " Unit 3 ", now: now).name == "Unit 3")
    }

    @Test("追加は末尾に、重複は入れない。外すと消える")
    func addAndRemove() {
        let group = editor.createGroup(name: "g", now: now)
        editor.add(wordIds: ["a1-0002", "a1-0001"], to: group, now: now)
        editor.add(wordIds: ["a1-0001", "a1-0003", "a1-0003"], to: group, now: now)
        #expect(group.wordIds == ["a1-0002", "a1-0001", "a1-0003"])

        editor.remove(wordIds: ["a1-0001"], from: group, now: now)
        #expect(group.wordIds == ["a1-0002", "a1-0003"])
    }

    @Test("まとめて外せる。残りの順番は保ち、更新日時が進む。入っていない語だけなら何もしない")
    func removeMany() {
        let group = editor.createGroup(name: "g", now: now)
        editor.add(wordIds: ["a", "b", "c", "d"], to: group, now: now)
        let later = now.addingTimeInterval(60)
        editor.remove(wordIds: ["d", "b"], from: group, now: later)
        #expect(group.wordIds == ["a", "c"])
        #expect(group.updatedAt == later)

        editor.remove(wordIds: ["x"], from: group, now: later.addingTimeInterval(60))
        #expect(group.wordIds == ["a", "c"])
        #expect(group.updatedAt == later)
    }

    @Test("選択画面の結果: 残す語の順番は保ち、新しい語は選んだ順で末尾へ")
    func setMembership() {
        let group = editor.createGroup(name: "g", now: now)
        editor.add(wordIds: ["a", "b", "c"], to: group, now: now)
        editor.setMembership(["c", "x", "a", "y"], for: group, now: now)
        #expect(group.wordIds == ["a", "c", "x", "y"])
    }

    @Test("自作語を作るとグループの末尾に入り、索引から引ける")
    func createCustomWord() throws {
        let group = editor.createGroup(name: "g", now: now)
        editor.add(wordIds: ["a1-0001"], to: group, now: now)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(
                word: "  take care of ", meaning: " 〜の世話をする ", pos: .phrase,
                example: "I take care of my dog.", exampleJa: "私は犬の世話をします。"
            ),
            addingTo: group,
            now: now
        )

        #expect(CustomWord.isCustom(custom.wordId))
        #expect(custom.word == "take care of")
        #expect(custom.meaning == "〜の世話をする")
        #expect(group.wordIds == ["a1-0001", custom.wordId])
        #expect(editor.customWord(id: custom.wordId) === custom)

        let store = WordStore.shared.including(customWords: [custom.entry])
        #expect(store.word(id: custom.wordId)?.isCustom == true)
    }

    @Test("英語と意味が無ければ保存できない。空白入りは熟語と推測する")
    func draftValidation() {
        #expect(!GroupEditor.WordDraft(word: "dog", meaning: " ").isValid)
        #expect(!GroupEditor.WordDraft(word: " ", meaning: "犬").isValid)
        #expect(GroupEditor.WordDraft(word: "dog", meaning: "犬").isValid)
        #expect(GroupEditor.WordDraft.guessedPos(for: "look after") == .phrase)
        #expect(GroupEditor.WordDraft.guessedPos(for: "dog ") == .noun)
    }

    @Test("例文に英語が見つからないときだけ「穴埋めにならない」と判定する")
    func exampleMissesWord() {
        func draft(_ word: String, _ example: String) -> GroupEditor.WordDraft {
            GroupEditor.WordDraft(word: word, meaning: "意味", example: example)
        }
        #expect(draft("homeroom", "We have homeroom at 8.").exampleMissesWord == false)
        // 活用形・熟語の活用でも見つかれば穴埋めにできる
        #expect(draft("commute", "She commutes by train.").exampleMissesWord == false)
        #expect(draft("look after", "He looked after the dog.").exampleMissesWord == false)
        #expect(draft("homeroom", "We meet in the morning.").exampleMissesWord)
        // 例文・英語が空なら案内しない
        #expect(draft("homeroom", " ").exampleMissesWord == false)
        #expect(draft(" ", "We have homeroom.").exampleMissesWord == false)
    }

    @Test("検索語から下書きを作る: 英語は英語欄、日本語は意味欄へ")
    func prefilledFromSearch() {
        let english = GroupEditor.WordDraft.prefilled(fromSearch: " take care of ")
        #expect(english.word == "take care of")
        #expect(english.meaning.isEmpty)
        #expect(english.pos == .phrase)

        let japanese = GroupEditor.WordDraft.prefilled(fromSearch: "学級会")
        #expect(japanese.word.isEmpty)
        #expect(japanese.meaning == "学級会")

        #expect(GroupEditor.WordDraft.prefilled(fromSearch: "  ") == GroupEditor.WordDraft())
    }

    @Test("自作語を編集できる")
    func updateCustomWord() {
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(word: "dog", meaning: "猫"), now: now
        )
        var draft = custom.draft
        draft.meaning = "犬"
        editor.update(custom, with: draft, now: now)
        #expect(custom.meaning == "犬")
    }

    @Test("意味が複数の自作語を作り・直せる（2 つ目以降も前後の空白を落とす）")
    func customWordWithSenses() throws {
        var draft = GroupEditor.WordDraft(word: "commute", meaning: "通勤する", pos: .verb)
        draft.extraSenses = [WordSense(pos: .noun, meaning: " 通勤 ", example: " My commute is long. ")]
        let custom = editor.createCustomWord(draft, now: now)
        #expect(custom.extraSenses == [WordSense(pos: .noun, meaning: "通勤", example: "My commute is long.")])
        #expect(custom.entry.senses.map(\.pos) == [.verb, .noun])
        #expect(custom.draft.senses.map(\.meaning) == ["通勤する", "通勤"])

        // 意味を消して 1 つに戻せる
        var edited = custom.draft
        edited.senses = [edited.senses[1]]
        editor.update(custom, with: edited, now: now)
        #expect(custom.pos == .noun)
        #expect(custom.meaning == "通勤")
        #expect(custom.extraSenses.isEmpty)
        #expect(custom.extraSensesData == nil)
    }

    @Test("意味が複数の下書き: どれか 1 つでも意味が空なら保存できない。足す意味の品詞はまだ使っていないもの")
    func draftWithSensesValidation() {
        var draft = GroupEditor.WordDraft(word: "commute", meaning: "通勤する", pos: .verb)
        #expect(draft.nextSensePos == .noun)
        draft.extraSenses = [WordSense(pos: .noun, meaning: " ")]
        #expect(!draft.isValid)
        draft.extraSenses[0].meaning = "通勤"
        #expect(draft.isValid)
        #expect(draft.nextSensePos == .adjective)

        // 例文の判定は意味ごと
        draft.extraSenses[0].example = "The trip is long."
        #expect(draft.exampleMissesWord(in: draft.extraSenses[0]))
        #expect(!draft.exampleMissesWord)

        // 意味を空にしても 1 つは残る
        draft.senses = []
        #expect(draft.senses.count == 1)
        #expect(draft.extraSenses.isEmpty)
    }

    @Test("自作語を消すと、グループ・進捗・回答ログからも消える")
    func deleteCustomWord() throws {
        let first = editor.createGroup(name: "1", now: now)
        let second = editor.createGroup(name: "2", now: now)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(word: "homeroom", meaning: "ホームルーム"),
            addingTo: first,
            now: now
        )
        let wordId = custom.wordId
        editor.add(wordIds: ["a1-0001", wordId], to: second, now: now)
        let engine = LearningEngine(context: context)
        engine.record(wordId: wordId, correct: true, quizType: .enToJa, kind: .new, now: now)
        engine.record(wordId: "a1-0001", correct: true, quizType: .enToJa, kind: .new, now: now)

        editor.deleteCustomWord(id: wordId)

        #expect(editor.customWord(id: wordId) == nil)
        #expect(first.wordIds.isEmpty)
        #expect(second.wordIds == ["a1-0001"])
        #expect(engine.progress(for: wordId) == nil)
        let logs = try context.fetch(FetchDescriptor<AnswerLog>())
        #expect(logs.map(\.wordId) == ["a1-0001"])
        // ほかの語の進捗は残る
        #expect(engine.progress(for: "a1-0001") != nil)
    }

    @Test("「単語を追加」の保存: 同じ綴りのマイ単語が無ければ作り、あれば ID を変えずに内容を置き換える")
    func upsertReplacesSameSpelling() throws {
        let created = editor.upsertCustomWord(
            GroupEditor.WordDraft(word: "commute", meaning: "通勤する", pos: .verb), now: now
        )
        let wordId = created.wordId
        let engine = LearningEngine(context: context)
        engine.record(wordId: wordId, correct: true, quizType: .enToJa, kind: .new, now: now)

        var draft = GroupEditor.WordDraft(word: " Commute ", meaning: "通勤する、通学する", pos: .verb)
        draft.extraSenses = [WordSense(pos: .noun, meaning: "通勤")]
        let later = now.addingTimeInterval(60)
        let replaced = editor.upsertCustomWord(draft, now: later)

        #expect(replaced.wordId == wordId)
        #expect(try context.fetch(FetchDescriptor<CustomWord>()).count == 1)
        #expect(replaced.meaning == "通勤する、通学する")
        #expect(replaced.extraSenses == [WordSense(pos: .noun, meaning: "通勤")])
        #expect(replaced.updatedAt == later)
        // 学習の記録は残る
        #expect(engine.progress(for: wordId) != nil)
    }

    @Test("同じ綴りのマイ単語が複数あれば、いちばん新しいものに寄せ、グループでの位置を引き継いでほかは消す")
    func upsertMergesDuplicates() throws {
        let old = editor.createCustomWord(
            GroupEditor.WordDraft(word: "commute", meaning: "古い", pos: .verb), now: now
        )
        let newer = editor.createCustomWord(
            GroupEditor.WordDraft(word: "commute", meaning: "新しい", pos: .verb),
            now: now.addingTimeInterval(10)
        )
        let onlyOld = editor.createGroup(name: "古い方だけ", now: now)
        editor.add(wordIds: ["a1-0001", old.wordId, "a1-0002"], to: onlyOld, now: now)
        let both = editor.createGroup(name: "両方", now: now)
        editor.add(wordIds: [old.wordId, newer.wordId], to: both, now: now)

        let later = now.addingTimeInterval(60)
        let kept = editor.upsertCustomWord(
            GroupEditor.WordDraft(word: "commute", meaning: "通勤する", pos: .verb), now: later
        )

        #expect(kept.wordId == newer.wordId)
        #expect(try context.fetch(FetchDescriptor<CustomWord>()).map(\.wordId) == [newer.wordId])
        #expect(kept.meaning == "通勤する")
        #expect(onlyOld.wordIds == ["a1-0001", newer.wordId, "a1-0002"])
        #expect(both.wordIds == [newer.wordId])
        #expect(onlyOld.updatedAt == later)
        // 消した方は削除記録が残り、同期でほかの端末・サーバーからも消える
        let deletions = try context.fetch(FetchDescriptor<SyncDeletion>())
        #expect(deletions.map(\.recordId) == [old.wordId])
    }

    @Test("グループを消しても進捗と自作語は残る")
    func deleteGroupKeepsWords() throws {
        let group = editor.createGroup(name: "g", now: now)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(word: "homeroom", meaning: "ホームルーム"),
            addingTo: group,
            now: now
        )
        LearningEngine(context: context).record(
            wordId: custom.wordId, correct: true, quizType: .enToJa, kind: .new, now: now
        )
        editor.delete(group)

        #expect(try context.fetch(FetchDescriptor<WordGroup>()).isEmpty)
        #expect(editor.customWord(id: custom.wordId) != nil)
        #expect(LearningEngine(context: context).progress(for: custom.wordId) != nil)
    }
}

@Suite("ドリル（進捗を動かさない練習）")
struct DrillTests {
    let now = TestDate.at(2026, 8, 14)
    let context: ModelContext
    let engine: LearningEngine

    init() throws {
        context = try makeContext()
        engine = LearningEngine(context: context)
    }

    private func drill(_ ids: [String], store: WordStore = .shared) -> SessionRunner {
        SessionRunner(
            drillWordIds: ids, engine: engine, store: store, rng: SeededRNG(seed: 7), clock: { now }
        )
    }

    private func answer(_ runner: SessionRunner, correct: Bool) throws -> String {
        guard case .quiz(let quiz, _) = runner.step else {
            Issue.record("クイズではなく \(runner.step) が表示されている")
            throw CancellationError()
        }
        let index = correct ? quiz.answerIndex : (quiz.answerIndex + 1) % quiz.choices.count
        runner.answer(choiceIndex: index)
        runner.next()
        return quiz.word.id
    }

    @Test("全語がクイズで出て、進捗もログも増えない")
    func drillDoesNotRecord() throws {
        let ids = ["a1-0001", "a1-0002", "a1-0003"]
        let runner = drill(ids)
        #expect(runner.mode == .drill)
        #expect(runner.remainingCount == 3)

        var asked: [String] = []
        for _ in ids { asked.append(try answer(runner, correct: true)) }

        #expect(asked == ids)
        #expect(runner.isFinished)
        #expect(runner.stats.answered == 3)
        #expect(runner.stats.correct == 3)
        #expect(runner.stats.learnedWordIds.isEmpty)
        #expect(try context.fetch(FetchDescriptor<WordProgress>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AnswerLog>()).isEmpty)
    }

    @Test("間違えた語は末尾で再出題され、間違えた語として残る")
    func missedWordsRequeue() throws {
        let runner = drill(["a1-0001", "a1-0002"])
        let missed = try answer(runner, correct: false)
        _ = try answer(runner, correct: true)

        guard case .quiz(let quiz, let kind) = runner.step else {
            Issue.record("再出題が無い")
            return
        }
        #expect(quiz.word.id == missed)
        #expect(kind == .requeue)
        _ = try answer(runner, correct: true)
        #expect(runner.isFinished)
        #expect(runner.stats.missedWordIds == [missed])
        #expect(try context.fetch(FetchDescriptor<AnswerLog>()).isEmpty)
    }

    @Test("出題形式は今のステージで決まり、ステージは変わらない")
    func quizTypeFollowsStage() throws {
        engine.record(wordId: "a1-0004", correct: true, quizType: .enToJa, kind: .new, now: now)
        let progress = try #require(engine.progress(for: "a1-0004"))
        progress.stage = 4
        try context.save()

        let runner = drill(["a1-0004"])
        guard case .quiz(let quiz, _) = runner.step else {
            Issue.record("クイズが無い")
            return
        }
        #expect(quiz.type == .jaToEn)
        _ = try answer(runner, correct: false)
        #expect(engine.progress(for: "a1-0004")?.stage == 4)
    }

    @Test("形式を穴埋めに固定すると、ステージに関係なく再出題も穴埋めで出て、何も記録しない")
    func fillBlankDrill() throws {
        engine.record(wordId: "a1-0004", correct: true, quizType: .enToJa, kind: .new, now: now)
        let progress = try #require(engine.progress(for: "a1-0004"))
        progress.stage = 5
        try context.save()
        let logsBefore = try context.fetch(FetchDescriptor<AnswerLog>()).count

        let ids = ["a1-0004", "a1-0821", "ph-0005"]
        let runner = SessionRunner(
            drillWordIds: ids, quizType: .fillBlank, engine: engine,
            rng: SeededRNG(seed: 7), clock: { now }
        )
        #expect(runner.mode == .drill)
        #expect(runner.drillQuizType == .fillBlank)

        var types: [QuizType] = []
        var kinds: [AnswerKind] = []
        var first = true
        while case .quiz(let quiz, let kind) = runner.step {
            types.append(quiz.type)
            kinds.append(kind)
            _ = try answer(runner, correct: !first)
            first = false
        }
        #expect(runner.isFinished)
        #expect(types.count == 4)
        #expect(types.allSatisfy { $0 == .fillBlank })
        #expect(kinds.last == .requeue)
        #expect(runner.stats.missedWordIds == ["a1-0004"])
        #expect(engine.progress(for: "a1-0004")?.stage == 5)
        #expect(try context.fetch(FetchDescriptor<AnswerLog>()).count == logsBefore)
    }

    @Test("形式を指定しないドリルは、形式を固定しない")
    func drillWithoutQuizType() {
        #expect(drill(["a1-0001"]).drillQuizType == nil)
    }

    @Test("自作語もドリルで出せる（例文が無ければ穴埋めにしない）")
    func customWordsInDrill() throws {
        let custom = WordEntry(
            id: "custom-1", word: "homeroom", pos: .noun, level: nil, meaning: "ホームルーム",
            example: "", exampleJa: ""
        )
        let store = WordStore.shared.including(customWords: [custom])
        var builder = QuizBuilder(store: store, rng: SeededRNG(seed: 1))
        let quiz = builder.make(for: custom, type: .fillBlank)
        #expect(quiz.type == .enToJa)
        #expect(quiz.choices.count == QuizBuilder.choiceCount)
        #expect(Set(quiz.choices.map(\.id)).count == QuizBuilder.choiceCount)
        #expect(quiz.choices.contains(custom))

        let runner = drill(["custom-1"], store: store)
        #expect(try answer(runner, correct: true) == "custom-1")
    }

    @Test("グループを渡すと、自作語の誤答肢に同じグループの語が入る")
    func drillUsesGroupForCustomDistractors() throws {
        let store = WordStore.shared.including(customWords: [customEntry("custom-1", word: "homeroom")])
        let runner = SessionRunner(
            drillWordIds: ["custom-1"], engine: engine, store: store,
            groups: [QuizGroup(name: "Unit 1", wordIds: ["custom-1", "a1-0004", "a1-0005", "a1-0006"])],
            rng: SeededRNG(seed: 7), clock: { now }
        )
        guard case .quiz(let quiz, _) = runner.step else {
            Issue.record("クイズが無い")
            return
        }
        #expect(Set(quiz.choices.map(\.id)) == ["custom-1", "a1-0004", "a1-0005", "a1-0006"])
    }

    @Test("いつもの学習では自作語も SRS に記録される")
    func learningRecordsCustomWord() throws {
        let custom = WordEntry(
            id: "custom-1", word: "homeroom", pos: .noun, level: nil, meaning: "ホームルーム",
            example: "", exampleJa: ""
        )
        let store = WordStore.shared.including(customWords: [custom])
        let runner = SessionRunner(
            plan: SessionPlan(newWordIds: ["custom-1"]),
            engine: engine, store: store, rng: SeededRNG(seed: 1), clock: { now }
        )
        #expect(runner.mode == .learning)
        guard case .present(let word) = runner.step else {
            Issue.record("提示カードが無い")
            return
        }
        #expect(word == custom)
        runner.next()
        _ = try answer(runner, correct: true)
        #expect(engine.progress(for: "custom-1")?.stage == SRS.minLearnedStage)
        #expect(runner.stats.learnedWordIds == ["custom-1"])
    }
}

@Suite("バックアップ（グループ・自作語）")
struct GroupBackupTests {
    let now = TestDate.at(2026, 8, 14)

    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "group-backup-\(UUID().uuidString)")!)
    }

    @Test("グループと自作語も書き出して復元できる")
    func roundTrip() throws {
        let context = try makeContext()
        let editor = GroupEditor(context: context)
        let group = editor.createGroup(name: "Unit 3", now: now)
        editor.add(wordIds: ["a1-0001"], to: group, now: now)
        let custom = editor.createCustomWord(
            GroupEditor.WordDraft(
                word: "take care of", meaning: "〜の世話をする", pos: .phrase,
                example: "I take care of it.", exampleJa: "私がそれの面倒を見ます。"
            ),
            addingTo: group,
            now: now
        )
        custom.extraSenses = [WordSense(pos: .verb, meaning: "〜を引き受ける")]
        let data = try BackupService.export(context: context, settings: settings(), now: now)

        let other = try makeContext()
        GroupEditor(context: other).createGroup(name: "消える", now: now)
        let archive = try BackupService.restore(from: data, context: other, settings: settings())

        #expect(archive.version == BackupArchive.currentVersion)
        let groups = try other.fetch(FetchDescriptor<WordGroup>())
        #expect(groups.map(\.name) == ["Unit 3"])
        #expect(groups.first?.id == group.id)
        #expect(groups.first?.wordIds == ["a1-0001", custom.wordId])
        let restored = try #require(GroupEditor(context: other).customWord(id: custom.wordId))
        #expect(restored.entry == custom.entry)
        #expect(restored.extraSenses == [WordSense(pos: .verb, meaning: "〜を引き受ける")])
    }

    @Test("2 つ目以降の意味の無い version 2 のファイルも読める（意味が 1 つの自作語になる）")
    func readsVersionTwo() throws {
        let json = """
        {
          "version": 2,
          "exportedAt": "2026-08-14T03:00:00Z",
          "settings": {"level": "A1", "newWordsPerDay": 10, "reviewLimitPerDay": 60, "soundEnabled": true},
          "progress": [],
          "logs": [],
          "groups": [],
          "customWords": [{"wordId": "custom-old", "word": "homeroom", "meaning": "ホームルーム",
                           "pos": "noun", "example": "", "exampleJa": "",
                           "createdAt": "2026-08-13T00:00:00Z", "updatedAt": "2026-08-13T00:00:00Z"}]
        }
        """
        let context = try makeContext()
        try BackupService.restore(from: Data(json.utf8), context: context, settings: settings())
        let custom = try #require(GroupEditor(context: context).customWord(id: "custom-old"))
        #expect(custom.extraSenses.isEmpty)
        #expect(custom.entry.senses == [WordSense(pos: .noun, meaning: "ホームルーム")])
    }

    @Test("グループの無い version 1 のファイルも読める")
    func readsVersionOne() throws {
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-08-14T03:00:00Z",
          "settings": {"level": "A1", "newWordsPerDay": 10, "reviewLimitPerDay": 60, "soundEnabled": true},
          "progress": [{"wordId": "a1-0001", "stage": 2, "dueAt": "2026-08-15T00:00:00Z",
                        "learnedAt": "2026-08-13T00:00:00Z", "updatedAt": "2026-08-13T00:00:00Z",
                        "known": false}],
          "logs": []
        }
        """
        let context = try makeContext()
        GroupEditor(context: context).createGroup(name: "既存", now: now)

        let archive = try BackupService.restore(
            from: Data(json.utf8), context: context, settings: settings()
        )
        #expect(archive.groups == nil)
        #expect(archive.customWords == nil)
        #expect(try context.fetch(FetchDescriptor<WordProgress>()).count == 1)
        // 置き換え方式なので、今のグループは消える
        #expect(try context.fetch(FetchDescriptor<WordGroup>()).isEmpty)
    }
}
