import XCTest
@testable import SHCore

/// LaTeX 降级测试：KaTeX 渲染不出来时，宁可显示「7/8」也不能让学生看到 `\( \frac{7}{8} \)`。
final class LatexDegradeTests: XCTestCase {

    func test分数降级成可读形式() {
        let out = MarkdownLite.degradeLatex("答：\\( \\frac{7}{8} \\)")
        XCTAssertTrue(out.contains("(7)/(8)"), out)
        XCTAssertFalse(out.contains("\\"), "不能留反斜杠：\(out)")
        XCTAssertFalse(out.contains("frac"), "不能留命令名：\(out)")
    }

    func test嵌套分数也能降级() {
        let out = MarkdownLite.degradeLatex("\\( \\frac{1}{\\frac{2}{3}} \\)")
        XCTAssertFalse(out.contains("\\"), out)
        XCTAssertFalse(out.contains("frac"), out)
    }

    func test根号与常见符号() {
        XCTAssertTrue(MarkdownLite.degradeLatex("\\( \\sqrt{9} \\)").contains("√(9)"))
        XCTAssertTrue(MarkdownLite.degradeLatex("\\( 3 \\times 4 \\)").contains("×"))
        XCTAssertTrue(MarkdownLite.degradeLatex("\\( 1 \\div 2 \\)").contains("÷"))
        XCTAssertTrue(MarkdownLite.degradeLatex("\\( \\pi r^2 \\)").contains("π"))
    }

    func test独立公式块也清干净() {
        let out = MarkdownLite.degradeLatex("""
        【解题思路】
        第1步：\\[ S = \\pi r^2 \\]
        第2步：代入
        """)
        XCTAssertFalse(out.contains("\\["), out)
        XCTAssertFalse(out.contains("\\]"), out)
        XCTAssertTrue(out.contains("【解题思路】"), "正文结构要保留")
    }

    func test普通文本不受影响() {
        let plain = "这道题考查圆的面积，答案是 28.26 平方厘米。"
        XCTAssertEqual(MarkdownLite.degradeLatex(plain), plain)
    }

    func test空输入不崩() {
        XCTAssertEqual(MarkdownLite.degradeLatex(""), "")
    }

    func test多余花括号与命令被清掉() {
        let out = MarkdownLite.degradeLatex("\\( \\text{甲} + \\unknowncmd 1 \\)")
        XCTAssertFalse(out.contains("{"), out)
        XCTAssertFalse(out.contains("}"), out)
        XCTAssertFalse(out.contains("\\"), out)
        XCTAssertTrue(out.contains("1"), out)
    }
}
