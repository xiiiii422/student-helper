import UIKit
import SHCore

/// 错题本导出 PDF：用系统 UIGraphicsPDFRenderer 绘制，零第三方依赖。
///
/// 为什么还要 PDF（已经有 txt 了）：家长要的是**打印出来给孩子做**，
/// 而打印店里 txt 排版会乱，PDF 才能保证分页、字号、行距固定。
///
/// 关键细节都对应真机踩过的坑：
/// - 中文字号行距固定，不能用屏幕上的动态字体（打印出来会忽大忽小）
/// - 自动分页：一页写满就开新页，绝不把一道题拦腰截断成两页
/// - 页边距留足，家用打印机普遍吃不掉太靠边的内容
enum PdfExport {

    private static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)  // A4 @72dpi
    private static let margin: CGFloat = 48
    private static let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
    private static let headFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    private static let bodyFont = UIFont.systemFont(ofSize: 11.5)
    private static let lineSpacing: CGFloat = 5

    /// 生成错题本 PDF，返回临时文件 URL。
    static func render(items: [FavoritesExport.Item], generatedAt: Date = Date()) throws -> URL {
        guard !items.isEmpty else { throw PdfError.empty }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("错题本-\(stamp(generatedAt)).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            var cursorY: CGFloat = margin
            var pageNo = 1

            // 开新页（同时画页脚页码）
            func newPage() {
                context.beginPage()
                cursorY = margin
                drawFooter(page: pageNo)
                pageNo += 1
            }

            func ensure(_ needed: CGFloat) {
                if cursorY + needed > page.height - margin - 24 { newPage() }
            }

            /// 画一段自动换行的文本，返回其后光标位置
            func draw(
                _ text: String, font: UIFont, x: CGFloat, width: CGFloat,
                color: UIColor = .black
            ) {
                let para = NSMutableParagraphStyle()
                para.lineSpacing = lineSpacing
                para.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color, .paragraphStyle: para
                ]
                let bounded = CGSize(width: width, height: .greatestFiniteMagnitude)
                let rect = (text as NSString).boundingRect(
                    with: bounded, options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs, context: nil
                )
                let h = ceil(rect.height)
                ensure(h)
                (text as NSString).draw(
                    in: CGRect(x: x, y: cursorY, width: width, height: h),
                    withAttributes: attrs
                )
                cursorY += h
            }

            newPage()  // 第一页

            let width = page.width - margin * 2
            draw("错题本", font: titleFont, x: margin, width: width)
            cursorY += 2
            draw(
                "共 \(items.count) 题 · 导出时间 \(Timestamp.format(Int(generatedAt.timeIntervalSince1970 * 1000)))",
                font: headFont, x: margin, width: width, color: .darkGray
            )
            cursorY += 14

            // 按学科分组，同组内按时间正序（先收的在前，符合复习顺序）
            let order = ["chinese": 0, "math": 1, "english": 2]
            let grouped = Dictionary(grouping: items) { $0.subject }
            let subjects = grouped.keys.sorted { (order[$0] ?? 99, $0) < (order[$1] ?? 99, $1) }

            var index = 1
            for subject in subjects {
                ensure(40)
                draw("【\(SubjectName.of(subject))】", font: headFont, x: margin, width: width)
                cursorY += 6

                for item in grouped[subject]!.sorted(by: { $0.createdAt < $1.createdAt }) {
                    let q = clean(item.question)
                    let a = clean(item.answer)

                    // 估算这一整题的高度，放不下就整题挪到下一页——
                    // 绝不把一道题拦腰截断在两页上（打印出来没法做）
                    let qH = height(of: "\(index). \(q)", width: width)
                    let aH = height(of: "   答：\(a)", width: width)
                    ensure(qH + aH + 16)

                    draw("\(index). \(q)", font: bodyFont, x: margin, width: width)
                    cursorY += 3
                    draw(
                        "   答：\(a)", font: bodyFont, x: margin, width: width,
                        color: UIColor(white: 0.25, alpha: 1)
                    )
                    cursorY += 14
                    index += 1
                }
                cursorY += 6
            }
        }
        return url
    }

    /// LaTeX 降级成可读文字（打印出来不能是一堆反斜杠）
    private static func clean(_ text: String) -> String {
        let s = MarkdownLite.degradeLatex(text)
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "（空）" : s
    }

    private static func height(of text: String, width: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont, .paragraphStyle: para
        ]
        let r = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        )
        return ceil(r.height)
    }

    private static func drawFooter(page: Int) {
        let text = "第 \(page) 页"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.lightGray
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: CGPoint(
                x: (PdfExport.page.width - size.width) / 2,
                y: PdfExport.page.height - margin + 10
            ),
            withAttributes: attrs
        )
    }

    private static func stamp(_ date: Date) -> String {
        Timestamp.format(Int(date.timeIntervalSince1970 * 1000))
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    enum PdfError: LocalizedError {
        case empty
        var errorDescription: String? { "当前没有可导出的错题" }
    }
}
