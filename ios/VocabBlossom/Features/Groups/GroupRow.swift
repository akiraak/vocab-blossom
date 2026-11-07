import SwiftUI

/// 一覧の 1 行。語数と育ち具合、今日の復習があるか、問題をこなした回数と達成度を見せる。
struct GroupRow: View {
    let group: WordGroup
    let summary: GroupStudy.Summary
    let activity: GroupStudy.Activity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.body.weight(.medium))
                Text("\(summary.total) 語・学習済み \(summary.learned) 語")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // まだ答えていないグループは今までの表示のまま
                if activity.answerCount > 0 {
                    activityLine
                }
            }
            Spacer(minLength: 8)
            if summary.due > 0 {
                Text("復習 \(summary.due)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var activityLine: some View {
        HStack(spacing: 8) {
            Text(GroupActivityText.line(activity))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let achievement = activity.achievement {
                ProgressView(value: achievement)
                    .tint(Theme.accent)
                    .frame(maxWidth: 80)
                    .accessibilityHidden(true)
            }
        }
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
