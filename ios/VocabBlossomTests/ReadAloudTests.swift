import Foundation
import Testing

@testable import VocabBlossom

/// 声を出さずに、頼まれた文の並びを覚えておく偽物。テストから「読み終えた」「割り込まれた」を起こす
final class FakeReadAloudSpeaker: ReadAloudSpeaking {
    var hasJapaneseVoice = true
    var onInterruption: (() -> Void)?

    private(set) var spoken: [[ReadAloudLine]] = []
    /// `prepare` で渡された語（単語の文）の並び
    private(set) var prepared: [[String]] = []
    private(set) var stopCount = 0
    private(set) var finishCount = 0
    private var onLineStart: ((Int) -> Void)?
    private var onFinish: (() -> Void)?

    /// 最後に頼まれた語（単語の文）
    var lastWord: String? { spoken.last?.first?.text }

    func speak(
        _ lines: [ReadAloudLine],
        onLineStart: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
        spoken.append(lines)
        self.onLineStart = onLineStart
        self.onFinish = onFinish
    }

    func prepare(_ upcoming: [[ReadAloudLine]]) {
        prepared.append(upcoming.compactMap { $0.first?.text })
    }

    func stop() {
        stopCount += 1
    }

    func finish() {
        finishCount += 1
    }

    func startLine(_ index: Int) {
        onLineStart?(index)
    }

    func finishItem() {
        onFinish?()
    }

    func interrupt() {
        onInterruption?()
    }
}

private func entry(
    _ word: String,
    meaning: String = "意味",
    example: String = "",
    exampleJa: String = "",
    extraSenses: [WordSense] = []
) -> WordEntry {
    WordEntry(
        id: "test-\(word)", word: word, pos: .noun, level: nil,
        meaning: meaning, example: example, exampleJa: exampleJa, extraSenses: extraSenses
    )
}

@Suite("読み上げる項目")
struct ReadAloudScriptTests {
    @Test("1 語は 単語 → 意味 → 例文 → 例文の和訳")
    func basicOrder() {
        let items = ReadAloudScript.items(
            for: [entry("apple", meaning: "りんご", example: "I like apples.", exampleJa: "私はりんごが好き。")],
            includesJapanese: true
        )
        #expect(items.count == 1)
        #expect(items[0].lines.map(\.kind) == [.word, .meaning, .example, .exampleJa])
        #expect(items[0].lines.map(\.text) == ["apple", "りんご", "I like apples.", "私はりんごが好き。"])
    }

    @Test("意味が複数ある語は、単語を 1 回読んだあと意味ごとに 意味 → 例文 → 和訳")
    func multipleSenses() {
        let word = entry(
            "cram", meaning: "詰め込み勉強をする", example: "I crammed.", exampleJa: "詰め込んだ。",
            extraSenses: [WordSense(pos: .verb, meaning: "詰め込み勉強", example: "A cram.", exampleJa: "詰め込み。")]
        )
        let lines = ReadAloudScript.items(for: [word], includesJapanese: true)[0].lines
        #expect(lines.map(\.kind) == [.word, .meaning, .example, .exampleJa, .meaning, .example, .exampleJa])
        #expect(lines.map(\.senseIndex) == [0, 0, 0, 0, 1, 1, 1])
    }

    @Test("例文・和訳が空なら飛ばす")
    func skipsEmpty() {
        let word = entry("homeroom", meaning: "ホームルーム", example: "  ")
        let lines = ReadAloudScript.items(for: [word], includesJapanese: true)[0].lines
        #expect(lines.map(\.kind) == [.word, .meaning])
    }

    @Test("日本語の声が無ければ日本語の文は入れない")
    func withoutJapanese() {
        let lines = ReadAloudScript.items(
            for: [entry("apple", meaning: "りんご", example: "I like apples.", exampleJa: "私はりんごが好き。")],
            includesJapanese: false
        )[0].lines
        #expect(lines.map(\.kind) == [.word, .example])
    }

    @Test("グループの並びのまま")
    func keepsOrder() {
        let items = ReadAloudScript.items(for: [entry("b"), entry("a"), entry("c")], includesJapanese: true)
        #expect(items.map(\.word.word) == ["b", "a", "c"])
    }

    @Test("日本語は読ませたくない記号を整えて読む（画面の文はそのまま）")
    func spokenJapanese() {
        #expect(ReadAloudScript.spokenJapanese("りんご／リンゴの木") == "りんご、リンゴの木")
        #expect(ReadAloudScript.spokenJapanese("〜の世話をする") == "の世話をする")
        #expect(ReadAloudScript.spokenJapanese("〜の中に［で］") == "の中に")
        #expect(ReadAloudScript.spokenJapanese("（風が）吹く") == "（風が）吹く")

        let word = entry("take care of", meaning: "〜の世話をする")
        let line = ReadAloudScript.items(for: [word], includesJapanese: true)[0].lines[1]
        #expect(line.text == "〜の世話をする")
        #expect(line.spokenText == "の世話をする")
    }
}

@Suite("穴埋めの回答後に読む文")
struct FillBlankAnswerLinesTests {
    private let word = entry(
        "commute", meaning: "通勤する", example: "I commute by bus.", exampleJa: "バスで通勤する。",
        extraSenses: [
            WordSense(pos: .noun, meaning: "通勤", example: "My commute is long.", exampleJa: "通勤が長い。"),
        ]
    )

    private func quiz(sense: WordSense? = nil, passage: Passage? = nil) -> Quiz {
        Quiz(
            word: word, sense: sense, type: .fillBlank, choices: [word],
            blankedExample: "＿＿＿＿", passage: passage
        )
    }

    @Test("文章で出したときは 単語 → 文章を 1 文ずつ")
    func passage() {
        let text = "Tom lives far from his office.  He has to commute for an hour! Is that hard? Yes."
        let passage = Passage(text: text, ja: "和訳。")
        let lines = ReadAloudScript.fillBlankAnswerLines(for: quiz(passage: passage))
        #expect(lines.map(\.kind) == [.word, .example, .example, .example, .example])
        #expect(lines.map(\.text) == [
            "commute", "Tom lives far from his office.", "He has to commute for an hour!",
            "Is that hard?", "Yes.",
        ])
    }

    @Test("例文で出したときは 単語 → 出題した意味の例文")
    func example() {
        let lines = ReadAloudScript.fillBlankAnswerLines(for: quiz(sense: word.senses[1]))
        #expect(lines.map(\.text) == ["commute", "My commute is long."])
        #expect(lines.map(\.senseIndex) == [0, 1])
    }

    @Test("例文が空なら単語だけ")
    func emptyExample() {
        let bare = entry("homeroom", meaning: "ホームルーム")
        let quiz = Quiz(word: bare, type: .fillBlank, choices: [bare], blankedExample: nil)
        #expect(ReadAloudScript.fillBlankAnswerLines(for: quiz).map(\.text) == ["homeroom"])
    }

    @Test("文の分け方: 文末記号のあとの空白で切り、引用符は前の文に付ける")
    func sentences() {
        #expect(ReadAloudScript.sentences(in: "She said \"Hi.\" Then she left.\nOK") == [
            "She said \"Hi.\"", "Then she left.", "OK",
        ])
        #expect(ReadAloudScript.sentences(in: "  ") == [])
        #expect(ReadAloudScript.sentences(in: "It costs 3.5 dollars.") == ["It costs 3.5 dollars."])
    }
}

@Suite("読み上げの再生")
struct ReadAloudPlayerTests {
    private func makePlayer(_ words: [String] = ["a", "b", "c"]) -> (ReadAloudPlayer, FakeReadAloudSpeaker) {
        let speaker = FakeReadAloudSpeaker()
        return (ReadAloudPlayer(words: words.map { entry($0) }, speaker: speaker), speaker)
    }

    @Test("順に最後まで読んで止まる")
    func playsToEnd() {
        let (player, speaker) = makePlayer()
        player.play()
        #expect(player.isPlaying)
        #expect(speaker.lastWord == "a")

        speaker.finishItem()
        #expect(player.index == 1)
        #expect(speaker.lastWord == "b")
        speaker.finishItem()
        #expect(speaker.lastWord == "c")
        speaker.finishItem()

        #expect(!player.isPlaying)
        #expect(player.isFinished)
        #expect(speaker.spoken.count == 3)
        #expect(speaker.finishCount == 1, "読み終えたらほかのアプリの音を戻す")
    }

    @Test("読み終えたあとに再生すると頭から読む")
    func replayAfterFinished() {
        let (player, speaker) = makePlayer(["a", "b"])
        player.play()
        speaker.finishItem()
        speaker.finishItem()
        #expect(player.isFinished)

        player.play()
        #expect(player.index == 0)
        #expect(!player.isFinished)
        #expect(speaker.lastWord == "a")
    }

    @Test("ループなら最後のあと頭に戻り、周回が増える")
    func loops() {
        let (player, speaker) = makePlayer(["a", "b"])
        player.isLooping = true
        player.play()
        speaker.finishItem()
        speaker.finishItem()

        #expect(player.isPlaying)
        #expect(player.index == 0)
        #expect(player.lap == 2)
        #expect(speaker.lastWord == "a")
    }

    @Test("一時停止して再開すると、同じ語の頭から読む")
    func pauseAndResume() {
        let (player, speaker) = makePlayer()
        player.play()
        speaker.finishItem()
        speaker.startLine(1)
        #expect(player.lineIndex == 1)

        player.pause()
        #expect(!player.isPlaying)
        #expect(player.lineIndex == nil)
        #expect(speaker.stopCount == 1)

        player.play()
        #expect(player.index == 1)
        #expect(speaker.lastWord == "b")
    }

    @Test("止めたあとに前の語の「読み終えた」が届いても進まない")
    func ignoresStaleFinish() {
        let (player, speaker) = makePlayer()
        player.play()
        player.pause()
        speaker.finishItem()
        #expect(player.index == 0)
        #expect(!player.isPlaying)
    }

    @Test("再生中に前後へ動くと、そこから読む")
    func nextAndPreviousWhilePlaying() {
        let (player, speaker) = makePlayer()
        player.play()
        player.next()
        #expect(player.index == 1)
        #expect(speaker.lastWord == "b")
        player.next()
        #expect(speaker.lastWord == "c")
        #expect(!player.canGoNext)

        player.previous()
        #expect(player.index == 1)
        #expect(speaker.lastWord == "b")
        #expect(player.isPlaying)
    }

    @Test("止まっているときに前後へ動くと、位置だけ動く")
    func nextWhilePaused() {
        let (player, speaker) = makePlayer()
        player.next()
        player.next()
        #expect(player.index == 2)
        #expect(speaker.spoken.isEmpty)
        player.next()
        #expect(player.index == 2, "最後の語では動かない")
        player.previous()
        player.previous()
        player.previous()
        #expect(player.index == 0, "先頭では動かない")
    }

    @Test("ループ中は最後の語から次へ進むと頭に戻る")
    func nextWrapsWhenLooping() {
        let (player, _) = makePlayer(["a", "b"])
        player.isLooping = true
        player.next()
        player.next()
        #expect(player.index == 0)
        #expect(player.lap == 2)
    }

    @Test("途中の語から読める")
    func startAtIndex() {
        let (player, speaker) = makePlayer()
        player.start(at: 2)
        #expect(player.isPlaying)
        #expect(speaker.lastWord == "c")

        player.start(at: 0)
        #expect(speaker.lastWord == "a")
        #expect(speaker.spoken.count == 2)
    }

    @Test("割り込みで一時停止になる")
    func interruptionPauses() {
        let (player, speaker) = makePlayer()
        player.play()
        speaker.interrupt()
        #expect(!player.isPlaying)
        #expect(speaker.stopCount == 1)
    }

    @Test("閉じると止めて、ほかのアプリの音を戻す")
    func closeFinishes() {
        let (player, speaker) = makePlayer()
        player.play()
        player.close()
        #expect(!player.isPlaying)
        #expect(speaker.finishCount == 1)
        speaker.finishItem()
        #expect(player.index == 0)
    }

    @Test("単語が無ければ再生しない")
    func emptyGroup() {
        let (player, speaker) = makePlayer([])
        player.play()
        #expect(!player.isPlaying)
        #expect(speaker.spoken.isEmpty)
        #expect(!player.canGoNext)
    }

    @Test("読み始めるたび、今の語と次の 3 語を声に先に用意させる（ループなら頭に戻って数える）")
    func preparesUpcoming() {
        let (player, speaker) = makePlayer(["a", "b", "c", "d", "e"])
        player.play()
        #expect(speaker.prepared.last == ["a", "b", "c", "d"])

        player.start(at: 3)
        #expect(speaker.prepared.last == ["d", "e"])

        player.isLooping = true
        player.next()
        #expect(speaker.prepared.last == ["e", "a", "b", "c"])
    }

    @Test("語が少なければ、ループでも同じ語を二度は用意させない")
    func preparesFewWords() {
        let (player, speaker) = makePlayer(["a", "b"])
        player.isLooping = true
        player.play()
        #expect(speaker.prepared.last == ["a", "b"])
    }
}
