import Foundation

/// グループ単位の学習で何を出すかを決める（純粋関数）。
enum GroupStudy {
    struct Input {
        var now: Date
        /// グループの単語（追加順。削除済みの自作語などは引き直しで落としてある）
        var words: [WordEntry]
        /// 全単語の進捗。グループ内に絞るのはこちらでやる
        var progress: [ProgressSnapshot]
        /// 1 回のセッションで出す新規語の上限
        var newWordsLimit: Int
        var reviewLimit: Int
        var order: ShuffleOrder = .install
    }

    /// グループ内の「期限が来た復習」と「未学習語」だけのセッション。
    ///
    /// 範囲を覚え切りたい用途なので、今日すでに学習した数では絞らない
    /// （上限まで出し切ったら、もう一度開けば続きが出る）。新規語はグループの追加順で出す。
    static func plan(_ input: Input) -> SessionPlan {
        let ids = Set(input.words.map(\.id))
        return SessionBuilder.build(
            SessionBuilder.Input(
                now: input.now,
                progress: input.progress.filter { ids.contains($0.wordId) },
                newWordPool: input.words,
                newWordsPerDay: input.newWordsLimit,
                reviewLimitPerDay: input.reviewLimit,
                order: input.order
            )
        )
    }

    /// グループの状況。一覧・詳細の表示に使う
    struct Summary: Equatable {
        var total = 0
        /// 学習を始めた語（進捗レコードがある語）
        var learned = 0
        /// 今日までに期限が来た復習
        var due = 0
        /// 開花した語
        var blossomed = 0

        var unlearned: Int { total - learned }
    }

    static func summary(
        wordIds: [String],
        progressByWordId: [String: ProgressSnapshot],
        now: Date
    ) -> Summary {
        let today = DateUtil.startOfDay(now)
        var result = Summary(total: wordIds.count)
        for wordId in wordIds {
            guard let progress = progressByWordId[wordId] else { continue }
            result.learned += 1
            if DateUtil.startOfDay(progress.dueAt) <= today { result.due += 1 }
            if progress.stage >= SRS.maxStage { result.blossomed += 1 }
        }
        return result
    }

    /// グループの問題への 1 回答（`GroupAnswerLog` から集計に要る分だけ取り出した値）
    struct Answer: Equatable {
        var wordId: String
        var answeredAt: Date
        var correct: Bool
    }

    /// グループの問題をこなした状況。一覧・詳細の表示に使う
    struct Activity: Equatable {
        /// 答えた回数（再出題も 1 回と数える。グループから外した語の分も含む）
        var answerCount = 0
        /// 今のグループの語のうち、最後に答えたときに正解だった語
        var achieved = 0
        /// 今のグループの語数
        var total = 0

        /// 達成度（0〜1）。語が無いときは nil
        var achievement: Double? {
            total > 0 ? Double(achieved) / Double(total) : nil
        }
    }

    /// 回答数と達成度。達成度は「今の語のうち、最後の回答が正解の語の割合」。
    /// 答えたことが無い語・最後に間違えた語は未達成。グループから外した語は数えない
    static func activity(wordIds: [String], answers: [Answer]) -> Activity {
        var latest: [String: Answer] = [:]
        for answer in answers {
            if let current = latest[answer.wordId], current.answeredAt > answer.answeredAt { continue }
            latest[answer.wordId] = answer
        }
        let ids = Set(wordIds)
        return Activity(
            answerCount: answers.count,
            achieved: ids.count { latest[$0]?.correct == true },
            total: ids.count
        )
    }
}
