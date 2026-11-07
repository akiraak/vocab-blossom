import SwiftUI
import Testing

@testable import VocabBlossom

@Suite("SVG のパスの読み込み（植物の線画）")
struct SVGPathTests {
    @Test("M と相対の v で縦の線になる")
    func moveAndRelativeVertical() {
        let path = SVGPath.path("M12 25v-7")
        #expect(path.currentPoint == CGPoint(x: 12, y: 18))
        #expect(path.boundingRect == CGRect(x: 12, y: 18, width: 0, height: 7))
    }

    @Test("絶対の H・V・L")
    func absoluteLines() {
        let path = SVGPath.path("M0 0H10V5L2 8")
        #expect(path.currentPoint == CGPoint(x: 2, y: 8))
        #expect(path.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 8))
    }

    @Test("区切りの無い数字（「5.2-4.8」「2.8.3」）も分けて読む")
    func numbersWithoutSeparators() {
        #expect(isClose(SVGPath.path("M0 0l2.8.3").currentPoint, CGPoint(x: 2.8, y: 0.3)))
        #expect(isClose(SVGPath.path("M10 10l-5.2-4.8").currentPoint, CGPoint(x: 4.8, y: 5.2)))
    }

    /// Path は座標を単精度で持つので、小数はおおよそで比べる
    private func isClose(_ point: CGPoint?, _ expected: CGPoint) -> Bool {
        guard let point else { return false }
        return abs(point.x - expected.x) < 0.0001 && abs(point.y - expected.y) < 0.0001
    }

    @Test("相対の c は区間の始まりから数え、z で始点に戻る")
    func relativeCurveAndClose() {
        // 葉の形: (12,19) から左上へふくらんで戻る
        let path = SVGPath.path("M12 19c-3 0-5-1.8-5.2-4.8 3 .1 5 2 5.2 4.8z")
        #expect(path.currentPoint == CGPoint(x: 12, y: 19))
        let box = path.boundingRect
        #expect(abs(box.minX - 6.8) < 0.01)
        #expect(abs(box.minY - 14.2) < 0.01)
        #expect(abs(box.maxX - 12) < 0.01)
        #expect(abs(box.maxY - 19) < 0.01)
    }

    @Test("M のあとに続く座標は線として読む")
    func implicitLineAfterMove() {
        let path = SVGPath.path("M0 0 10 0 10 10")
        #expect(path.currentPoint == CGPoint(x: 10, y: 10))
        #expect(path.boundingRect == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("知らない命令（A など）があっても止まらずに読み終える")
    func skipsUnknownCommands() {
        let path = SVGPath.path("M1 1A5 5 0 0 1 9 9L3 3")
        #expect(path.currentPoint == CGPoint(x: 3, y: 3))
    }
}
