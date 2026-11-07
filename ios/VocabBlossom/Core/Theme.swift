import SwiftUI
import UIKit

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

    /// 植物の線画の色。育つほど濃いセージになる
    var color: Color {
        switch self {
        case .seed: Theme.seed
        case .sprout: Theme.sprout
        case .bud: Theme.bud
        case .blossom: Theme.blossom
        }
    }

    /// 色面（カードの地）の色。育つほど濃くなる
    var tint: Color {
        switch self {
        case .seed: Theme.tintSeed
        case .sprout: Theme.tintSprout
        case .bud: Theme.tintBud
        case .blossom: Theme.tintBlossom
        }
    }
}

/// 配色とレイアウトの共通値。
///
/// 白の地に、セージ 1 色と細い線画で見せる（2026-11-07 のデザイン B4）。
/// 枠線は使わず、育ち具合で濃さの変わる薄いセージの色面で区切る。
/// アプリはいつもライトの見た目で出す（Info.plist の `UIUserInterfaceStyle: Light`）。
/// ダークの色も持っているのは、ダークモードに戻すときにそのまま使えるようにするため
enum Theme {
    static let background = Color("LaunchBackground")
    static let accent = Color.accentColor

    // 植物の線画（種 → 芽 → つぼみ → 開花）
    static let seed = Color(light: 0xBDBDB7, dark: 0x5E645F)
    static let sprout = Color(light: 0x7FA38A, dark: 0x7FA38A)
    static let bud = Color(light: 0x5F8A6C, dark: 0x9CC2A6)
    static let blossom = Color.accentColor

    // 色面（育つほど濃い）
    static let tintSeed = Color(light: 0xF5F5F2, dark: 0x1A1D1B)
    static let tintSprout = Color(light: 0xF2F5F2, dark: 0x1B211D)
    static let tintBud = Color(light: 0xEDF2EE, dark: 0x1E2721)
    static let tintBlossom = Color(light: 0xE4EDE6, dark: 0x233026)

    /// ふつうのカードの地（育ち具合と関係ない情報）
    static let card = Color(light: 0xF4F6F3, dark: 0x1A1F1C)
    /// 色面の上の補足の文字（`secondary` より少し濃い）
    static let tintText = Color(light: 0x4F5B53, dark: 0xA7B3AA)
    /// 細い線（区切り・枠線の選択肢・空のカードの点線）
    static let hairline = Color(light: 0xE6E6E2, dark: 0x2B322D)
    /// 進み具合の線の地
    static let track = Color(light: 0xECECE8, dark: 0x2B322D)

    /// セージの地の上の文字・記号（ダークはセージが明るいので暗い文字にする）
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x111513)

    static let correct = Color(light: 0x3F6B4C, dark: 0x8DBB98)
    static let incorrect = Color(light: 0xB9503F, dark: 0xE08A7A)

    static let cardCorner: CGFloat = 22
}

extension Color {
    /// ライト・ダークで色を変える（16 進の RGB）
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

// SwiftUI は描画用のスレッドで色を解決することがあるので、解決する処理はメインアクターに縛らない
// （縛ると読み上げ画面のアニメーション中などに落ちる）
nonisolated private extension UIColor {
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// 画面全体に共通の背景を敷く。
    func gardenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// カード: 枠線の無い薄い色面（角丸 22）。`tint` を渡すと、その色面にする
    func cardStyle(_ tint: Color = Theme.card) -> some View {
        padding(16)
            .frame(maxWidth: .infinity)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }

    /// 字間を広げた小さな見出し（「グループ」「今日の復習」など）
    func sectionLabel() -> some View {
        font(.caption.weight(.medium))
            .tracking(1.6)
            .foregroundStyle(.secondary)
    }
}

/// 丸いバーのボタン（主: セージの地に白い文字、副: 薄い色面にセージの文字）。画面の幅いっぱいに広がる
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .tracking(0.8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.accent)
            .background(prominent ? Theme.accent : Theme.tintBlossom, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    /// 主のボタン（セージの地）
    static var capsule: CapsuleButtonStyle { CapsuleButtonStyle() }
    /// 副のボタン（薄い色面）
    static var capsuleSecondary: CapsuleButtonStyle { CapsuleButtonStyle(prominent: false) }
}
