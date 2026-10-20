import Foundation

/// 错题本导出：把收藏的题目+答案排成一份可直接打印的纯文本。
///
/// 为什么是纯文本而不是 PDF：分享面板里「文件」App 能存、备忘录能贴、微信能发，
/// 家长拿去打印店也好处理；PDF 反而要额外引 UIKit 排版代码，收益不大。
public enum FavoritesExport {

    public struct Item {
        public let subject: String
        public let question: String
        public let answer: String
        public let createdAt: Int

        public init(subject: String, question: String, answer: String, createdAt: Int) {
            self.subject = subject
            self.question = question
            self.answer = answer
            self.createdAt = createdAt
        }
    }

    /// 生成可读的错题清单。答案里的 LaTeX 会降级成「7/8」这种形式，
    /// 否则打印出来全是反斜杠。
    public static func render(items: [Item], generatedAt: Date = Date()) -> String {
        guard !items.isEmpty else { return "（错题本是空的）\n" }

        var out = "错题本 · 共 \(items.count) 题\n"
        out += "导出时间：\(Timestamp.format(Int(generatedAt.timeIntervalSince1970 * 1000)))\n"
        out += String(repeating: "=", count: 32) + "\n\n"

        // 按学科分组，同科内按时间正序（先收的在前，符合复习顺序）
        let order = ["chinese": 0, "math": 1, "english": 2]
        let grouped = Dictionary(grouping: items) { $0.subject }
        let subjects = grouped.keys.sorted {
            (order[$0] ?? 99, $0) < (order[$1] ?? 99, $1)
        }

        var index = 1
        for subject in subjects {
            out += "【\(SubjectName.of(subject))】\n\n"
            for item in grouped[subject]!.sorted(by: { $0.createdAt < $1.createdAt }) {
                out += "\(index). \(clean(item.question))\n"
                out += "   答：\(clean(item.answer))\n\n"
                index += 1
            }
            out += "\n"
        }
        return out
    }

    /// 去掉 LaTeX 标记与多余空白，保证打印出来是人话
    private static func clean(_ text: String) -> String {
        let degraded = MarkdownLite.degradeLatex(text)
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return degraded.isEmpty ? "（空）" : degraded
    }
}

/// 学科中文名。Core 里不依赖 App 层的 SubjectLabel，单独放一份最小的。
public enum SubjectName {
    public static func of(_ apiValue: String) -> String {
        switch apiValue {
        case "chinese": return "语文"
        case "english": return "英语"
        case "math": return "数学"
        default: return apiValue
        }
    }
}
