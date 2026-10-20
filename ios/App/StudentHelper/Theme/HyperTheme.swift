import SwiftUI
import SHCore

/// 小米澎湃 OS（HyperOS）色板与排版，逐一对齐安卓 `ui/theme/Color.kt`、`Type.kt`、`Shape.kt`、`Theme.kt`。
/// 尺寸口径：安卓 1dp ≈ iOS 1pt，iPhone 14 逻辑分辨率 390×844，直接沿用同一批数字。

extension Color {
    /// 0xRRGGBB，与安卓 Color(0xFF...) 同写法，方便两端对色。
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Hyper {
    // ── 品牌与中性色（浅色） ──
    static let miBlue = Color(hex: 0x0A59F7)            // 小米品牌蓝（主强调）
    static let miOrange = Color(hex: 0xFF6900)          // 小米品牌橙（次强调）
    static let background = Color(hex: 0xF5F5F5)        // 页面灰底
    static let card = Color(hex: 0xFFFFFF)              // 分组白卡
    static let fill = Color(hex: 0xF2F3F5)              // 输入胶囊 / AI 气泡填充
    static let divider = Color(hex: 0xE5E6EB)           // 分隔线
    static let text = Color(hex: 0x1D2129)              // 一级文本
    static let textSecondary = Color(hex: 0x4E5969)     // 二级文本
    static let textTertiary = Color(hex: 0x86909C)      // 三级文本 / 未选中图标

    // ── 深色（澎湃 OS Dark） ──
    static let miBlueDark = Color(hex: 0x409CFF)
    static let backgroundDark = Color(hex: 0x171717)
    static let cardDark = Color(hex: 0x1F1F1F)
    static let fillDark = Color(hex: 0x2C2C2E)
    static let dividerDark = Color(hex: 0x38383A)
    static let textDark = Color(hex: 0xF5F5F7)
    static let textSecondaryDark = Color(hex: 0x98989F)

    // ── 学科强调色（克制、小面积点睛） ──
    static let chinese = Color(hex: 0xF53F3F)           // 语文·红
    static let math = miBlue                            // 数学·小米蓝
    static let english = Color(hex: 0x00B42A)           // 英语·绿
    static let composition = miOrange                   // 作文·小米橙
    /// “我的”不是学科，不参与红/蓝/绿/橙那套身份色；再用紫会退化成系统默认强调色的观感。
    static let me = textSecondary

    // ── 分数配色 ──
    static let scoreExcellent = Color(hex: 0x00B42A)    // >=90 绿
    static let scoreGood = miBlue                       // >=80 蓝
    static let scoreFair = Color(hex: 0xFF7D00)         // >=70 橙
    static let scorePoor = Color(hex: 0xF53F3F)         // <70 红

    // ── 状态指示（连接测试这类“通/不通”小圆点，不用学科身份色） ──
    static let statusOk = Color(hex: 0x00B42A)

    // ── 批改详情语义色（深浅各一套，避免深底上几乎看不清） ──
    static let noteOriginal = Color(hex: 0xB45309)
    static let noteOriginalDark = Color(hex: 0xFFB84D)
    static let noteBetter = Color(hex: 0x0E9F5B)
    static let noteBetterDark = Color(hex: 0x65D18A)
}

/// 学科身份色：讲题气泡的操作行、底栏选中态、错题本色条都用它。
enum SubjectColor {
    static func forSubject(_ apiValue: String) -> Color {
        switch apiValue {
        case "chinese": return Hyper.chinese
        case "english": return Hyper.english
        case "composition": return Hyper.composition
        default: return Hyper.math
        }
    }
}

/// 分数环底色，阈值与安卓 `scoreColor` 一致。
enum ScoreColor {
    static func forScore(_ score: Int) -> Color {
        switch score {
        case 90...: return Hyper.scoreExcellent
        case 80..<90: return Hyper.scoreGood
        case 70..<80: return Hyper.scoreFair
        default: return Hyper.scorePoor
        }
    }
}

/// iOS 没有 Material3 的 ColorScheme，这里把两端需要共用的语义色打包成环境值，
/// 视图里写 `palette.surface` 而不是散落的十六进制，保证换肤只改一处。
struct HyperPalette {
    let background: Color
    let card: Color
    let fill: Color
    let divider: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let error: Color
    let statusOk: Color
    let isDark: Bool

    static let light = HyperPalette(
        background: Hyper.background, card: Hyper.card, fill: Hyper.fill,
        divider: Hyper.divider, text: Hyper.text, textSecondary: Hyper.textSecondary,
        textTertiary: Hyper.textTertiary, accent: Hyper.miBlue,
        error: Hyper.scorePoor, statusOk: Hyper.statusOk, isDark: false
    )

    static let dark = HyperPalette(
        background: Hyper.backgroundDark, card: Hyper.cardDark, fill: Hyper.fillDark,
        divider: Hyper.dividerDark, text: Hyper.textDark, textSecondary: Hyper.textSecondaryDark,
        textTertiary: Hyper.textSecondaryDark, accent: Hyper.miBlueDark,
        error: Color(hex: 0xFF6960), statusOk: Hyper.statusOk, isDark: true
    )
}

private struct HyperPaletteKey: EnvironmentKey {
    static let defaultValue: HyperPalette = .light
}

extension EnvironmentValues {
    var hyperPalette: HyperPalette {
        get { self[HyperPaletteKey.self] }
        set { self[HyperPaletteKey.self] = newValue }
    }
}

/// 外观模式：0 跟随系统，1 强制浅色，2 强制深色。与安卓 `keyThemeMode` 同一套取值。
enum ThemeMode: Int, CaseIterable, Codable {
    case system = 0, light = 1, dark = 2

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    func colorScheme(_ systemDark: Bool) -> ColorScheme? {
        switch self {
        case .system: return systemDark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }

    func resolvePalette(systemDark: Bool) -> HyperPalette {
        switch self {
        case .system: return systemDark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 排版阶梯，对应安卓 AppTypography：Large Title 34 / Title2 22 / Body 17 / Subheadline 15 / Footnote 13。
/// 字体用系统 SF Pro（中文自动回落 PingFang SC），与安卓用 MiSans 的思路一致：跟系统走，不自带字体。
///
/// 用 `.custom(_:size:relativeTo:)` 而不是 `Font.system(size:)`：
/// 后者是绝对字号，系统「设置 → 显示与亮度 → 文字大小」调大时完全不变；
/// 前者按指定样式缩放，用户在无障碍里放大字号，正文会真的变大。
/// 这对小学生（尤其近视的）比像素级还原设计稿重要。
enum HyperType {
    /// 页面大标题（IosLargeTitle 的等价物）
    static let largeTitle = Font.custom("SF Pro Display", size: 34, relativeTo: .largeTitle)
        .weight(.bold)
    static let title2 = Font.custom("SF Pro Display", size: 22, relativeTo: .title2)
        .weight(.bold)
    static let titleMedium = Font.custom("SF Pro Text", size: 17, relativeTo: .headline)
        .weight(.semibold)
    /// 气泡正文：17/24，与安卓 bodyLarge 完全一致
    static let body = Font.custom("SF Pro Text", size: 17, relativeTo: .body)
    static let bodyMedium = Font.custom("SF Pro Text", size: 15, relativeTo: .subheadline)
    static let labelLarge = Font.custom("SF Pro Text", size: 15, relativeTo: .subheadline)
        .weight(.medium)
    static let footnote = Font.custom("SF Pro Text", size: 13, relativeTo: .footnote)
    /// 气泡行高，对应安卓 lineHeight = 24.sp。
    /// 行距不跟字号等比放大是刻意的：大字号下再加 7pt 会散架，这里保持固定。
    static let bodyLineSpacing: CGFloat = 7

    /// 分数环里的数字
    static let scoreNumber = Font.custom("SF Pro Text", size: 15, relativeTo: .caption)
        .weight(.bold)
}

/// 圆角：卡片 20 / 气泡 18 / 小件 12，与安卓 CardShape、BubbleShape 同值。
enum HyperRadius {
    static let card: CGFloat = 20
    static let bubble: CGFloat = 18
    static let small: CGFloat = 12
    static let extraSmall: CGFloat = 8
    static let medium: CGFloat = 16
    static let extraLarge: CGFloat = 26

    static let cardShape = RoundedRectangle(cornerRadius: card, style: .continuous)
    static let smallShape = RoundedRectangle(cornerRadius: small, style: .continuous)
}

/// 气泡形状：用户右下小尖、AI 左下小尖，与安卓 ChatBubble 的 18dp + 6dp 组合逐角一致。
/// 用 iOS 16 的 UnevenRoundedRectangle 直接四角分半径，不需要再桥 UIKit 圆角。
enum BubbleShape {
    static let user = UnevenRoundedRectangle(
        topLeadingRadius: 18, bottomLeadingRadius: 18,
        bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous
    )
    static let assistant = UnevenRoundedRectangle(
        topLeadingRadius: 18, bottomLeadingRadius: 6,
        bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous
    )

    static func forUser(_ isUser: Bool) -> UnevenRoundedRectangle {
        isUser ? user : assistant
    }
}
