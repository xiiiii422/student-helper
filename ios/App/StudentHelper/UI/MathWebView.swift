import SwiftUI
import WebKit
import SHCore

/// 含 LaTeX 的讲稿渲染：WKWebView + 本地 KaTeX，高度按内容自适应。
///
/// 与安卓 MathText 同一套约束：WebView 不会自己撑高，不给高度就会被父容器按视口截断
/// （长答案最后一行切一半）。所以页面加载完回读 `document.body.scrollHeight`，
/// CSS px 直接当 pt 用（viewport 是 device-width，1:1）。
///
/// 两个易错点也照搬安卓的处置：
/// - KaTeX 字体是异步换的，首帧高度偏小 → 120ms / 420ms 各量一次
/// - 同一份 HTML 只加载一次，否则列表回滚时整页重载会白屏闪一下
struct MathWebView: UIViewRepresentable {
    let content: String
    /// 正文颜色（跟随深浅色语义色）
    let color: Color
    /// 量到的内容高度回调
    let onHeight: (CGFloat) -> Void
    /// 诊断回调（仅截图模式），把 KaTeX 是否加载成功透出来
    var onDiagnostics: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.allowsLinkPreview = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        web.navigationDelegate = context.coordinator
        context.coordinator.onHeight = onHeight
        if ScreenshotMode.isActive {
            context.coordinator.onDiagnostics = onDiagnostics
        }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onHeight = onHeight
        // 颜色也要进签名：深浅色切换后若只比 content，KaTeX 正文会留着老颜色
        let signature = content + "|" + colorHex
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature
        context.coordinator.reload(in: web, content: content, colorHex: colorHex)
    }

    private var colorHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return MathHtml.hexColor(red: Double(r), green: Double(g), blue: Double(b))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastSignature: String?
        var onHeight: ((CGFloat) -> Void)?
        /// 诊断回调（仅截图模式用）
        var onDiagnostics: ((String) -> Void)?
        private var lastHeight: CGFloat = 0

        func reload(in web: WKWebView, content: String, colorHex: String) {
            lastHeight = 0
            let html = MathHtml.document(content: content, colorHex: colorHex)
            // 关键：不能用 loadHTMLString(_:baseURL:)。
            // 那种方式下 WKWebView 对 file:// 相对资源（katex.min.js/css/fonts）的读取权限
            // 不可靠——真机与模拟器都会静默加载失败，公式永远不渲染，只剩原始 \(...\) 文本。
            //
            // 正确做法：把 HTML 与 KaTeX 资源放进**同一个可读目录**，再用 loadFileURL 加载。
            // KaTeX 在 bundle 里是只读的，所以整个目录先拷进 Caches 一份（首次约 1MB，之后复用），
            // HTML 也写在那儿，allowingReadAccessTo 只需要这一个目录。
            guard let workDir = Self.workingDirectory() else {
                web.loadHTMLString(html, baseURL: nil)
                return
            }
            let page = workDir.appendingPathComponent("page-\(UUID().uuidString).html")
            do {
                try html.write(to: page, atomically: true, encoding: .utf8)
                web.loadFileURL(page, allowingReadAccessTo: workDir)
            } catch {
                web.loadHTMLString(html, baseURL: nil)
            }
        }

        /// 可写的 KaTeX 工作目录：首次调用把 bundle 里的 KaTeX 整目录拷过来。
        ///
        /// 为什么必须拷：loadFileURL 的 allowingReadAccessTo 只接受**一个**目录，
        /// 而 bundle 是只读的、HTML 又必须写盘，两者不在同一棵树里就没法同时授权。
        /// 全部放进 Caches/KaTeX 后，HTML 与资源同目录，一次授权即可。
        static func workingDirectory() -> URL? {
            let fm = FileManager.default
            guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return katexDirectoryURL
            }
            let dir = caches.appendingPathComponent("KaTeX", isDirectory: true)
            let js = dir.appendingPathComponent("katex.min.js")
            if fm.fileExists(atPath: js.path) { return dir }

            guard let source = katexDirectoryURL else { return nil }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let items = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            else { return source }
            for item in items {
                let dest = dir.appendingPathComponent(item.lastPathComponent)
                try? fm.removeItem(at: dest)          // 上次半截拷贝可能留着
                try? fm.copyItem(at: item, to: dest)
            }
            // 拷贝没成功（比如 fonts 目录）就退回 bundle 目录，至少 CSS/JS 还能试
            return fm.fileExists(atPath: js.path) ? dir : source
        }

        /// Assets/KaTeX 目录：与安卓 assets/katex 同一批文件
        /// （katex.min.css / katex.min.js / auto-render.min.js / fonts）
        static var katexDirectoryURL: URL? {
            Bundle.main.url(forResource: "KaTeX", withExtension: nil) ?? Bundle.main.resourceURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 字体异步替换，首帧偏小；两次都量，量到 0 保持原样不把自己压成一条线
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak webView] in
                guard let webView else { return }
                self.probe(webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak webView] in
                guard let webView else { return }
                self.probe(webView)
                self.diagnose(webView) { text in self.onDiagnostics?(text) }
            }
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            print("[MathWebView] 加载失败: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print("[MathWebView] 预加载失败: \(error.localizedDescription)")
        }

        private func probe(_ webView: WKWebView) {
            webView.evaluateJavaScript(MathHtml.heightProbe) { [weak self] result, error in
                guard let self, error == nil,
                      let value = result as? Int, value > 0 else { return }
                let next = CGFloat(value)
                guard next != self.lastHeight else { return }
                self.lastHeight = next
                DispatchQueue.main.async { self.onHeight?(next) }
            }
        }

        /// 诊断用：KaTeX 到底有没有跑起来（脚本加载失败 / 解析报错都会导致公式保持原文）。
        /// 截图模式下把结果回传出来，直接画在页面上——CI 里 print 抓不到，
        /// 只能靠「看得见的字」判断到底卡在哪一步。
        func diagnose(_ webView: WKWebView, report: @escaping (String) -> Void) {
            let js = """
            (function(){
              var hasKatex = (typeof katex !== 'undefined');
              var hasRender = (typeof renderMathInElement !== 'undefined');
              var rendered = document.querySelectorAll('.katex').length;
              var bodyText = document.body ? document.body.innerText : '';
              return 'katex=' + hasKatex + ' render=' + hasRender
                   + ' nodes=' + rendered + ' len=' + bodyText.length;
            })();
            """
            webView.evaluateJavaScript(js) { result, error in
                if let text = result as? String {
                    report(text)
                } else if let error {
                    report("js-error: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// 讲稿正文：有公式走 KaTeX，没公式走 AttributedString。
/// 无公式时根本不建 WebView（省内存，与安卓同一策略）。
///
/// KaTeX 资源加载失败时（bundle 里拿不到、JS 被拦、WebContent 被杀），
/// WebView 会一直量不到高度、卡在 44pt 只显示第一行原始 `\(...\)`。
/// 这里加了 2.5s 超时：仍没量到就整体降级成「去 LaTeX 的纯文本」，宁可朴素也别露反斜杠。
struct MathText: View {
    let content: String
    var color: Color = .primary
    @State private var height: CGFloat = 0
    @State private var renderFailed = false
    /// 截图模式下的 KaTeX 诊断信息，直接画在页面上
    @State private var diagnostics: String?

    var body: some View {
        Group {
            if MarkdownLite.containsLatex(content) && !renderFailed {
                VStack(alignment: .leading, spacing: 2) {
                    MathWebView(content: content, color: color) { measured in
                        if measured != height { height = measured }
                    } onDiagnostics: { text in
                        diagnostics = text
                    }
                    .frame(width: .infinity, height: height > 0 ? height : 44, alignment: .topLeading)
                    // 截图模式把诊断结果显示出来：CI 里看不到 print，只能靠页面上的字判断
                    if ScreenshotMode.isActive, let diagnostics {
                        Text("[katex] \(diagnostics)")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                .task(id: content) {
                    // 2.5s 还没量到高度 = KaTeX 没跑起来，降级
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if height <= 0 { renderFailed = true }
                }
            } else {
                Text(renderFailed ? degradedAttributed : attributed)
                    .font(HyperType.body)
                    .lineSpacing(HyperType.bodyLineSpacing)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: height)
    }

    /// 降级文本：去掉 LaTeX 标记，公式变成 7/8、√(x) 这类可读形式
    private var degradedAttributed: AttributedString {
        var result = AttributedString()
        let lines = MarkdownLite.toRich(MarkdownLite.degradeLatex(content))
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            for segment in line.segments {
                var piece = AttributedString(segment.text)
                if segment.bold { piece.font = .system(size: 17, weight: .bold) }
                result.append(piece)
            }
        }
        // 截图模式下把「为什么降级」标出来，否则在 CI 里根本看不出 KaTeX 是否加载成功
        if ScreenshotMode.isActive {
            result.append(AttributedString("\n[降级]"))
        }
        return result
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        let lines = MarkdownLite.toRich(content)
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            for segment in line.segments {
                var piece = AttributedString(segment.text)
                if segment.bold { piece.font = .system(size: 17, weight: .bold) }
                result.append(piece)
            }
        }
        return result
    }
}

/// 三点输入指示器，对应安卓 LoadingDots。
struct LoadingDots: View {
    var color: Color = .secondary
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(opacity(for: index))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityHidden(true)
    }

    private func opacity(for index: Int) -> Double {
        // 三个点轮流亮，相位错开 1/3 个周期
        let offsets = [0.0, 0.33, 0.66]
        let t = (phase + offsets[index]).truncatingRemainder(dividingBy: 1.0)
        return 0.3 + 0.7 * abs(sin(t * .pi))
    }
}
