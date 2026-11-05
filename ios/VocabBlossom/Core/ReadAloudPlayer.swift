import Foundation
import Observation

/// 実際に声を出す部分。テストでは偽物に差し替える。
protocol ReadAloudSpeaking: AnyObject {
    /// 日本語の声が端末にあるか（無ければ日本語の文は読まない）
    var hasJapaneseVoice: Bool { get }

    /// 通話・ほかのアプリの再生などで音が止められたとき（イヤホンが抜けたときも）に呼ばれる
    var onInterruption: (() -> Void)? { get set }

    /// 文の並びを順に読む。文を読み始めるたびに `onLineStart`（何番目か）、全部読み終えたら `onFinish` を呼ぶ。
    /// 途中で `stop` / 次の `speak` をしたら、前の分の `onFinish` は呼ばない
    func speak(
        _ lines: [ReadAloudLine],
        onLineStart: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    )

    /// 読んでいる途中でも止める（音声セッションはそのまま）
    func stop()

    /// 読み上げを終える。止めたうえで、ほかのアプリの音を戻す
    func finish()
}

/// グループの単語を順に読み上げる。再生・一時停止・前後・ループを持つ。
///
/// 一時停止して再開すると、読んでいた語の頭から読み直す。学習の記録には残さない
@Observable
final class ReadAloudPlayer {
    private(set) var items: [ReadAloudItem]
    /// 今の語（読んでいる語、止まっているならそこから読む語）
    private(set) var index = 0
    /// 今の語の中で読んでいる文（`ReadAloudItem.lines` の位置）。止まっている間は nil
    private(set) var lineIndex: Int?
    private(set) var isPlaying = false
    /// 何周目か（ループで頭に戻るたびに増える）
    private(set) var lap = 1
    /// 最後まで読み終えて止まった（次に再生すると頭から読む）
    private(set) var isFinished = false
    /// 最後まで読んだら頭から繰り返す
    var isLooping = false

    @ObservationIgnored private let speaker: any ReadAloudSpeaking
    /// 前の `speak` の知らせを無視するための番号。読み始めるたび・止めるたびに進める
    @ObservationIgnored private var generation = 0

    init(words: [WordEntry], speaker: any ReadAloudSpeaking) {
        self.items = ReadAloudScript.items(for: words, includesJapanese: speaker.hasJapaneseVoice)
        self.speaker = speaker
    }

    var currentItem: ReadAloudItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var canGoNext: Bool { index + 1 < items.count || (isLooping && !items.isEmpty) }
    var canGoPrevious: Bool { index > 0 }

    func play() {
        guard !items.isEmpty, !isPlaying else { return }
        if isFinished {
            index = 0
            lap = 1
            isFinished = false
        }
        isPlaying = true
        // 割り込みの知らせは再生するときに受け取る（SwiftUI が画面を作り直すたびに init が走っても横取りされないように）
        speaker.onInterruption = { [weak self] in
            self?.pause()
        }
        speakCurrent()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        silence()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// 次の語へ。再生中ならそこから読み、止まっているなら位置だけ動かす。
    /// 最後の語では、ループなら頭へ、そうでなければ何もしない
    func next() {
        guard canGoNext else { return }
        if index + 1 < items.count {
            move(to: index + 1)
        } else {
            lap += 1
            move(to: 0)
        }
    }

    /// 前の語へ。先頭では何もしない
    func previous() {
        guard canGoPrevious else { return }
        move(to: index - 1)
    }

    /// 一覧で押した語から読む
    func start(at newIndex: Int) {
        guard items.indices.contains(newIndex) else { return }
        isFinished = false
        if isPlaying {
            move(to: newIndex)
        } else {
            index = newIndex
            play()
        }
    }

    /// 画面を閉じるとき。止めて、ほかのアプリの音を戻す
    func close() {
        isPlaying = false
        generation += 1
        lineIndex = nil
        speaker.finish()
    }

    // MARK: -

    private func move(to newIndex: Int) {
        index = newIndex
        isFinished = false
        if isPlaying {
            speakCurrent()
        } else {
            lineIndex = nil
        }
    }

    private func speakCurrent() {
        guard let item = currentItem else { return }
        generation += 1
        let current = generation
        lineIndex = nil
        speaker.speak(
            item.lines,
            onLineStart: { [weak self] line in
                guard let self, self.generation == current else { return }
                self.lineIndex = line
            },
            onFinish: { [weak self] in
                guard let self, self.generation == current else { return }
                self.advance()
            }
        )
    }

    /// 1 語読み終えたら次へ。最後まで読んだら、ループなら頭へ、そうでなければ止まる
    private func advance() {
        if index + 1 < items.count {
            index += 1
        } else if isLooping {
            index = 0
            lap += 1
        } else {
            isPlaying = false
            isFinished = true
            lineIndex = nil
            generation += 1
            // ほかのアプリの音を戻す（もう一度再生すれば有効にし直す）
            speaker.finish()
            return
        }
        speakCurrent()
    }

    private func silence() {
        generation += 1
        lineIndex = nil
        speaker.stop()
    }
}
