import Foundation

/// SwiftData から切り離した進捗の値。セッション構築を純粋関数に保つために使う。
struct ProgressSnapshot: Equatable, Sendable {
    let wordId: String
    let stage: Int
    let dueAt: Date
}

/// 今日のセッションで出す単語。
struct SessionPlan: Equatable, Sendable {
    /// 新規学習のミニバッチ 1 つあたりの語数（提示 → 直後クイズ の単位）
    static let newBatchSize = 5

    var reviewWordIds: [String] = []
    var newWordIds: [String] = []
    /// 上限で今日は繰り越した復習の数（ホームでの案内に使う）
    var deferredReviewCount: Int = 0

    var isEmpty: Bool { reviewWordIds.isEmpty && newWordIds.isEmpty }
    var totalCount: Int { reviewWordIds.count + newWordIds.count }

    /// 新規学習を 5 語ずつのミニバッチに割る
    var newBatches: [[String]] {
        stride(from: 0, to: newWordIds.count, by: Self.newBatchSize).map {
            Array(newWordIds[$0..<min($0 + Self.newBatchSize, newWordIds.count)])
        }
    }
}

/// 「今日は何を出すか」を決める。
///
/// 挫折させないための調整弁（復習の 1 日上限・新規語の自動抑制）もここに閉じ込める。
enum SessionBuilder {
    struct Input {
        var now: Date
        var progress: [ProgressSnapshot]
        var newWordPool: [WordEntry]
        var newWordsPerDay: Int
        var reviewLimitPerDay: Int
        /// 今日すでに終えた復習の数（同じ日に何度もセッションを開いても上限を守るため）
        var reviewsDoneToday: Int = 0
        /// 今日すでに学習した新規語の数
        var newWordsDoneToday: Int = 0
    }

    static func build(_ input: Input) -> SessionPlan {
        let today = DateUtil.startOfDay(input.now)

        // 期限が来た順（古い超過から）に並べる。同着は安定させるため ID 順
        let due = input.progress
            .filter { DateUtil.startOfDay($0.dueAt) <= today }
            .sorted {
                $0.dueAt == $1.dueAt ? $0.wordId < $1.wordId : $0.dueAt < $1.dueAt
            }

        let reviewSlots = max(0, input.reviewLimitPerDay - input.reviewsDoneToday)
        let reviews = due.prefix(reviewSlots).map(\.wordId)

        var plan = SessionPlan(
            reviewWordIds: Array(reviews),
            deferredReviewCount: due.count - reviews.count
        )

        // 復習が上限を超えている日は新規語を出さない（溜まった復習を先に片付ける）
        guard due.count <= input.reviewLimitPerDay else { return plan }

        let learned = Set(input.progress.map(\.wordId))
        let newSlots = max(0, input.newWordsPerDay - input.newWordsDoneToday)
        plan.newWordIds = input.newWordPool
            .lazy
            .filter { !learned.contains($0.id) }
            .prefix(newSlots)
            .map(\.id)
        return plan
    }
}
