import Foundation
import SwiftData
import Testing

@testable import VocabBlossom

@Suite("進捗のエクスポート / インポート")
struct BackupTests {
    let now = TestDate.at(2026, 8, 14)
    let context: ModelContext
    let settings: AppSettings
    let defaultsName = "backup-tests-\(UUID().uuidString)"

    init() throws {
        let container = try ModelContainer(
            for: WordProgress.self, AnswerLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        settings = AppSettings(defaults: UserDefaults(suiteName: defaultsName)!)
    }

    private func seed() throws {
        let engine = LearningEngine(context: context)
        engine.record(wordId: "a1-0001", correct: true, quizType: .enToJa, kind: .new, now: now)
        engine.record(
            wordId: "a1-0002", correct: false, quizType: .fillBlank, kind: .review, now: now
        )
        engine.markKnown(wordId: "a1-0003", now: now)
        try context.save()
    }

    @Test("書き出して読み込むと進捗・ログ・設定が復元される")
    func roundTrip() throws {
        try seed()
        settings.level = .a2
        settings.newWordsPerDay = 20
        settings.soundEnabled = false

        let data = try BackupService.export(context: context, settings: settings, now: now)

        // 別の端末を模して、進捗も設定も違う状態から読み込む
        let other = try ModelContainer(
            for: WordProgress.self, AnswerLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let otherContext = ModelContext(other)
        let otherSettings = AppSettings(
            defaults: UserDefaults(suiteName: "backup-tests-other-\(UUID().uuidString)")!
        )
        otherContext.insert(
            WordProgress(
                wordId: "zzz", stage: 5, dueAt: now, learnedAt: now, updatedAt: now
            )
        )
        try otherContext.save()

        let archive = try BackupService.restore(
            from: data, context: otherContext, settings: otherSettings
        )
        #expect(archive.version == BackupArchive.currentVersion)

        let progress = try otherContext.fetch(
            FetchDescriptor<WordProgress>(sortBy: [SortDescriptor(\.wordId)])
        )
        #expect(progress.map(\.wordId) == ["a1-0001", "a1-0002", "a1-0003"])
        #expect(progress.first { $0.wordId == "a1-0003" }?.known == true)
        #expect(progress.first { $0.wordId == "a1-0001" }?.dueAt == DateUtil.startOfDay(
            DateUtil.addDays(now, 1)
        ))

        let logs = try otherContext.fetch(FetchDescriptor<AnswerLog>())
        #expect(logs.count == 2)
        #expect(logs.contains { $0.quizType == .fillBlank && $0.correct == false })

        #expect(otherSettings.level == .a2)
        #expect(otherSettings.newWordsPerDay == 20)
        #expect(otherSettings.soundEnabled == false)
    }

    @Test("読み込みは置き換え方式（元の進捗は残らない）")
    func restoreReplacesExistingData() throws {
        try seed()
        let data = try BackupService.export(context: context, settings: settings, now: now)

        let engine = LearningEngine(context: context)
        engine.record(wordId: "a1-0100", correct: true, quizType: .enToJa, kind: .new, now: now)
        #expect(engine.progress(for: "a1-0100") != nil)

        try BackupService.restore(from: data, context: context, settings: settings)
        #expect(engine.progress(for: "a1-0100") == nil)
        #expect(try context.fetch(FetchDescriptor<AnswerLog>()).count == 2)
    }

    @Test("空の状態でも書き出せる")
    func exportsEmptyState() throws {
        let data = try BackupService.export(context: context, settings: settings, now: now)
        let archive = try BackupService.decoder.decode(BackupArchive.self, from: data)
        #expect(archive.progress.isEmpty)
        #expect(archive.logs.isEmpty)
        #expect(archive.exportedAt == now)
    }

    @Test("壊れたファイルは読み込まずエラーにする")
    func malformedDataThrows() throws {
        try seed()
        #expect(throws: BackupError.self) {
            try BackupService.restore(
                from: Data("not json".utf8), context: context, settings: settings
            )
        }
        // 失敗しても元の進捗は消えない
        #expect(LearningEngine(context: context).progress(for: "a1-0001") != nil)
    }

    @Test("新しい形式のファイルは読み込まない")
    func futureVersionThrows() throws {
        var archive = BackupArchive(
            exportedAt: now,
            settings: BackupArchive.Settings(
                level: .a1, newWordsPerDay: 10, reviewLimitPerDay: 60, soundEnabled: true
            ),
            progress: [],
            logs: []
        )
        archive.version = BackupArchive.currentVersion + 1
        let data = try BackupService.encoder.encode(archive)

        #expect(throws: BackupError.self) {
            try BackupService.restore(from: data, context: context, settings: settings)
        }
    }

    @Test("ファイル名は書き出した日付になる")
    func fileNameUsesDate() {
        #expect(BackupService.fileName(now: now) == "vocab-blossom-2026-08-14.json")
    }
}
