import SwiftUI

/// 単語 1 つを植物の線画で描く（種 → 芽 → つぼみ → 開花）。
///
/// 数値より先に「庭が育つ」絵で進捗が伝わるようにするための、庭・一覧共通の部品
struct PlantView: View {
    let stage: GrowthStage
    var size: CGFloat = 28

    var body: some View {
        LineArtView(drawing: PlantDrawing.glyph(stage), color: stage.color, lineWidth: 1.6)
            .frame(width: size, height: size)
    }
}

/// グループのカード・オンボーディングに置く、大きな植物の絵
struct PlantIllustration: View {
    let stage: GrowthStage
    var height: CGFloat = 110
    var color: Color?

    var body: some View {
        LineArtView(
            drawing: PlantDrawing.illustration(stage),
            color: color ?? stage.color,
            lineWidth: 1.1
        )
        .frame(width: height * 64 / 74, height: height)
    }
}

/// ロゴの印（小枝）
struct BrandMark: View {
    var height: CGFloat = 22

    var body: some View {
        LineArtView(drawing: PlantDrawing.sprig, color: Theme.accent, lineWidth: 1.3)
            .frame(width: height * 14 / 22, height: height)
    }
}

/// ロゴ: 小枝の印 ＋ 字間を広げた「VOCAB GARDEN」
struct BrandWordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            BrandMark()
            Text("VOCAB GARDEN")
                .font(.system(size: 13, weight: .medium))
                .tracking(4.4)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("VocabGarden")
    }
}

/// 線画 1 枚（SVG の座標のまま持ち、枠に合わせて縮める）
struct PlantDrawing {
    let viewBox: CGSize
    /// 線で描く部分
    let stroke: Path
    /// 塗る部分（種・花の芯）
    var fill = Path()

    static func glyph(_ stage: GrowthStage) -> PlantDrawing {
        switch stage {
        case .seed: glyphSeed
        case .sprout: glyphSprout
        case .bud: glyphBud
        case .blossom: glyphBlossom
        }
    }

    static func illustration(_ stage: GrowthStage) -> PlantDrawing {
        switch stage {
        case .seed: illustrationSeed
        case .sprout: illustrationSprout
        case .bud: illustrationBud
        case .blossom: illustrationBlossom
        }
    }

    // 小さな絵（一覧の行・庭）: 24 x 26
    private static let glyphBox = CGSize(width: 24, height: 26)
    private static let glyphSeed = PlantDrawing(
        viewBox: glyphBox, stroke: Path(),
        fill: Path(ellipseIn: CGRect(x: 9, y: 21, width: 6, height: 4))
    )
    private static let glyphSprout = PlantDrawing(
        viewBox: glyphBox,
        stroke: paths("M12 25v-7", "M12 19c-3 0-5-1.8-5.2-4.8 3 .1 5 2 5.2 4.8z")
    )
    private static let glyphBud = PlantDrawing(
        viewBox: glyphBox,
        stroke: paths("M12 25V11", "M12 20c-3 0-5-1.8-5.2-4.8 3 .1 5 2 5.2 4.8z")
            .union(Path(ellipseIn: CGRect(x: 9.6, y: 4.1, width: 4.8, height: 6.8)))
    )
    private static let glyphBlossom = PlantDrawing(
        viewBox: glyphBox,
        stroke: paths("M12 25V11.2", "M12 21c-3 0-5-1.8-5.2-4.8 3 .1 5 2 5.2 4.8z")
            .union(Path(ellipseIn: CGRect(x: 7.8, y: 2.8, width: 8.4, height: 8.4))),
        fill: Path(ellipseIn: CGRect(x: 10.8, y: 5.8, width: 2.4, height: 2.4))
    )

    // 大きな絵（グループのカード）: 64 x 74
    private static let illustrationBox = CGSize(width: 64, height: 74)
    private static let illustrationSeed = PlantDrawing(
        viewBox: illustrationBox, stroke: Path(),
        fill: [22.0, 34, 46].reduce(into: Path()) { path, x in
            path.addEllipse(in: CGRect(x: x - 3.4, y: 67.7, width: 6.8, height: 4.6))
        }
    )
    private static let illustrationSprout = PlantDrawing(
        viewBox: illustrationBox,
        stroke: paths(
            "M32 74V52",
            "M32 58c-6 0-10-3.4-11-9 6 .2 10 3.6 11 9z",
            "M32 54c5 0 8.5-3 9-7.5-5 .2-8.5 3.2-9 7.5z"
        )
    )
    private static let illustrationBud = PlantDrawing(
        viewBox: illustrationBox,
        stroke: paths("M32 74V33.5", "M32 62c-8 0-13-5-14-12 8 .2 13 5 14 12z")
            .union(Path(ellipseIn: CGRect(x: 27, y: 16.5, width: 10, height: 17)))
    )
    private static let illustrationBlossom = PlantDrawing(
        viewBox: illustrationBox,
        stroke: paths(
            "M32 74V26",
            "M32 60c-8 0-13-5-14-12 8 .2 13 5 14 12z",
            "M32 46c7 0 12-4.5 13-11-7 .3-12 4.6-13 11z"
        )
        .union(Path(ellipseIn: CGRect(x: 22, y: 6, width: 20, height: 20))),
        fill: Path(ellipseIn: CGRect(x: 29, y: 13, width: 6, height: 6))
    )

    // ロゴの小枝: 14 x 22
    static let sprig = PlantDrawing(
        viewBox: CGSize(width: 14, height: 22),
        stroke: paths(
            "M7 21V5",
            "M7 15c-3.5 0-5.8-2-6-5.4 3.5.1 5.8 2.1 6 5.4z",
            "M7 9c3 0 5-1.7 5.2-4.6-3 .1-5 1.8-5.2 4.6z"
        )
    )

    private static func paths(_ ds: String...) -> Path {
        ds.reduce(into: Path()) { path, d in path.addPath(SVGPath.path(d)) }
    }
}

private extension Path {
    func union(_ other: Path) -> Path {
        var result = self
        result.addPath(other)
        return result
    }
}

/// 線画を枠いっぱい（縦横比はそのまま・下寄せ）に描く
struct LineArtView: View {
    let drawing: PlantDrawing
    let color: Color
    /// 線の太さ（線画の座標での値。枠に合わせて一緒に縮む）
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let box = drawing.viewBox
            let scale = min(geometry.size.width / box.width, geometry.size.height / box.height)
            let transform = CGAffineTransform(
                translationX: (geometry.size.width - box.width * scale) / 2,
                y: geometry.size.height - box.height * scale
            )
            .scaledBy(x: scale, y: scale)
            ZStack {
                drawing.stroke.applying(transform)
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: max(1, lineWidth * scale), lineCap: .round, lineJoin: .round
                        )
                    )
                drawing.fill.applying(transform).fill(color)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        BrandWordmark()
        HStack(spacing: 24) {
            ForEach(GrowthStage.allCases, id: \.self) { stage in
                VStack {
                    PlantView(stage: stage, size: 40)
                    PlantIllustration(stage: stage, height: 90)
                    Text(stage.label).font(.caption)
                }
            }
        }
    }
    .padding()
}
