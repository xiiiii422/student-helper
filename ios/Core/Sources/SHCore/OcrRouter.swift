import Foundation

/// 拍照识别完之后「怎么发给模型」的决策结果。
///
/// 为什么需要分档：本地 OCR 对印刷体接近全对，对**手写**（尤其数学算式）错误率很高，
/// 而错一位数字就会把整道题讲歪。所以按「识别质量 + 学科」决定要不要把原图也带上。
public enum OcrMode: String, Equatable, CaseIterable {
    /// 高置信度纯文字：只发文字，省 token、更快。
    case textOnly
    /// 中置信度：文字为主，附带原图兜底。
    case textAndImage
    /// 低置信度/纯图形题：几乎完全依赖看图，文字只作参考。
    case imageOnly
}

/// 移植自安卓 `domain/ocr/OcrRouter.kt`：同一套规则，改动需要两端同步。
public enum OcrRouter {

    /// 多行版式阈值：语文/英语题常是「文章 + 小题」的多段结构，
    /// 超过这么多非空行时纯文字会丢掉版式，模型看不出哪句是文章、哪句是题目。
    public static let multiLineThreshold = 4

    /// 纯决策函数：识别文本 + 平均置信度 + 学科 → 发送模式。
    ///
    /// - Parameters:
    ///   - text: 本地 OCR 识别出的文本（可为空）
    ///   - confidence: 本地 OCR 平均置信度 0–1
    ///   - subject: `"math"` / `"chinese"` / `"english"`，与 App 里学科标识一致
    public static func decide(text: String, confidence: Double, subject: String) -> OcrMode {
        let isMath = subject == "math"
        // 数学：命中符号/算式特征就一定会带图——文本行识别器认不出分式、根号、上下标
        let hasMathSymbols = isMath && matches(mathPattern, text)
        // 图多字少（几何图、竖式、纯公式页）：有效字符太少，纯文字没有意义
        let sparseText = isMath && text.filter { !$0.isWhitespace }.count < 12
        // 语文/英语的多行阅读题：必须带图
        let nonBlankLines = text
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        let multiLineLayout = !isMath && nonBlankLines >= multiLineThreshold

        if confidence >= 0.90 && !hasMathSymbols && !sparseText && !multiLineLayout {
            return .textOnly
        }
        if confidence >= 0.60 {
            return .textAndImage
        }
        return .imageOnly
    }

    /// 常见数学符号 / 算式特征，命中则倾向走多模态兜底。
    private static let mathPattern = try! NSRegularExpression(
        pattern:
            "[∫∑√π∞≈≠≤≥÷×±]\\d*" +            // 特殊符号
            "|\\d+\\s*[+\\-*/÷×]\\s*\\d+\\s*=" +  // 四则算式
            "|\\d+/\\d+" +                      // 分数
            "|∠|⊥|∥|△|○"                        // 几何符号
    )

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
