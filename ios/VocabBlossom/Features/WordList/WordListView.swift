import SwiftData
import SwiftUI

/// 単語帳。デッキ別の一覧・検索・成長状態を見る。
struct WordListView: View {
    @Query private var progresses: [WordProgress]

    @State private var query = ""
    @State private var selectedDeckId: String?

    @Environment(\.wordStore) private var store

    /// 自作語のチップの ID（同梱デッキの ID と衝突しない値）
    private static let customDeckId = "custom"

    private var progressByWordId: [String: WordProgress] {
        Dictionary(progresses.map { ($0.wordId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var words: [WordEntry] {
        let base: [WordEntry]
        switch selectedDeckId {
        case nil: base = store.allWords
        case Self.customDeckId: base = store.customWords
        case let id?: base = store.decks.first { $0.id == id }?.words ?? store.allWords
        }
        return WordStore.filter(base, query: query)
    }

    var body: some View {
        NavigationStack {
            let progressByWordId = progressByWordId
            let words = words
            VStack(spacing: 0) {
                deckChips
                if words.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        Section {
                            ForEach(words) { word in
                                NavigationLink {
                                    WordDetailView(word: word)
                                } label: {
                                    WordRow(
                                        word: word,
                                        progress: progressByWordId[word.id]
                                    )
                                }
                            }
                        } header: {
                            Text("\(words.count) 語")
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("単語帳")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "単語・意味・例文を検索")
            .onChange(of: store.customWords.isEmpty) { _, isEmpty in
                // 自作語を全部消したら「マイ単語」チップも消えるので選択を戻す
                if isEmpty, selectedDeckId == Self.customDeckId { selectedDeckId = nil }
            }
        }
    }

    private var deckChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: "すべて", deckId: nil)
                ForEach(store.decks) { deck in
                    chip(title: deck.name, deckId: deck.id)
                }
                if !store.customWords.isEmpty {
                    chip(title: "マイ単語", deckId: Self.customDeckId)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, deckId: String?) -> some View {
        let isSelected = selectedDeckId == deckId
        return Button {
            selectedDeckId = deckId
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Theme.accent : Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 一覧の 1 行。成長状態と次回復習日をひと目で分かるようにする。
struct WordRow: View {
    let word: WordEntry
    let progress: WordProgress?

    private var stage: Int { progress?.stage ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            PlantView(stage: GrowthStage(stage: stage), size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.body.weight(.medium))
                Text(word.meaningSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let progress {
                Text(DateUtil.dueLabel(dueAt: progress.dueAt, now: .now))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(word.word)、\(word.meaningSummary)、\(GrowthStage(stage: stage).label)"
        )
    }
}
