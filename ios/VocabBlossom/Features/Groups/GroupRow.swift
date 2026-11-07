import SwiftUI

/// ホームのグループのカード。育ち具合で色面の濃さと右下の植物が変わる（種 → 芽 → つぼみ → 花）。
///
/// 名前・語数と達成度・今日の復習の数を左上に、植物の線画を右下に大きく置く
struct GroupCard: View {
    let group: WordGroup
    let summary: GroupStudy.Summary
    let activity: GroupStudy.Activity

    private var growth: GrowthStage { GroupStudy.growth(summary: summary, activity: activity) }

    private var detail: String {
        if summary.total == 0 { return "単語がありません" }
        if growth == .seed { return "\(summary.total) 語・まだ種のまま" }
        if let percent = GroupActivityText.percent(activity) {
            return "\(summary.total) 語・達成 \(percent)%"
        }
        return "\(summary.total) 語・学習済み \(summary.learned) 語"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(detail)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.tintText)
            if summary.due > 0 {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text("復習 \(summary.due)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            PlantIllustration(stage: growth, height: 108)
                .padding(.trailing, 6)
        }
        .background(growth.tint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(growth.label)
    }
}

/// 回答数・達成度の文言。一覧と詳細で同じ書き方にする
enum GroupActivityText {
    /// 例:「回答 42 回・達成 67%」
    static func line(_ activity: GroupStudy.Activity) -> String {
        var text = "回答 \(activity.answerCount) 回"
        if let percent = percent(activity) { text += "・達成 \(percent)%" }
        return text
    }

    /// 切り捨てる（1 語でも残っていれば 100% にしない）
    static func percent(_ activity: GroupStudy.Activity) -> Int? {
        activity.achievement.map { Int(($0 * 100).rounded(.down)) }
    }
}
