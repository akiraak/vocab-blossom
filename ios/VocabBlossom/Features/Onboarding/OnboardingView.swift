import SwiftUI

/// 初回のみ表示する。レベルを選び、続けて知っている単語をまとめて片付ける。
///
/// 設定はいつでも変えられるので、ここでは「とりあえず選んで始められる」ことを優先する。
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings

    @State private var selected: CefrLevel = .a1
    @State private var showsKnownWords = false

    var body: some View {
        NavigationStack {
            levelStep
                .navigationDestination(isPresented: $showsKnownWords) {
                    KnownWordsPickerView(onFinish: finish)
                }
        }
    }

    private var levelStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            header
            Spacer(minLength: 24)
            levelPicker
            Spacer(minLength: 24)
            actions
        }
        .padding(24)
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
    }

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("学習レベルを選んでください")
                .font(.headline)
            Text("あとから設定でいつでも変えられます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(CefrLevel.allCases) { level in
                Button {
                    selected = level
                } label: {
                    levelRow(level)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func levelRow(_ level: CefrLevel) -> some View {
        let isSelected = selected == level
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.label)
                    .font(.headline)
                Text(level.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(WordStore.shared.words(level: level).count) 語")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .stroke(isSelected ? Theme.accent : .clear, lineWidth: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                settings.level = selected
                showsKnownWords = true
            } label: {
                Text("次へ")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            Button("すぐに始める") {
                settings.level = selected
                finish()
            }
            .font(.subheadline)

            Text("次の画面で、すでに知っている単語をまとめてとばせます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func finish() {
        settings.hasOnboarded = true
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings(defaults: UserDefaults(suiteName: "preview")!))
}
