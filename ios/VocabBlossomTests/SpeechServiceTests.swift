import Foundation
import Testing

@testable import VocabBlossom

/// 読み上げの基本動作（開始・完走・停止後の再開）を確認する。
///
/// 注意: 報告された「提示直後に『もう知ってる』を押すと以後ずっと鳴らない」不具合は
/// **シミュレータでは再現しない**（修正前のコードでもこのテストは通る）。
/// 実機の TTS でしか起きないため、ここは回帰テストではなく異常検知の網として置いている。
/// 実機で再発したときは Console.app で `subsystem: com.akiraak.VocabBlossom` の
/// 「読み上げ開始 / 発話開始 / 発話終了」を見て、どこで止まっているかを切り分ける。
@Suite("読み上げ", .serialized)
struct SpeechServiceTests {
    let service = SpeechService.shared

    /// `condition` が満たされるまで待つ。満たされなければ false
    private func waitUntil(
        timeout: Duration = .seconds(8),
        _ condition: () -> Bool
    ) async -> Bool {
        let steps = Int(timeout.components.seconds * 20 + 20)
        for _ in 0..<steps {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test("読み上げは始まり、最後まで喋り終わる")
    func speaksAndFinishes() async {
        service.stop()
        service.speak(word: "apple")

        #expect(await waitUntil { service.isSpeaking }, "読み上げが始まらない")
        #expect(await waitUntil { !service.isSpeaking }, "読み上げが終わらない（詰まっている）")
    }

    @Test("発話が始まる前に素早く切り替えても詰まらない")
    func rapidReplacementDoesNotWedge() async {
        service.stop()
        // 提示 → 即「もう知ってる」→ 次の提示 …… を素早く繰り返す
        for _ in 0..<6 {
            service.speak(word: "apple", example: "I like apples.")
            try? await Task.sleep(for: .milliseconds(10))
        }
        service.speak(word: "book")

        #expect(await waitUntil { service.isSpeaking }, "切り替え後に読み上げが始まらない")
        #expect(await waitUntil { !service.isSpeaking }, "切り替え後に詰まっている")
    }

    @Test("停止したあとでも、もう一度読み上げられる")
    func speaksAgainAfterStop() async {
        service.speak(word: "apple", example: "I like apples.")
        try? await Task.sleep(for: .milliseconds(50))
        service.stop()
        #expect(!service.isSpeaking)

        service.speak(word: "book")
        #expect(await waitUntil { service.isSpeaking }, "停止後に読み上げが始まらない")
        #expect(await waitUntil { !service.isSpeaking }, "停止後の読み上げが詰まっている")
    }

    @Test("空文字は読み上げない")
    func ignoresEmptyText() async {
        service.stop()
        service.speak(word: "   ")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!service.isSpeaking)
    }
}
