import SwiftData
import SwiftUI

/// 知っている単語をまとめて登録する画面。
///
/// 既知語を 1 日 10 語の枠の中で 1 つずつ「もう知ってる」していくと何十日もかかるので、
/// 未学習語をグリッドで並べてタップで一括登録できるようにする。
struct KnownWordsPickerView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var progresses: [WordProgress]

    @State private var pageIndex = 0
    @State private var selected: Set<String> = []
    @State private var registeredCount = 0

    /// 完了時に呼ばれる（オンボーディングから使うときに次へ進むため）
    var onFinish: (() -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    /// 画面を開いた時点の未学習語。登録するたびに減ると位置がずれるので固定して持つ
    @State private var candidates: [WordEntry] = []

    private var page: [WordEntry] { KnownWordsPicker.page(candidates, at: pageIndex) }
    private var pageCount: Int { KnownWordsPicker.pageCount(candidates) }
    private var isLastPage: Bool { pageIndex >= pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if page.isEmpty {
                emptyState
            } else {
                grid
            }
            footer
        }
        .gardenBackground()
        .navigationTitle("知っている単語")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("終わる") { finish() }
            }
        }
        .task {
            guard candidates.isEmpty else { return }
            candidates = KnownWordsPicker.candidates(
                store: .shared,
                level: settings.level,
                learnedWordIds: Set(progresses.map(\.wordId))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("すでに意味が分かる単語をタップしてください。")
                .font(.subheadline)
            Text("選んだ語は学習をとばして、3 ヶ月後の確認だけになります。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if pageCount > 1 {
                let remaining = candidates.count - pageIndex * KnownWordsPicker.pageSize
                Text("\(pageIndex + 1) / \(pageCount) ページ・残り \(remaining) 語")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(page) { word in
                    cell(word)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func cell(_ word: WordEntry) -> some View {
        let isSelected = selected.contains(word.id)
        return Button {
            if isSelected {
                selected.remove(word.id)
            } else {
                selected.insert(word.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(word.word)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(word.meaning)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.accent.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.word)、\(word.meaning)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "未学習の単語がありません",
            systemImage: "checkmark.seal",
            description: Text("このレベルの単語はすべて学習済みです。")
        )
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if registeredCount > 0 {
                Text("これまでに \(registeredCount) 語を登録しました")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                register()
            } label: {
                Text(nextButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(page.isEmpty)
        }
        .padding(16)
        .background(.bar)
    }

    private var nextButtonTitle: String {
        if isLastPage {
            return selected.isEmpty ? "終わる" : "\(selected.count) 語を登録して終わる"
        }
        return selected.isEmpty ? "次の \(KnownWordsPicker.pageSize) 語へ" : "\(selected.count) 語を登録して次へ"
    }

    private func register() {
        if !selected.isEmpty {
            LearningEngine(context: context).markKnown(wordIds: Array(selected))
            registeredCount += selected.count
            selected.removeAll()
        }
        if isLastPage {
            finish()
        } else {
            pageIndex += 1
        }
    }

    private func finish() {
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }
}
