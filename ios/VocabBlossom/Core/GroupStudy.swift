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
}
