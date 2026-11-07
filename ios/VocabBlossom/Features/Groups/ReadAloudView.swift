import SwiftUI

/// グループの単語を順に読み上げる画面（フルスクリーン）。開くとすぐ頭から読み始め、閉じたら止める。
///
/// 今読んでいる語を大きく出し、読んでいる文（単語・品詞と意味・例文・和訳）を強調する。一覧の語を押すとそこから読む。
/// 画面を消しても読み続け、ロック画面・コントロールセンターから操作できる（`UIBackgroundModes: audio`）
struct ReadAloudView: View {
    let groupName: String

    @State private var player: ReadAloudPlayer
    /// ロック画面・コントロールセンターの表示と操作
    @State private var nowPlaying = ReadAloudNowPlaying()
    @Environment(\.dismiss) private var dismiss

    init(
        groupName: String,
        words: [WordEntry],
        speaker: any ReadAloudSpeaking = GeminiReadAloudSpeaker.shared
    ) {
        self.groupName = groupName
        _player = State(initialValue: ReadAloudPlayer(words: words, speaker: speaker))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    currentCard
                    progressRow
                    controls
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                wordList
            }
            .gardenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("読み上げ")
                            .font(.headline)
                        Text(groupName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("読み上げを閉じる")
                }
            }
        }
        .task {
            nowPlaying.start(player: player, groupName: groupName)
            player.play()
        }
        .onDisappear {
            player.close()
            nowPlaying.stop()
        }
    }

    // MARK: - 今の語

    /// 今読んでいる文（強調する文）
    private var currentLine: ReadAloudLine? {
        guard let item = player.currentItem, let lineIndex = player.lineIndex,
              item.lines.indices.contains(lineIndex) else { return nil }
        return item.lines[lineIndex]
    }

    private func isReading(_ kind: ReadAloudLine.Kind, sense: Int = 0) -> Bool {
        guard let currentLine else { return false }
        return currentLine.kind == kind && currentLine.senseIndex == sense
    }

    @ViewBuilder
    private var currentCard: some View {
        if let word = player.currentItem?.word {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(word.word)
                        .font(.system(size: 34, weight: .light))
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .readingHighlight(isReading(.word))

                    ForEach(Array(word.senses.enumerated()), id: \.offset) { index, sense in
                        if index > 0 { Divider() }
                        senseBlock(sense, index: index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .padding(6)
            .cardStyle(Theme.tintBlossom)
            .accessibilityElement(children: .combine)
        } else {
            ContentUnavailableView("単語がありません", systemImage: "speaker.slash")
        }
    }

    /// 意味 1 つ分。品詞はいつも出し、意味の文（「品詞。意味」と読む）を読んでいる間は品詞ごと強調する
    private func senseBlock(_ sense: WordSense, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(sense.pos.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    // 意味を読んでいる間は白く浮くので、ラベルは色面の色にして見分けられるようにする
                    .background(
                        isReading(.meaning, sense: index) ? Theme.tintBlossom : Theme.background,
                        in: Capsule()
                    )
                Text(sense.meaning)
                    .font(.title3.weight(.medium))
            }
            .readingHighlight(isReading(.meaning, sense: index))
            if !sense.example.isEmpty {
                Text(sense.example)
                    .font(.body)
                    .readingHighlight(isReading(.example, sense: index))
            }
            if !sense.exampleJa.isEmpty {
                Text(sense.exampleJa)
                    .font(.callout)
                    .foregroundStyle(Theme.tintText)
                    .readingHighlight(isReading(.exampleJa, sense: index))
            }
        }
    }

    private var progressRow: some View {
        HStack {
            Text(player.items.isEmpty ? "0 / 0 語" : "\(player.index + 1) / \(player.items.count) 語")
                .monospacedDigit()
            Spacer()
            if player.isLooping {
                Label("\(player.lap) 周目", systemImage: "repeat")
                    .monospacedDigit()
            } else if player.isFinished {
                Text("最後まで読みました")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - 操作

    private var controls: some View {
        HStack {
            Button {
                player.isLooping.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(player.isLooping ? Theme.onAccent : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(player.isLooping ? Theme.accent : Theme.tintBlossom, in: Circle())
            }
            .accessibilityLabel("ループ再生")
            .accessibilityValue(player.isLooping ? "オン" : "オフ")

            Spacer()

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .frame(width: 52, height: 52)
            }
            .disabled(!player.canGoPrevious)
            .accessibilityLabel("前の単語")

            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 72, height: 72)
                    .background(Theme.accent, in: Circle())
            }
            .disabled(player.items.isEmpty)
            .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .frame(width: 52, height: 52)
            }
            .disabled(!player.canGoNext)
            .accessibilityLabel("次の単語")

            Spacer()

            // ループのボタンと左右の釣り合いを取る
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: - 一覧

    private var wordList: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(Array(player.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            player.start(at: index)
                        } label: {
                            row(item, isCurrent: index == player.index)
                                .contentShape(Rectangle())
                        }
                        // 行の文字をボタンの色（アクセント）にしない
                        .buttonStyle(.plain)
                        .id(index)
                    }
                } header: {
                    Text("押した単語から読みます")
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: player.index) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func row(_ item: ReadAloudItem, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: player.isPlaying && isCurrent ? "speaker.wave.2.fill" : "speaker.fill")
                .foregroundStyle(Theme.accent)
                .opacity(isCurrent ? 1 : 0)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.word.word)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                Text(item.word.meaningSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private extension View {
    /// 読んでいる文を白（ダークは地の色）で浮かせる（カードは薄いセージの色面）
    func readingHighlight(_ isReading: Bool) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.background.opacity(isReading ? 1 : 0))
            )
            .padding(.horizontal, -6)
            .padding(.vertical, -2)
            .animation(.easeInOut(duration: 0.2), value: isReading)
    }
}
