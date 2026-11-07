import SwiftData
import SwiftUI

/// 初回のみ表示する。使い方を短く伝え、最初のグループを作ってホームへ進む（デザイン B4）。
///
/// 学習はグループが中心なので、ここでグループを 1 つ作っておけば、ホームからすぐ単語を入れ始められる。
/// 作らずに進むこともできる（ホームの ＋ でいつでも作れる）
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var groupName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                steps
                createGroup
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .gardenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandWordmark()
            Text("覚えたい単語を、\n自分の庭で育てる。")
                .font(.system(size: 28, weight: .light))
                .lineSpacing(6)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// 使い方の 3 つの手順。種 → つぼみ → 花と、進むほど色面が濃くなる
    private var steps: some View {
        VStack(spacing: 8) {
            step(
                number: "01", stage: .seed,
                title: "グループを作る",
                detail: "小テストの範囲や教科書の単元など、覚えたい単語をまとめます。"
            )
            step(
                number: "02", stage: .bud,
                title: "グループで学習する",
                detail: "学習する・ドリル・穴埋め・読み上げで、くり返し覚えます。"
            )
            step(
                number: "03", stage: .blossom,
                title: "庭が育つ",
                detail: "覚えた単語が花になります。復習はホームでまとめてできます。"
            )
        }
    }

    private func step(number: String, stage: GrowthStage, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number)
                .font(.caption2)
                .tracking(2.4)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.tintText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 92)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            PlantIllustration(stage: stage, height: 64)
                .padding(.trailing, 14)
        }
        .background(stage == .seed ? Theme.tintSeed : stage.tint)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var createGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最初のグループの名前")
                .sectionLabel()
            TextField("例: 小テスト Unit 3", text: $groupName)
                .focused($isNameFocused)
                .submitLabel(.done)
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .accessibilityLabel("最初のグループの名前")

            Button("最初のグループを作る") {
                GroupEditor(context: context).createGroup(name: groupName)
                finish()
            }
            .buttonStyle(.capsule)

            Button("あとで作る") { finish() }
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44)

            Text("グループはホームの ＋ からいつでも作れます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func finish() {
        isNameFocused = false
        settings.hasOnboarded = true
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings(defaults: UserDefaults(suiteName: "preview")!))
        .modelContainer(for: [WordGroup.self], inMemory: true)
}
