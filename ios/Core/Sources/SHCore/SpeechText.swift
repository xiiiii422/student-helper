import Foundation

/// 朗读前的文本归一化：把讲稿变成「人会说出口」的话。
///
/// 这是「用尽可能像人的语速和音色朗读」这条需求里真正容易做错的一半 ——
/// 音色由系统语音决定，但如果直接把 Markdown 喂给 TTS，学生会听到
/// 「左括号 反斜杠 frac 七 八 右括号」，而老师说的一定是「八分之七」。
///
/// 放在 Core 里是因为这套替换全是纯字符串规则，必须能在不启动模拟器的情况下测。
public enum SpeechText {

    public enum Language: String, Equatable {
        case chinese, english
    }

    public struct Chunk: Equatable {
        public let text: String
        public let language: Language
        public init(text: String, language: Language) {
            self.text = text
            self.language = language
        }
    }

    // MARK: 规则表

    private static let displayMath = try! NSRegularExpression(pattern: #"\\\[(.+?)\\\]"#, options: [.dotMatchesLineSeparators])
    private static let inlineMath = try! NSRegularExpression(pattern: #"\\\((.+?)\\\)"#, options: [.dotMatchesLineSeparators])
    private static let sectionTag = try! NSRegularExpression(pattern: "【([^】]{1,14})】")
    private static let bullet = try! NSRegularExpression(pattern: "^[ \\t]*[•·][ \\t]*", options: [])
    private static let frac = try! NSRegularExpression(pattern: #"\\d?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#)
    private static let sqrt = try! NSRegularExpression(pattern: #"\\sqrt\s*\{([^{}]*)\}"#)
    private static let power2 = try! NSRegularExpression(pattern: #"\^\s*2|\\times\s*2(?![0-9])"#)
    private static let power3 = try! NSRegularExpression(pattern: #"\^\s*3"#)
    private static let percent = try! NSRegularExpression(pattern: #"([0-9.]+)\s*%"#)
    private static let leftoverCmd = try! NSRegularExpression(pattern: #"\\[a-zA-Z]+"#)
    private static let multiSpace = try! NSRegularExpression(pattern: "[ \\t]{2,}")
    private static let cjk = try! NSRegularExpression(pattern: #"[\u4e00-\u9fff]"#)

    /// 一条命令词的读法替换。顺序敏感：先长后短。
    private static let wordMap: [(String, String)] = [
        ("\\times", " 乘 "),
        ("\\div", " 除以 "),
        ("\\frac", " "),          // 已由 frac 正则处理，剩下的当噪声清掉
        ("\\dfrac", " "),
        ("\\pi", "π"),
        ("\\approx", " 约等于 "),
        ("\\geq", " 大于等于 "),
        ("\\leq", " 小于等于 "),
        ("\\neq", " 不等于 "),
        ("\\left", " "),
        ("\\right", " "),
        ("\\%", "%"),
        ("=", " 等于 "),
        ("+", " 加 "),
        ("-", " 减 "),
        ("(", "（"),
        (")", "）"),
    ]

    // MARK: 对外

    /// Markdown + LaTeX → 可直接交给 TTS 的中文口语串。
    public static func normalize(_ raw: String) -> String {
        var s = MarkdownLite.strip(raw)

        // 独立公式块先摘掉定界符，内容按行内公式同样处理
        s = replacing(displayMath, s) { group($0, 1, in: s) }

        // 每个 \( ... \) 内部整体翻译成口语
        s = replacing(inlineMath, s) { m in
            " " + speakMath(group(m, 1, in: s)) + " "
        }

        // 【答案】这类小标题读成「答案，」，让耳朵能分出段落
        s = replacing(sectionTag, s) { m in group(m, 1, in: s) + "，" }
        s = replacing(bullet, s) { _ in "" }
        s = s.replacingOccurrences(of: "——", with: "，")
            .replacingOccurrences(of: "---", with: "")
        s = replacing(multiSpace, s) { _ in " " }

        // 连续空行压成一个换行，分句时按它断
        s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把 `\frac{7}{8}`、`r^2`、`3.14 × 6` 这类式子翻成中文读法。
    static func speakMath(_ inner: String) -> String {
        var s = inner
        // 中文分数先说分母再说分子：\frac{7}{8}（7/8）要念「八分之七」。
        // 正则只吃不含花括号的一层，所以嵌套分数天然从最内层开始替，循环几次就能剥完。
        for _ in 0..<4 {
            let next = replacing(frac, s) { m in
                let num = group(m, 1, in: s).trimmingCharacters(in: .whitespaces)
                let den = group(m, 2, in: s).trimmingCharacters(in: .whitespaces)
                return " \(den)分之\(num) "
            }
            if next == s { break }
            s = next
        }
        s = replacing(sqrt, s) { "根号" + group($0, 1, in: s) }
        s = replacing(power3, s) { _ in " 的立方 " }
        s = replacing(power2, s) { _ in " 的平方 " }
        s = replacing(percent, s) { "百分之" + group($0, 1, in: s) }

        for (from, to) in wordMap {
            s = s.replacingOccurrences(of: from, with: to)
        }
        // 兜底：没进映射表的 \command 直接删掉，念出来只会是噪声
        s = replacing(leftoverCmd, s) { _ in " " }
        s = s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        s = replacing(multiSpace, s) { _ in " " }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// 归一化 + 按呼吸断句 + 逐段判定语种。
    /// 英语题的讲解是中文夹英文，一个中文音色念 English 单词很难听，所以按脚本切段交给不同 voice。
    public static func chunks(_ raw: String, maxChunkChars: Int = 42) -> [Chunk] {
        let text = normalize(raw)
        guard !text.isEmpty else { return [] }
        var out: [Chunk] = []
        for sentence in splitSentences(text, maxChunkChars: maxChunkChars) {
            for piece in splitByScript(sentence) {
                out.append(Chunk(text: piece, language: language(of: piece)))
            }
        }
        return out
    }

    /// 句子级切分：中文句末标点、换行都断；过长的句子再按逗号找换气口。
    static func splitSentences(_ text: String, maxChunkChars: Int) -> [String] {
        var result: [String] = []
        var current = ""
        let delimiters: Set<Character> = ["。", "！", "？", "；", "…", "\n", ".", "!", "?", ";"]
        for ch in text {
            current.append(ch)
            if delimiters.contains(ch) {
                flush(&result, &current, maxChunkChars: maxChunkChars)
            }
        }
        flush(&result, &current, maxChunkChars: maxChunkChars)
        return result
    }

    private static func flush(_ result: inout [String], _ current: inout String, maxChunkChars: Int) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        current = ""
        guard !trimmed.isEmpty else { return }
        if trimmed.count <= maxChunkChars {
            result.append(trimmed)
            return
        }
        // 太长：从最后一个逗号/顿号处劈开，保证 TTS 有换气，不至于越念越快
        var head = Substring(trimmed)
        let soft: [Character] = ["，", "、", ",", " "]
        for mark in soft {
            if let idx = head.lastIndex(of: mark),
               head.distance(from: head.startIndex, to: idx) > maxChunkChars / 3 {
                let cut = head.index(after: idx)
                result.append(String(head[..<cut]).trimmingCharacters(in: .whitespaces))
                head = head[cut...]
            }
        }
        let rest = String(head).trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
    }

    /// 中文段与拉丁段分开，交给各自的音色。
    static func splitByScript(_ sentence: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var currentIsLatin: Bool?
        for ch in sentence {
            let latin = ch.isASCII && (ch.isLetter || ch.isNumber)
            let isCjk = isCjkChar(ch)
            guard !isCjk else {
                if !current.isEmpty { pieces.append(current); current = "" }
                currentIsLatin = nil
                current.append(ch)
                continue
            }
            if latin {
                if currentIsLatin == false, !current.isEmpty { pieces.append(current); current = "" }
                currentIsLatin = true
                current.append(ch)
            } else {
                // 标点等中性字符跟在当前段尾巴上
                current.append(ch)
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func language(of piece: String) -> Language {
        if cjk.firstMatch(in: piece, range: NSRange(location: 0, length: (piece as NSString).length)) != nil {
            return .chinese
        }
        return .english
    }

    private static func isCjkChar(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(Int(scalar.value))
    }

    // MARK: 正则小工具（与 MarkdownLite 同一套字面替换语义）

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

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : (s as NSString).substring(with: r)
    }
}
