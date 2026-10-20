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
    /// 朗读进度（当前第几句 / 共几句），仅在这条正在被念时有值
    var progress: (Int, Int)? = nil
    var onImageClick: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    /// 重新生成这条回答（用前面的提问重跑，结果原地替换）
    var onRegenerate: (() -> Void)? = nil

    @Environment(\.hyperPalette) private var palette
    /// 缩略图异步解码结果（先占位、后填图，避免主线程解大图）
    @State private var thumbnailImage: UIImage?

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
            } else if shouldRenderMath {
                // 只要正文里真有 \(...\) / \[...\] 就走 KaTeX，不再按学科判断：
                // 语文的文言文断句、英语的语法公式都可能带 LaTeX，
                // 以前非数学学科会把 \( \frac{1}{2} \) 原样显示成一堆反斜杠。
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

    /// 是否走 KaTeX：只认「真的有公式」，没有就不建 WebView（省内存）
    private var shouldRenderMath: Bool {
        MarkdownLite.containsLatex(text)
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
            if let image = thumbnailImage {
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
                    // 占位先出现，解码在后台完成——流式时整表每 300ms 重绘一次，
                    // 同步解码会让滚动明显掉帧。
                    .task(id: uri) {
                        thumbnailImage = await LocalImage.loadAsync(uri)
                    }
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
            button(
                icon: isSpeakingThis ? "stop.circle.fill" : "speaker.wave.2",
                label: isSpeakingThis ? "停止朗读" : "朗读"
            ) { onSpeak?() }
            .foregroundStyle(isSpeakingThis ? palette.accent : palette.textSecondary)
            if let onToggleFavorite {
                button(icon: isFavorited ? "heart.fill" : "heart", label: "收藏") {
                    Haptics.lightTap()
                    onToggleFavorite()
                }
                .foregroundStyle(isFavorited ? palette.accent : palette.textSecondary)
            }
            if let onRegenerate {
                button(icon: "arrow.clockwise", label: "重新生成") { onRegenerate() }
            }
            // 朗读进度：长回答几十句，只有「在念」没有「念到哪」会让人不知道还剩多久
            if isSpeakingThis, let progress {
                speakProgress(progress)
            }
        }
        .padding(.top, 1)
    }

    /// 第 3/12 句 + 一条细进度条
    private func speakProgress(_ progress: (Int, Int)) -> some View {
        HStack(spacing: 6) {
            Text("\(progress.0)/\(progress.1)")
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.divider)
                    Capsule()
                        .fill(palette.accent)
                        .frame(
                            width: geo.size.width
                                * min(1, CGFloat(progress.0) / CGFloat(max(progress.1, 1)))
                        )
                }
            }
            .frame(width: 44, height: 3)
        }
        .padding(.leading, 6)
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
            if let onRegenerate {
                Button { onRegenerate() } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
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
///
/// 必须带缓存：流式回答时列表每 300 毫秒重绘一次，无缓存会把同一张图反复从磁盘解码，
/// 滚动和流式都会掉帧。
enum LocalImage {

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        c.totalCostLimit = 80 * 1024 * 1024
        return c
    }()

    private static func normalize(_ uri: String) -> String {
        // 容器路径可能在重装/迁移后变化，交给 FileStorage 统一兜底解析
        FileStorage.resolve(uri)
    }

    private static func decode(_ path: String) -> UIImage? {
        if let image = UIImage(contentsOfFile: path) { return image }
        // 最后再兜一层临时目录（相机直出的中转文件）
        return UIImage(contentsOfFile: NSTemporaryDirectory() + (path as NSString).lastPathComponent)
    }

    static func load(_ uri: String) -> UIImage? {
        let path = normalize(uri)
        if let hit = cache.object(forKey: path as NSString) { return hit }
        guard let image = decode(path) else { return nil }
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: path as NSString, cost: cost)
        return image
    }

    /// 后台解码；命中缓存时立刻返回，不占主线程。
    static func loadAsync(_ uri: String) async -> UIImage? {
        let path = normalize(uri)
        if let hit = cache.object(forKey: path as NSString) { return hit }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.load(uri))
            }
        }
    }
}
