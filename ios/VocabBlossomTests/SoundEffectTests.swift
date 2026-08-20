import AVFoundation
import Foundation
import Testing

@testable import VocabBlossom

@Suite("正解・不正解の効果音")
struct SoundEffectTests {
    @Test("波形は想定の長さで、クリップも小さすぎもしない", arguments: SoundEffect.allCases)
    func samplesAreBoundedAndSized(effect: SoundEffect) {
        let samples = effect.samples()
        let expectedDuration = effect.segments.reduce(0) { $0 + $1.duration }

        #expect(
            abs(Double(samples.count) / Double(SoundEffect.sampleRate) - expectedDuration) < 0.01
        )
        #expect(samples.allSatisfy { abs($0) <= 1.0 }, "クリップしている")
        #expect((samples.map(abs).max() ?? 0) > 0.2, "小さすぎて聞こえない")
    }

    @Test("鳴り始めと終わりは無音に近い（プチッというノイズを出さない）", arguments: SoundEffect.allCases)
    func edgesAreNearSilent(effect: SoundEffect) throws {
        let samples = effect.samples()
        #expect(abs(try #require(samples.first)) < 0.02)
        #expect(abs(try #require(samples.last)) < 0.02)
    }

    @Test("正解と不正解は違う音")
    func soundsAreDistinct() {
        #expect(SoundEffect.correct.samples() != SoundEffect.incorrect.samples())
    }

    @Test("合成した WAV は再生器で読み込める", arguments: SoundEffect.allCases)
    func wavIsDecodable(effect: SoundEffect) throws {
        let player = try AVAudioPlayer(data: effect.wavData())
        let expectedDuration = effect.segments.reduce(0) { $0 + $1.duration }
        #expect(abs(player.duration - expectedDuration) < 0.05)
    }

    @Test("連続で鳴らしても問題ない")
    func playsBackToBack() {
        let service = SoundEffectService()
        service.play(.correct)
        service.play(.incorrect)
        service.play(.correct)
    }
}
