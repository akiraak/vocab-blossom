import SwiftData
import SwiftUI

/// 初回のみ表示する。使い方を短く伝え、最初のグループを作ってホームへ進む。
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
            VStack(spacing: 28) {
                header
                steps
                createGroup
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .gardenBackground()
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                PlantView(stage: .sprout, size: 40)
                PlantView(stage: .bud, size: 52)
                PlantView(stage: .blossom, size: 64)
            }
            Text("vocab-blossom")
                .font(.largeTitle.weight(.bold))
            Text("覚えた単語が花になって庭が育つ、\n英語のことばを増やすアプリ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(
                systemImage: "folder.badge.plus",
                title: "グループを作る",
                detail: "小テストの範囲や教科書の単元など、覚えたい単語・フレーズをまとめます。"
            )
            step(
                systemImage: "graduationcap.fill",
                title: "グループで学習する",
                detail: "「学習する」・ドリル・穴埋め・読み上げで、くり返し覚えます。"
            )
            step(
                systemImage: "leaf.fill",
                title: "庭が育つ",
                detail: "覚えた単語が花になります。復習はホームの「今日の復習」でまとめてできます。"
            )
        }
        .cardStyle()
    }

    private func step(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var createGroup: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("最初のグループの名前")
                    .font(.subheadline.weight(.semibold))
                TextField("例: 小テスト Unit 3", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .submitLabel(.done)
            }

            Button {
                GroupEditor(context: context).createGroup(name: groupName)
                finish()
            } label: {
                Text("最初のグループを作る")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Button("あとで作る") { finish() }
                .font(.subheadline)

            Text("グループはホームの ＋ からいつでも作れます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
