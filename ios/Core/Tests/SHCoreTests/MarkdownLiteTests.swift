import XCTest
@testable import SHCore

/// 逐条搬运安卓 `MarkdownLiteTest`，两端行为必须一致；
/// 安卓侧后续任何排版改动都要同步到这里，否则 iOS 会静默回退。
final class MarkdownLiteTests: XCTestCase {

    /// 禁则包装会插进 <span class="nw">，测加粗/转义时先把它去掉，只看排版语义。
    private func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<span class=\"nw\">", with: "")
            .replacingOccurrences(of: "</span>", with: "")
    }

    func testStrip去除加粗标题代码与分隔线() {
        let md = "### 第一题\n**答案**是 `3/8`\n- 要点一\n---\n结束"
        XCTAssertEqual(MarkdownLite.strip(md), "第一题\n答案是 3/8\n• 要点一\n结束")
    }

    func testStrip不触碰LaTeX() {
        let latex = "面积公式 \\( S = \\pi r^2 \\)\n独立公式 \\[ \\frac{3}{4} \\]"
        XCTAssertEqual(MarkdownLite.strip(latex), latex)
    }

    func testToHtml转换加粗标题并转义尖括号() {
        let html = MarkdownLite.toHtml("### 标题\n**重点** <脚本> 内容")
        XCTAssertTrue(html.contains("<b>标题</b>"))
        XCTAssertTrue(html.contains("<b>重点</b>"))
        XCTAssertTrue(html.contains("&lt;脚本&gt;"))
        XCTAssertTrue(html.contains("<br>"))
    }

    func testToHtml保留LaTeX反斜杠() {
        let html = MarkdownLite.toHtml("答案是 \\( \\frac{3}{8} \\)")
        XCTAssertTrue(html.contains("\\( \\frac{3}{8} \\)"))
    }

    func testToRich输出纯文本内容一致() {
        let lines = MarkdownLite.toRich("### 标题\n**重点**普通\n- 项目")
        XCTAssertEqual(lines.map(\.plainText).joined(separator: "\n"), "标题\n重点普通\n• 项目")
    }

    func test公式后的孤立句号并回上一行() {
        let raw = "第2步：把 1/2 变成 4 分母。 \\( \\frac{1\\times2}{2\\times2} = \\frac{2}{4} \\)\n。\n第3步：相加"
        let out = MarkdownLite.strip(raw)
        XCTAssertEqual(
            out,
            "第2步：把 1/2 变成 4 分母。 \\( \\frac{1\\times2}{2\\times2} = \\frac{2}{4} \\)。\n第3步：相加"
        )
        XCTAssertEqual(MarkdownLite.normalizedLines(raw).count, 2)
    }

    func test行首括号不并行以免打乱列点() {
        let raw = "【答案】\n（1）对\n（2）错"
        XCTAssertEqual(MarkdownLite.normalizedLines(raw).count, 3)
    }

    func test收尾标点与前面的词锁在一起() {
        // 公式必须裸露给 KaTeX：一旦被包进 <span class="nw">，定界符被标签切开，
        // auto-render 就永远匹配不到，真机/模拟器都只会显示原始 \(...\)。
        let html = MarkdownLite.toHtml("写成 \\( \\frac{2}{5} \\) 。")
        XCTAssertTrue(html.contains("\\( \\frac{2}{5} \\)"), html)
        XCTAssertFalse(html.contains("<span class=\"nw\">\\( \\frac"), "公式不能进 nowrap：\(html)")
        // 数字接全角括号：不能把“）。”单独甩到下一行
        XCTAssertTrue(
            MarkdownLite.toHtml("答：28.26 平方厘米（ 取 3.14）。")
                .contains("<span class=\"nw\">3.14）。</span>")
        )
        // 只锁一个词，不会把整句吞进 nowrap
        XCTAssertFalse(
            MarkdownLite.toHtml("第1题考圆的面积公式。")
                .contains("<span class=\"nw\">第1题考圆的面积公式。</span>")
        )
    }

    func test禁则不能把整句锁成一个不折行块() {
        // 安卓真机踩过：非贪婪的 \(..\) 会为了凑出后面的“）。”一路扩到行尾，
        // 整句变成 nowrap 后塞不下，被整体挤到下一行，行首留一大片空白。
        let line = "第1题：答：\\( 28.26 \\) 平方厘米（\\( \\pi \\) 取 \\( 3.14 \\)）。"
        let html = MarkdownLite.toHtml(line)
        let marker = "<span class=\"nw\">"
        for piece in html.components(separatedBy: marker).dropFirst() {
            let span = piece.components(separatedBy: "</span>").first ?? ""
            XCTAssertFalse(span.isEmpty, "空的 nowrap 块：\(html)")
            // 按 UTF-16 计，与安卓 String.length 同口径
            XCTAssertLessThanOrEqual((span as NSString).length, 20, "nowrap 块过长：\(span)")
            XCTAssertFalse(span.contains("\\("), "nowrap 块里不能含公式：\(span)")
        }
        // 所有公式都必须完好保留，交给 KaTeX
        XCTAssertTrue(html.contains("\\( 28.26 \\)"), html)
        XCTAssertTrue(html.contains("\\( \\pi \\)"), html)
        XCTAssertTrue(html.contains("\\( 3.14 \\)"), html)
    }

    func test禁则不破坏LaTeX与实体() {
        let latex = "面积 \\( S = \\pi r^2 \\) 平方厘米"
        XCTAssertTrue(MarkdownLite.toHtml(latex).contains("\\( S = \\pi r^2 \\)"))
        XCTAssertTrue(plain(MarkdownLite.toHtml("a < b 与 & 符号")).contains("&lt;"))
    }

    func test分节标题单独成行时加粗() {
        let html = MarkdownLite.toHtml("【答案】\n答：7/8\n【解题思路】")
        XCTAssertTrue(plain(html).contains("<b>【答案】</b>"))
        XCTAssertTrue(plain(html).contains("<b>【解题思路】</b>"))
        XCTAssertFalse(plain(html).contains("<b>答：7/8</b>"))
        let lines = MarkdownLite.toRich("【答案】\n答：7/8")
        XCTAssertEqual(lines[0].segments.first?.text, "【答案】")
        XCTAssertEqual(lines[0].segments.first?.bold, true)
        XCTAssertEqual(lines[1].segments.first?.bold, false)
    }

    func test判别函数() {
        XCTAssertTrue(MarkdownLite.containsMarkdown("**加粗**"))
        XCTAssertTrue(MarkdownLite.containsMarkdown("### 标题"))
        XCTAssertFalse(MarkdownLite.containsMarkdown("【答案】普通文本"))
        XCTAssertTrue(MarkdownLite.containsLatex("公式 \\( x \\)"))
        XCTAssertFalse(MarkdownLite.containsLatex("无公式文本"))
    }
}
