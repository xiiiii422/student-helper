import SwiftUI
import UIKit
import SHCore

/// 消息气泡，逐条对齐安卓 `ui/components/ChatBubble.kt`：
/// 用户=品牌蓝实底白字右下小尖，AI=浅灰底黑字左下小尖，流式带光标，定稿后数学走 KaTeX。
///
/// iOS 侧额外加了两样安卓没有的：
/// - 朗读按钮：念这条回答，并把正在念的那句高亮（配合 SpeechService 的分句队列）
/// - 长按上下文菜单：复制 / 收藏 / 朗读 / 删除，比安卓的「长按直接删」更符合系统习惯，
///   因此删除改成菜单里二次确认，不会一按就掉
struct ChatBubbleView: View {
    let role: String
    let text: String
    let subject: String
    var imageUri: String? = nil
    var isStreaming: Bool = false
    var statusHint: String? = nil
    var isFavorited: Bool = false
    var onToggleFavorite: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onSpeak: (() -> Void)? = nil
    var spokenChunk: String? = nil
    var isSpeakingThis: Bool = false
    var onImageClick: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.hyperPalette) private var palette

    private var isUser: Bool { role == "user" }
    private var bubbleColor: Color { isUser ? palette.accent : palette.fill }
    private var textColor: Color { isUser ? .white : palette.text }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 1) {
                if let imageUri, !imageUri.isEmpty { thumbnail(imageUri) }
                bubble
                if !isUser && !isStreaming && onToggleFavorite != nil { actionRow }
            }
            .frame(maxWidth: isUser ? 290 : 310, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 44) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: 气泡主体

    private var bubble: some View {
        Group {
            if isStreaming && text.isEmpty {
                waitingContent
            } else if isStreaming {
                Text(streamingPreview)
                    .font(HyperType.body)
                    .lineSpacing(HyperType.bodyLineSpacing)
                    .foregroundStyle(textColor)
            } else if subject == "math" && MarkdownLite.containsLatex(text) {
                MathText(content: text, color: textColor)
            } else {
                RichText(text: text, color: textColor, highlight: isUser ? nil : spokenChunk)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .background(bubbleColor)
        .clipShape(BubbleShape.forUser(isUser))
        .contextMenu { menuItems }
    }

    /// 流式且还没有内容：三点指示器；退避重试时附一行小字，免得长等待被当成死机。
    private var waitingContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            LoadingDots(color: palette.textSecondary)
            if let statusHint {
                Text(statusHint)
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    /// 流式预览：去掉 Markdown 符号 + 光标，与安卓 `strip(text) + "▍"` 一致。
    private var streamingPreview: AttributedString {
        var result = AttributedString(MarkdownLite.strip(text))
        let cursor = AttributedString("▍")
        result.append(cursor)
        return result
    }

    // MARK: 图片缩略

    private func thumbnail(_ uri: String) -> some View {
        Group {
            if let image = LocalImage.load(uri) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 210, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.fill)
                    .frame(width: 210, height: 160)
                    .overlay(Image(systemName: "photo").foregroundStyle(palette.textTertiary))
            }
        }
        .padding(.bottom, 4)
        .onTapGesture { onImageClick?() }
    }

    // MARK: 操作行

    private var actionRow: some View {
        HStack(spacing: 2) {
            if let onCopy {
                button(icon: "doc.on.doc", label: "复制") { onCopy() }
            }
            button(icon: "speaker.wave.2", label: "朗读") { onSpeak?() }
                .foregroundStyle(isSpeakingThis ? palette.accent : palette.textSecondary)
            if let onToggleFavorite {
                button(icon: isFavorited ? "heart.fill" : "heart", label: "收藏") {
                    Haptics.lightTap()
                    onToggleFavorite()
                }
                .foregroundStyle(isFavorited ? palette.accent : palette.textSecondary)
            }
        }
        .padding(.top, 1)
    }

    private func button(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var menuItems: some View {
        if !isUser, !text.isEmpty {
            if let onCopy {
                Button { onCopy() } label: { Label("复制", systemImage: "doc.on.doc") }
            }
            Button { onSpeak?() } label: {
                Label(isSpeakingThis ? "停止朗读" : "朗读这条", systemImage: "speaker.wave.2")
            }
            if let onToggleFavorite {
                Button { onToggleFavorite() } label: {
                    Label(isFavorited ? "取消收藏" : "加入收藏", systemImage: "heart")
                }
            }
        }
        if let onDelete {
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// 定稿正文：MarkdownLite 的分段结构 → AttributedString，并把正在朗读的句子标出底色。
struct RichText: View {
    let text: String
    let color: Color
    var highlight: String?

    var body: some View {
        Text(attributed)
            .font(HyperType.body)
            .lineSpacing(HyperType.bodyLineSpacing)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        let lines = MarkdownLite.toRich(text)
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            for segment in line.segments {
                var piece = AttributedString(segment.text)
                if segment.bold { piece.font = .system(size: 17, weight: .bold) }
                if let highlight, segment.text.contains(highlight) {
                    piece.backgroundColor = Color.yellow.opacity(0.28)
                }
                result.append(piece)
            }
        }
        return result
    }
}

/// 触感反馈集中在这里，免得每个按钮各写一遍。
enum Haptics {
    static func lightTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// 本地图片读取（拍照/相册都先落到 App 沙盒，路径存进数据库，与安卓 FileStorage 同思路）。
enum LocalImage {
    static func load(_ uri: String) -> UIImage? {
        let path = uri.hasPrefix("file://")
            ? (URL(string: uri)?.path ?? uri)
            : uri
        if let image = UIImage(contentsOfFile: path) { return image }
        return UIImage(contentsOfFile: NSTemporaryDirectory() + (path as NSString).lastPathComponent)
    }
}
