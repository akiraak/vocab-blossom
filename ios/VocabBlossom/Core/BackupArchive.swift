import Foundation
import SwiftData

/// 学習進捗のエクスポート/インポート形式。
///
/// MVP は端末間同期を持たないので、機種変更や取り違えの保険としてこの JSON を書き出す。
/// 取り込みは「置き換え」方式（差分マージはしない）。
///
/// - version 1: 設定・進捗・回答ログ
/// - version 2: グループと自作語を追加（v1 のファイルには無いので nil として読む）
/// - version 3: 自作語の 2 つ目以降の意味（`extraSenses`）を追加（v2 のファイルには無いので空として読む）
struct BackupArchive: Codable, Equatable {
    static let currentVersion = 3

    var version = currentVersion
    var exportedAt: Date
    var settings: Settings
    var progress: [Progress]
    var logs: [Log]
    var groups: [Group]?
    var customWords: [Custom]?

    struct Settings: Codable, Equatable {
        var level: CefrLevel
        var newWordsPerDay: Int
        var reviewLimitPerDay: Int
        var soundEnabled: Bool
    }

    struct Progress: Codable, Equatable {
        var wordId: String
        var stage: Int
        var dueAt: Date
        var learnedAt: Date
        var updatedAt: Date
        var known: Bool
    }

    struct Log: Codable, Equatable {
        var wordId: String
        var answeredAt: Date
        var dateKey: String
        var correct: Bool
        var quizType: QuizType
        var kind: AnswerKind
        var stageAfter: Int
    }

    struct Group: Codable, Equatable {
        var id: UUID
        var name: String
        var wordIds: [String]
        var createdAt: Date
        var updatedAt: Date
    }

    struct Custom: Codable, Equatable {
        var wordId: String
        var word: String
        var meaning: String
        var pos: PartOfSpeech
        var example: String
        var exampleJa: String
        var extraSenses: [WordSense]?
        var createdAt: Date
        var updatedAt: Date
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case malformed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "このファイル（形式 \(version)）はこのバージョンのアプリでは読み込めません。"
        case .malformed:
            "ファイルの形式が正しくないため読み込めませんでした。"
        }
    }
}

enum BackupService {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func fileName(now: Date = .now) -> String {
        "vocab-blossom-\(DateUtil.dateKey(now)).json"
    }

    static func makeArchive(
        context: ModelContext,
        settings: AppSettings,
        now: Date = .now
    ) throws -> BackupArchive {
        let progress = try context.fetch(
            FetchDescriptor<WordProgress>(sortBy: [SortDescriptor(\.wordId)])
        )
        let logs = try context.fetch(
            FetchDescriptor<AnswerLog>(sortBy: [SortDescriptor(\.answeredAt)])
        )
        let groups = try context.fetch(
            FetchDescriptor<WordGroup>(sortBy: [SortDescriptor(\.createdAt)])
        )
        let customWords = try context.fetch(
            FetchDescriptor<CustomWord>(sortBy: [SortDescriptor(\.createdAt)])
        )
        return BackupArchive(
            exportedAt: now,
            settings: BackupArchive.Settings(
                level: settings.level,
                newWordsPerDay: settings.newWordsPerDay,
                reviewLimitPerDay: settings.reviewLimitPerDay,
                soundEnabled: settings.soundEnabled
            ),
            progress: progress.map {
                BackupArchive.Progress(
                    wordId: $0.wordId, stage: $0.stage, dueAt: $0.dueAt,
                    learnedAt: $0.learnedAt, updatedAt: $0.updatedAt, known: $0.known
                )
            },
            logs: logs.map {
                BackupArchive.Log(
                    wordId: $0.wordId, answeredAt: $0.answeredAt, dateKey: $0.dateKey,
                    correct: $0.correct, quizType: $0.quizType, kind: $0.kind,
                    stageAfter: $0.stageAfter
                )
            },
            groups: groups.map {
                BackupArchive.Group(
                    id: $0.id, name: $0.name, wordIds: $0.wordIds,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            },
            customWords: customWords.map {
                BackupArchive.Custom(
                    wordId: $0.wordId, word: $0.word, meaning: $0.meaning, pos: $0.pos,
                    example: $0.example, exampleJa: $0.exampleJa,
                    extraSenses: $0.extraSenses.isEmpty ? nil : $0.extraSenses,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }
        )
    }

    static func export(
        context: ModelContext,
        settings: AppSettings,
        now: Date = .now
    ) throws -> Data {
        try encoder.encode(makeArchive(context: context, settings: settings, now: now))
    }

    /// 取り込みは置き換え方式。今の進捗を消してからファイルの内容を入れる
    @discardableResult
    static func restore(
        from data: Data,
        context: ModelContext,
        settings: AppSettings
    ) throws -> BackupArchive {
        let archive: BackupArchive
        do {
            archive = try decoder.decode(BackupArchive.self, from: data)
        } catch {
            throw BackupError.malformed
        }
        guard archive.version <= BackupArchive.currentVersion else {
            throw BackupError.unsupportedVersion(archive.version)
        }

        try context.delete(model: WordProgress.self)
        try context.delete(model: AnswerLog.self)
        try context.delete(model: WordGroup.self)
        try context.delete(model: CustomWord.self)
        // 復元より前の削除記録は捨てる（復元後は全件を送り直し、サーバーの全件も受け取り直す: SyncService.resendAll）
        try context.delete(model: SyncDeletion.self)

        for item in archive.progress {
            context.insert(
                WordProgress(
                    wordId: item.wordId, stage: item.stage, dueAt: item.dueAt,
                    learnedAt: item.learnedAt, updatedAt: item.updatedAt, known: item.known
                )
            )
        }
        for item in archive.logs {
            context.insert(
                AnswerLog(
                    wordId: item.wordId, answeredAt: item.answeredAt, dateKey: item.dateKey,
                    correct: item.correct, quizType: item.quizType, kind: item.kind,
                    stageAfter: item.stageAfter
                )
            )
        }
        for item in archive.groups ?? [] {
            context.insert(
                WordGroup(
                    id: item.id, name: item.name, wordIds: item.wordIds,
                    createdAt: item.createdAt, updatedAt: item.updatedAt
                )
            )
        }
        for item in archive.customWords ?? [] {
            context.insert(
                CustomWord(
                    wordId: item.wordId, word: item.word, meaning: item.meaning, pos: item.pos,
                    example: item.example, exampleJa: item.exampleJa,
                    extraSenses: item.extraSenses ?? [],
                    createdAt: item.createdAt, updatedAt: item.updatedAt
                )
            )
        }
        try context.save()

        settings.level = archive.settings.level
        settings.newWordsPerDay = archive.settings.newWordsPerDay
        settings.soundEnabled = archive.settings.soundEnabled
        // reviewLimitPerDay は新規語数からの算出値なので、書き出すだけで復元はしない
        return archive
    }
}
