import SwiftUI

/// 花の成長段階。ステージ（0〜5）を初学者向けの言葉に翻訳する。
enum GrowthStage: String, CaseIterable, Sendable {
    case seed, sprout, bud, blossom

    init(stage: Int) {
        switch stage {
        case ..<1: self = .seed
        case 1...2: self = .sprout
        case 3...4: self = .bud
        default: self = .blossom
        }
    }

    var label: String {
        switch self {
        case .seed: "種"
        case .sprout: "芽"
        case .bud: "つぼみ"
        case .blossom: "開花"
        }
    }

    /// 庭・一覧で使う絵文字。数値より先に絵で進捗が分かるようにする
    var symbol: String {
        switch self {
        case .seed: "🌱"
        case .sprout: "🌿"
        case .bud: "🌷"
        case .blossom: "🌸"
        }
    }

    var color: Color {
        switch self {
        case .seed: Theme.seed
        case .sprout: Theme.sprout
        case .bud: Theme.bud
        case .blossom: Theme.blossom
        }
    }
}

/// 配色とレイアウトの共通値。
enum Theme {
    static let background = Color("LaunchBackground")
    static let accent = Color.accentColor

    static let seed = Color(red: 0.63, green: 0.55, blue: 0.47)
    static let sprout = Color(red: 0.40, green: 0.73, blue: 0.42)
    static let bud = Color(red: 0.95, green: 0.62, blue: 0.71)
    static let blossom = Color(red: 0.93, green: 0.28, blue: 0.60)

    static let correct = Color(red: 0.15, green: 0.66, blue: 0.42)
    static let incorrect = Color(red: 0.87, green: 0.35, blue: 0.31)

    static let cardCorner: CGFloat = 16
}

extension View {
    /// 画面全体に共通の背景を敷く。
    func gardenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// カード風の白背景。
    func cardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }
}
