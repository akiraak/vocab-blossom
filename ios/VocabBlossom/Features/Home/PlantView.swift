import SwiftUI

/// 単語 1 つを花に見立てて描く。
///
/// 数値より先に「庭が育つ」絵で進捗が伝わるようにするための、庭・一覧共通の部品。
struct PlantView: View {
    let stage: GrowthStage
    var size: CGFloat = 28

    private var stemHeight: CGFloat {
        switch stage {
        case .seed: 0
        case .sprout: size * 0.42
        case .bud: size * 0.52
        case .blossom: size * 0.5
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if stage != .seed {
                Capsule()
                    .fill(Theme.sprout)
                    .frame(width: max(1.5, size * 0.08), height: stemHeight)
            }
            leaves
            head
                .offset(y: -stemHeight)
        }
        .frame(width: size, height: size, alignment: .bottom)
    }

    @ViewBuilder
    private var leaves: some View {
        if stage != .seed {
            let leaf = Ellipse().fill(Theme.sprout.opacity(0.85))
            let width = size * 0.3
            let height = size * 0.16
            HStack(spacing: size * 0.02) {
                leaf.frame(width: width, height: height).rotationEffect(.degrees(-20))
                leaf.frame(width: width, height: height).rotationEffect(.degrees(20))
            }
            .offset(y: -stemHeight * 0.45)
        }
    }

    @ViewBuilder
    private var head: some View {
        switch stage {
        case .seed:
            Ellipse()
                .fill(Theme.seed)
                .frame(width: size * 0.34, height: size * 0.26)
        case .sprout:
            EmptyView()
        case .bud:
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Theme.bud, Theme.blossom.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.34, height: size * 0.44)
        case .blossom:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(Theme.blossom.opacity(0.9))
                        .frame(width: size * 0.3, height: size * 0.3)
                        .offset(y: -size * 0.17)
                        .rotationEffect(.degrees(Double(index) * 72))
                }
                Circle()
                    .fill(Color(red: 0.98, green: 0.75, blue: 0.14))
                    .frame(width: size * 0.22, height: size * 0.22)
            }
            .frame(width: size * 0.64, height: size * 0.64)
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(GrowthStage.allCases, id: \.self) { stage in
            VStack {
                PlantView(stage: stage, size: 56)
                Text(stage.label).font(.caption)
            }
        }
    }
    .padding()
}
