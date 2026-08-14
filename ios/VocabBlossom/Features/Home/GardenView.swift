import SwiftUI

/// 覚えた単語を花として並べた「庭」。
struct GardenView: View {
    let stages: [GrowthStage]
    /// 庭に入りきらなかった分（「ほか N 語」として文字で伝える）
    var overflow: Int = 0

    private let columns = 10
    private let plantSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                sky
                if stages.isEmpty {
                    emptyMessage
                } else {
                    plants
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))

            if overflow > 0 {
                Text("ほか \(overflow) 語も育っています")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var sky: some View {
        LinearGradient(
            colors: [
                Color(red: 0.85, green: 0.93, blue: 1.0),
                Color(red: 0.95, green: 0.98, blue: 0.92),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.80, green: 0.89, blue: 0.71))
                .frame(height: 18)
        }
    }

    private var plants: some View {
        VStack(spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, stage in
                        PlantView(stage: stage, size: plantSize)
                            // 機械的な整列に見えないよう、わずかに高さをずらす
                            .offset(y: CGFloat(index % 3) - 1)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    private var rows: [[GrowthStage]] {
        stride(from: 0, to: stages.count, by: columns).map {
            Array(stages[$0..<min($0 + columns, stages.count)])
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 6) {
            Text("🌱")
                .font(.system(size: 36))
            Text("まだ種だけの庭です")
                .font(.subheadline.weight(.medium))
            Text("今日の学習を始めると花が育ちます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var accessibilityLabel: String {
        guard !stages.isEmpty else { return "庭。まだ花はありません" }
        let counts = Dictionary(grouping: stages, by: { $0 }).mapValues(\.count)
        let detail = GrowthStage.allCases
            .compactMap { stage in counts[stage].map { "\(stage.label) \($0) 語" } }
            .joined(separator: "、")
        return "庭。\(detail)"
    }
}

#Preview {
    GardenView(
        stages: (0..<38).map { GrowthStage(stage: $0 % 5 + 1) },
        overflow: 12
    )
    .padding()
}
