import SwiftUI

/// 初回のみ表示する学習レベルの選択。
///
/// 設定はいつでも変えられるので、ここでは「とりあえず選んで始められる」ことを優先する。
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selected: CefrLevel = .a1

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            header
            Spacer(minLength: 24)
            levelPicker
            Spacer(minLength: 24)
            startButton
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

    private var startButton: some View {
        Button {
            settings.level = selected
            settings.hasOnboarded = true
        } label: {
            Text("はじめる")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings(defaults: UserDefaults(suiteName: "preview")!))
}
