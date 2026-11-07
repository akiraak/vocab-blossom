import SwiftUI

/// SVG の path の `d`（M・L・H・V・C・Z と、その小文字の相対の形）を SwiftUI の `Path` にする。
///
/// デザインの線画（植物・ロゴ）の座標をそのまま使うための最小限の読み込み。
/// 円・楕円は `Path(ellipseIn:)` で別に描く。知らない命令（A など）の文字は読まない（止まらずに読み終える）
enum SVGPath {
    private enum Token: Equatable {
        case command(Character)
        case number(CGFloat)
    }

    // 命令ごとの分岐をひとつの switch にまとめて読みやすくしているため、複雑さの警告は外す
    // swiftlint:disable:next cyclomatic_complexity
    static func path(_ d: String) -> Path {
        let tokens = tokenize(d)
        var path = Path()
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func nextIsNumber() -> Bool {
            guard index < tokens.count, case .number = tokens[index] else { return false }
            return true
        }
        func number() -> CGFloat {
            guard index < tokens.count, case .number(let value) = tokens[index] else { return 0 }
            index += 1
            return value
        }
        func point(from base: CGPoint, relative: Bool) -> CGPoint {
            let x = number()
            let y = number()
            return relative ? CGPoint(x: base.x + x, y: base.y + y) : CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if case .command(let next) = tokens[index] {
                command = next
                index += 1
            } else if !nextIsNumber() {
                index += 1
                continue
            }
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                current = point(from: current, relative: relative)
                start = current
                path.move(to: current)
                // M のあとに続く座標は L として読む（SVG の決まり）
                command = relative ? "l" : "L"
            case "L":
                current = point(from: current, relative: relative)
                path.addLine(to: current)
            case "H":
                let x = number()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case "V":
                let y = number()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case "C":
                let base = current
                let control1 = point(from: base, relative: relative)
                let control2 = point(from: base, relative: relative)
                current = point(from: base, relative: relative)
                path.addCurve(to: current, control1: control1, control2: control2)
            case "Z":
                path.closeSubpath()
                current = start
                // Z は座標を取らない。続く数字は読み捨てる（無限に回らないように）
                while nextIsNumber() { index += 1 }
            default:
                while nextIsNumber() { index += 1 }
            }
        }
        return path
    }

    /// 命令の文字と数字に分ける。「5.2-4.8」「2.8.3」のように区切りの無い数字も分ける
    private static func tokenize(_ d: String) -> [Token] {
        d.matches(of: /[MmLlHhVvCcZz]|-?(?:\d+\.?\d*|\.\d+)/).map { match in
            let text = String(match.output)
            if let first = text.first, first.isLetter { return .command(first) }
            return .number(CGFloat(Double(text) ?? 0))
        }
    }
}
