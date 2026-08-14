import SwiftUI

// Phase 4 で実装する。ここではホームからの導線だけ通しておく。
struct SessionView: View {
    let plan: SessionPlan

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("学習セッション")
                .font(.title2.weight(.bold))
            Text("復習 \(plan.reviewWordIds.count) 語 / 新規 \(plan.newWordIds.count) 語")
                .foregroundStyle(.secondary)
            Button("閉じる") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .gardenBackground()
    }
}
