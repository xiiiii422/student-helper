import Foundation

/// 轻量 Markdown / 中文禁则处理，逐条对齐安卓 `core/util/MarkdownLite.kt`。
///
/// 三科讲解文本长这样：`【答案】`、`**加粗**`、`### 标题`、`- 列表`、`\(...\)` 公式。
/// 模型输出并不总是守规矩，所以渲染前先规范化。三种形态：
/// - `strip`：流式期间纯文本预览
/// - `toRich`：定稿气泡用的分段结构（iOS 侧由 UI 层映射成 AttributedString）
/// - `toHtml`：喂给 WKWebView + KaTeX 的 HTML 片段
///
/// 所有转换都不触碰 LaTeX 定界符 `\(` `\)` `\[` `\]` 与反斜杠命令。
public enum MarkdownLite {

    // MARK: - 规则

    private static let bold = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let heading = try! NSRegularExpression(pattern: #"^\s{0,3}#{1,4}\s+(.*)$"#)
    private static let bullet = try! NSRegularExpression(pattern: #"^\s*[-*•]\s+"#)
    private static let rule = try! NSRegularExpression(pattern: #"^\s*(-{3,}|\*{3,})\s*$"#)
    private static let code = try! NSRegularExpression(pattern: "`([^`]+)`")
    private static let section = try! NSRegularExpression(pattern: #"^\s*(【[^】]{2,14}】)\s*$"#)

    /// 中文行首标点：模型常在 LaTeX 公式后断开，导致“。”孤零零占一行。
    /// 只含收尾类标点；故意不含“（”，因为“（1）xxx”是常见的合法换行项。
    private static let orphanPunct = try! NSRegularExpression(
        pattern: #"^[\u3002\uff0c\u3001\uff1b\uff1a\uff1f\uff01\u201d\u2019\u2014\u2026\uff09\u3011\u300b,;?!]"#
    )

    /// 公式与收尾标点之间多一个空格，浏览器就会把“。”单独折到下一行。
    private static let spaceBeforeClose = try! NSRegularExpression(
        pattern: #"\s+(?=[\u3002\uff0c\uff1b\uff1a\uff01\uff1f\uff09\u3011\u300b])"#
    )

    /// 中文禁则（标点不得出现在行首）不能指望渲染端：
    /// WebView 实测 lang="zh-CN" + line-break:strict 无效，公式又是 atomic inline，禁则更管不到；
    /// 这里直接把「前一个词 + 收尾标点」包成 nowrap，标点永远跟着前面的字走。
    ///
    /// 公式那段必须写成 `(?:(?!\\\().){1,40}?`：只写 `\\\(.{1,40}?\\\)` 的话，非贪婪只是优先短匹配，
    /// 为了让后面的标点成立，引擎会一路扩到本行最后一个 `\)`，把整句锁成一个不可断的块，
    /// 行首那一长串塞不下就整体挪到下一行，留下大片空白（安卓真机踩过，iOS 的 WKWebView 同引擎）。
    /// 40 字封顶：再长的算式宁可让它可以断，也别把整行顶到下一行。
    private static let punctGlue = try! NSRegularExpression(
        pattern: #"(\\\((?:(?!\\\().){1,40}?\\\)|[0-9A-Za-z.%\-]{1,24}|[\u4e00-\u9fff])([\u3002\uff0c\u3001\uff1b\uff1a\uff01\uff1f\u201d\u2019\u2014\u2026\uff09\u3011\u300b\)\]]+)"#
    )

    // MARK: - 对外判定

    public static func containsMarkdown(_ text: String) -> Bool {
        if bold.firstMatch(in: text, range: nsRange(text)) != nil { return true }
        for line in splitLines(text) {
            if isFullMatch(heading, line) { return true }
            if bullet.firstMatch(in: line, range: nsRange(line)) != nil { return true }
            if isFullMatch(rule, line) { return true }
        }
        return false
    }

    public static func containsLatex(_ text: String) -> Bool {
        text.contains("\\(") || text.contains("\\[")
    }

    // MARK: - 行规范化

    /// 丢弃分隔线，并把以标点开头的行并回上一行末尾。
    /// 三种渲染形态共用，保证流式预览 / 定稿气泡 / KaTeX WebView 表现一致。
    public static func normalizedLines(_ text: String) -> [String] {
        var out: [String] = []
        out.reserveCapacity(16)
        for raw in splitLines(text) {
            if isFullMatch(rule, raw) { continue }
            var trimmed = trimStart(raw)
            trimmed = replacing(spaceBeforeClose, trimmed) { _ in "" }
            if !out.isEmpty,
               !trimmed.isEmpty,
               orphanPunct.firstMatch(in: trimmed, range: nsRange(trimmed)) != nil {
                out[out.count - 1] = trimEnd(out[out.count - 1]) + trimmed
            } else {
                out.append(trimmed)
            }
        }
        return out
    }

    // MARK: - 三种输出形态

    /// 纯文本化（流式预览用）。
    public static func strip(_ text: String) -> String {
        normalizedLines(text).map { line in
            let base = firstGroup(heading, line) ?? line
            let unbuilt = replacingFirst(bullet, base) { _ in "• " }
            let afterBold = replacing(bold, unbuilt) { group($0, 1, in: unbuilt) }
            return replacing(code, afterBold) { group($0, 1, in: afterBold) }
        }.joined(separator: "\n")
    }

    /// KaTeX 不可用时的降级：把 LaTeX 转成人能读的纯文字。
    ///
    /// 真机上如果 WKWebView 拿不到 bundle 里的 KaTeX 资源（或 JS 被拦），
    /// 公式会原样显示成 `\( \frac{7}{8} \)`——学生看到一堆反斜杠。
    /// 这里退化成「7/8」这种能看懂的形式，宁可朴素也不要露原始标记。
    public static func degradeLatex(_ text: String) -> String {
        var s = strip(text)
        // 定界符直接去掉
        for token in ["\\(", "\\)", "\\[", "\\]", "$$", "$"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        // 分数 \frac{a}{b} → (a)/(b)，循环几次处理嵌套
        let frac = try! NSRegularExpression(pattern: #"\\d?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#)
        for _ in 0..<4 {
            let next = replacing(frac, s) { m in
                let num = group(m, 1, in: s).trimmingCharacters(in: .whitespaces)
                let den = group(m, 2, in: s).trimmingCharacters(in: .whitespaces)
                return "(\(num))/(\(den))"
            }
            if next == s { break }
            s = next
        }
        let sqrt = try! NSRegularExpression(pattern: #"\\sqrt\s*\{([^{}]*)\}"#)
        s = replacing(sqrt, s) { "√(" + group($0, 1, in: s) + ")" }
        // 常见命令换成符号
        let map: [(String, String)] = [
            ("\\times", "×"), ("\\div", "÷"), ("\\pi", "π"),
            ("\\approx", "≈"), ("\\geq", "≥"), ("\\leq", "≤"),
            ("\\neq", "≠"), ("\\angle", "∠"), ("\\%", "%"),
            ("\\left", ""), ("\\right", ""), ("\\cdot", "·"),
        ]
        for (from, to) in map { s = s.replacingOccurrences(of: from, with: to) }
        // 剩余 \command 与多余花括号清掉
        let leftover = try! NSRegularExpression(pattern: #"\\[a-zA-Z]+"#)
        s = replacing(leftover, s) { _ in "" }
        s = s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        let spaces = try! NSRegularExpression(pattern: "[ \t]{2,}")
        s = replacing(spaces, s) { _ in " " }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 定稿气泡用：按行给出带加粗标记的分段。
    public static func toRich(_ text: String) -> [RichLine] {
        normalizedLines(text).map { raw in
            let headingTitle = firstGroup(heading, raw)
            let emphasized = headingTitle != nil || isFullMatch(section, raw)
            let line = headingTitle ?? raw
            let hasBullet = bullet.firstMatch(in: line, range: nsRange(line)) != nil
            let body = replacingFirst(bullet, line) { _ in "" }
            var segments = boldSegments(body, baseBold: emphasized)
            if hasBullet {
                segments.insert(RichSegment(text: "• ", bold: emphasized), at: 0)
            }
            return RichLine(segments: segments)
        }
    }

    /// WKWebView + KaTeX 用：先转义再还原标记，公式反斜杠不受影响。
    public static func toHtml(_ text: String) -> String {
        normalizedLines(text).map { raw in
            let headingTitle = firstGroup(heading, raw)
            let emphasized = headingTitle != nil || isFullMatch(section, raw)
            var line = escapeHtml(headingTitle ?? raw)
            line = replacingFirst(bullet, line) { _ in "• " }
            let afterBullet = line
            line = replacing(bold, afterBullet) { "<b>" + group($0, 1, in: afterBullet) + "</b>" }
            let afterBold = line
            line = replacing(code, afterBold) { "<code>" + group($0, 1, in: afterBold) + "</code>" }
            // 实体（&lt; &#39;）里的分号会被误当成标点，所以转义之后再包、且禁则集不含 ASCII 分号
            //
            // 关键：禁则不能把 `\(...\)` 整个包进 <span class="nw">。
            // KaTeX 的 auto-render 只遍历「连续文本节点」里的定界符，
            // 公式被标签切开后永远匹配不到，真机/模拟器都表现为显示原始 \(...\)。
            //
            // 折中：公式本身保持裸露（让 KaTeX 能渲染），
            // 只在公式**后面**的收尾标点上单独包一个 nowrap span 并前置零宽连接符，
            // 既不会把标点甩到行首，也不破坏定界符。
            let beforeGlue = line
            line = gluePunctuationOutsideMath(beforeGlue)
            return emphasized ? "<b>\(line)</b>" : line
        }.joined(separator: "<br>")
    }

    /// 公式保持原样，标点禁则只作用于非公式片段。
    ///
    /// 公式**后面紧跟**的收尾标点不能包进 span（会切断 KaTeX 的定界符），
    /// 也不靠 word joiner（实测在 WebKit 里对 inline-block 之后的位置无效）。
    /// 这里只保证公式文本连续，粘行由 MathHtml 里的 JS 在渲染后按 DOM 处理。
    private static func gluePunctuationOutsideMath(_ line: String) -> String {
        let formulaPattern = try! NSRegularExpression(
            pattern: #"(\\\((?:(?!\\\().)*?\\\)|\\\[(?:(?!\\\[).)*?\\\])"#,
            options: [.dotMatchesLineSeparators]
        )
        var out = ""
        var cursor = 0
        let ns = line as NSString
        for m in formulaPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let before = ns.substring(
                with: NSRange(location: cursor, length: m.range.location - cursor)
            )
            out += gluePlain(before)
            out += ns.substring(with: m.range)
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length {
            out += gluePlain(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return out
    }

    private static func gluePlain(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return replacing(punctGlue, text) { m in
            "<span class=\"nw\">" + group(m, 0, in: text) + "</span>"
        }
    }

    // MARK: - 输出结构

    public struct RichSegment: Equatable {
        public let text: String
        public let bold: Bool
        public init(text: String, bold: Bool) {
            self.text = text
            self.bold = bold
        }
    }

    public struct RichLine: Equatable {
        public let segments: [RichSegment]
        public init(segments: [RichSegment]) { self.segments = segments }
        public var plainText: String { segments.map(\.text).joined() }
    }

    // MARK: - 内部工具

    /// 与安卓 appendWithBold 同序：先清 `code` 再找 `**bold**`（替换会移动索引，简化处理）。
    private static func boldSegments(_ text: String, baseBold: Bool) -> [RichSegment] {
        let cleaned = replacing(code, text) { group($0, 1, in: text) }
        var segments: [RichSegment] = []
        var cursor = 0
        for m in bold.matches(in: cleaned, range: nsRange(cleaned)) {
            if m.range.location > cursor {
                segments.append(RichSegment(
                    text: substring(cleaned, NSRange(location: cursor, length: m.range.location - cursor)),
                    bold: baseBold
                ))
            }
            segments.append(RichSegment(text: group(m, 1, in: cleaned), bold: true))
            cursor = NSMaxRange(m.range)
        }
        if cursor < (cleaned as NSString).length {
            segments.append(RichSegment(
                text: substring(cleaned, NSRange(location: cursor, length: (cleaned as NSString).length - cursor)),
                bold: baseBold
            ))
        }
        return segments.filter { !$0.text.isEmpty }
    }

    private static func escapeHtml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Kotlin 的 lineSequence 认 \n、\r\n、\r；这里对齐，避免 Windows 风格换行留个孤零零的 \r。
    private static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func trimStart(_ s: String) -> String {
        String(s.drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func trimEnd(_ s: String) -> String {
        String(s.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
    }

    private static func nsRange(_ s: String) -> NSRange {
        NSRange(location: 0, length: (s as NSString).length)
    }

    private static func substring(_ s: String, _ r: NSRange) -> String {
        (s as NSString).substring(with: r)
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : substring(s, r)
    }

    private static func firstGroup(_ re: NSRegularExpression, _ s: String) -> String? {
        guard let m = re.firstMatch(in: s, range: nsRange(s)) else { return nil }
        let r = m.range(at: 1)
        return r.location == NSNotFound ? nil : substring(s, r)
    }

    /// Kotlin 的 Regex.matches 语义：整串必须被规则吃掉。
    private static func isFullMatch(_ re: NSRegularExpression, _ s: String) -> Bool {
        guard let m = re.firstMatch(in: s, range: nsRange(s)) else { return false }
        return m.range == nsRange(s)
    }

    /// 逐条替换，替换文本按字面插入（不像 withTemplate 那样解释 `$` 与 `\`）。
    private static func replacing(
        _ re: NSRegularExpression, _ input: String, _ transform: (NSTextCheckingResult) -> String
    ) -> String {
        let ns = input as NSString
        var out = ""
        var cursor = 0
        for m in re.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            }
            out += transform(m)
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length {
            out += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return out
    }

    private static func replacingFirst(
        _ re: NSRegularExpression, _ input: String, _ transform: (NSTextCheckingResult) -> String
    ) -> String {
        guard let m = re.firstMatch(in: input, range: nsRange(input)) else { return input }
        let ns = input as NSString
        return ns.substring(with: NSRange(location: 0, length: m.range.location))
            + transform(m)
            + ns.substring(with: NSRange(location: NSMaxRange(m.range), length: ns.length - NSMaxRange(m.range)))
    }
}
