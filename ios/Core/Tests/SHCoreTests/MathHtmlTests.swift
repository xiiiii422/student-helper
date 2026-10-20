import XCTest
@testable import SHCore

/// KaTeX 渲染前置条件测试。
///
/// 真机上出现过「公式永远不渲染、只显示原始 \(...\)」的 bug，
/// 根因是标点禁则把 `\(...\)` 整个包进了 `<span class="nw">`，
/// auto-render 遍历文本节点时看不到连续定界符。这里把它钉死。
final class MathHtmlTests: XCTestCase {

    func test公式不能被包进禁则span() {
        let html = MarkdownLite.toHtml("第2题：答：\\( \\frac{5}{6} \\)。")
        // 定界符必须连续出现在文本里，中间不能插入标签
        XCTAssertTrue(html.contains("\\( \\frac{5}{6} \\)"), html)
        XCTAssertFalse(
            html.contains("<span class=\"nw\">\\( \\frac"),
            "公式被包进 nw span 会让 KaTeX 匹配不到：\(html)"
        )
    }

    func test多个公式之间互不干扰() {
        let html = MarkdownLite.toHtml("先算 \\( 1+2 \\)，再算 \\( 3+4 \\)。")
        XCTAssertTrue(html.contains("\\( 1+2 \\)"), html)
        XCTAssertTrue(html.contains("\\( 3+4 \\)"), html)
    }

    func test独立公式块保留原样() {
        let html = MarkdownLite.toHtml("\\[ S = \\pi r^2 \\]")
        XCTAssertTrue(html.contains("\\[ S = \\pi r^2 \\]"), html)
    }

    func test没有公式时仍然做禁则() {
        let html = MarkdownLite.toHtml("答案是 28.26 平方厘米。")
        // 非公式文本该包还是包，避免句号单独成行
        XCTAssertTrue(html.contains("<span class=\"nw\">"), html)
    }

    func testHTML转义不影响公式反斜杠() {
        let html = MarkdownLite.toHtml("a < b 且 \\( x < y \\)")
        XCTAssertTrue(html.contains("&lt;"), "尖括号要转义：\(html)")
        XCTAssertTrue(html.contains("\\( x < y \\)"), "公式里的内容不转义：\(html)")
    }

    func test完整文档含KaTeX脚本与定界符配置() {
        let doc = MathHtml.document(content: "答：\\( \\frac{1}{2} \\)", colorHex: "#000000")
        XCTAssertTrue(doc.contains("katex.min.js"), doc)
        XCTAssertTrue(doc.contains("auto-render.min.js"), doc)
        XCTAssertTrue(doc.contains("renderMathInElement"), doc)
        XCTAssertTrue(doc.contains("#000000"), doc)
        // JS 里必须是转义后的 "\\["，浏览器才会得到 \[
        XCTAssertTrue(doc.contains(#"left:"\\["#), doc)
    }

    func test颜色换算() {
        XCTAssertEqual(MathHtml.hexColor(red: 0, green: 0, blue: 0), "#000000")
        XCTAssertEqual(MathHtml.hexColor(red: 1, green: 1, blue: 1), "#FFFFFF")
        // 越界要夹紧，不能算出 #-1 这种非法值
        XCTAssertEqual(MathHtml.hexColor(red: 2, green: -1, blue: 0.5), "#FF0080")
    }
}
