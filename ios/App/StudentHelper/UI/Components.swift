import SwiftUI
import SHCore

/// 通用组件：大标题、子页导航、文字按钮、底栏。
/// 尺寸与配色逐条对齐安卓 `ui/components/IosComponents.kt` 与 `ui/navigation/AppBottomBar.kt`，
/// 安卓 1dp = iOS 1pt，数值直接沿用。

// MARK: - 大标题

struct IosLargeTitle: View {
    let title: String
    var actions: AnyView = AnyView(EmptyView())

    @Environment(\.hyperPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(title)
                .font(HyperType.largeTitle)
                .foregroundStyle(palette.text)
            Spacer(minLength: 0)
            actions
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 子页导航行

struct IosNavBar: View {
    let title: String
    let onBack: () -> Void
    var actions: AnyView = AnyView(EmptyView())

    @Environment(\.hyperPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text(title)
                .font(HyperType.title2)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}

// MARK: - 文字按钮（系统 bar button 风）

struct IosTextButton: View {
    let text: String
    var color: Color?
    let action: () -> Void

    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(HyperType.labelLarge)
                .foregroundStyle(color ?? palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 发丝分隔线，对应安卓 0.5dp outlineVariant。
struct Hairline: View {
    @Environment(\.hyperPalette) private var palette
    var body: some View {
        Rectangle().fill(palette.divider).frame(height: 0.5)
    }
}

// MARK: - 底栏

enum BottomTab: String, CaseIterable, Identifiable {
    case chinese, math, english, composition, me
    var id: String { rawValue }

    var label: String {
        switch self {
        case .chinese: return "语文"
        case .math: return "数学"
        case .english: return "英语"
        case .composition: return "作文"
        case .me: return "我的"
        }
    }

    /// 未选中细线 / 选中填充，与安卓双态图标一致。
    var iconUnselected: String {
        switch self {
        case .chinese: return "book.closed"
        case .math: return "calculator"
        case .english: return "textformat.abc"
        case .composition: return "square.and.pencil"
        case .me: return "person"
        }
    }

    var iconSelected: String {
        switch self {
        case .chinese: return "book.closed.fill"
        case .math: return "calculator.fill"
        case .english: return "textformat.abc.dottedunderline"
        case .composition: return "square.and.pencil"
        case .me: return "person.fill"
        }
    }

    var accent: Color { SubjectColor.forSubject(rawValue) }

    /// “我的”不是学科，不参与红/蓝/绿/橙那套身份色。
    var indicatorColor: Color { rawValue == "me" ? Hyper.me : accent }
}

/// 澎湃 OS 风 Tab 栏：乳白半透 + 发丝顶线。选中态统一用品牌蓝（HyperOS 系统应用
/// 不会一个 tab 一个颜色），学科强调色只保留为标签下一条 3pt 短横，兼顾识别与克制。
struct AppBottomBar: View {
    @Binding var selection: BottomTab
    var onPick: (BottomTab) -> Void = { _ in }

    @Environment(\.hyperPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(BottomTab.allCases) { tab in
                    item(tab)
                }
            }
            .padding(.vertical, 6)
            // 背景延伸到安全区后方，内容避开 Home 指示条
            .padding(.bottom, 0)
        }
        .background(palette.card.opacity(0.94))
        .overlay(alignment: .top) { EmptyView() }
    }

    private func item(_ tab: BottomTab) -> some View {
        let selected = tab == selection
        let tint = selected ? palette.accent : palette.textSecondary
        return Button {
            if tab != selection { onPick(tab) }
            selection = tab
        } label: {
            VStack(spacing: 0) {
                Image(systemName: selected ? tab.iconSelected : tab.iconUnselected)
                    .font(.system(size: 21, weight: selected ? .semibold : .regular))
                    .symbolVariant(selected ? .fill : .none)
                    .foregroundStyle(tint)
                    .frame(height: 26)
                    .scaleEffect(selected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: selection)

                Text(tab.label)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                    .padding(.top, 2)

                // 学科色短横：常驻占位，避免选中切换时整栏高度跳动
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tab.indicatorColor.opacity(selected ? 1 : 0))
                    .frame(width: 14, height: 3)
                    .padding(.top, 3)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selection)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
