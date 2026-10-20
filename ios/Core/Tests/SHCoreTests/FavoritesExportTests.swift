import XCTest
@testable import SHCore

/// 错题本导出测试：这份文本是给家长打印用的，格式错乱就白导了。
final class FavoritesExportTests: XCTestCase {

    private func item(_ subject: String, _ q: String, _ a: String, at: Int = 1_000) -> FavoritesExport.Item {
        FavoritesExport.Item(subject: subject, question: q, answer: a, createdAt: at)
    }

    func test空错题本给出明确提示() {
        let out = FavoritesExport.render(items: [])
        XCTAssertTrue(out.contains("错题本是空的"), out)
    }

    func test按学科分组且顺序固定() {
        let out = FavoritesExport.render(items: [
            item("english", "He go to school", "goes"),
            item("math", "3/4 + 1/8 = ?", "7/8"),
            item("chinese", "忽然造句", "忽然下雨了。"),
        ])
        let mathRange = out.range(of: "【数学】")
        let chineseRange = out.range(of: "【语文】")
        let englishRange = out.range(of: "【英语】")
        XCTAssertNotNil(mathRange)
        XCTAssertNotNil(chineseRange)
        XCTAssertNotNil(englishRange)
        // 语文在前、数学其次、英语最后
        XCTAssertLessThan(chineseRange!.lowerBound, mathRange!.lowerBound)
        XCTAssertLessThan(mathRange!.lowerBound, englishRange!.lowerBound)
    }

    func testLaTeX被降级成可读文本() {
        let out = FavoritesExport.render(items: [
            item("math", "计算 \\( \\frac{3}{4} \\)", "答：\\( \\frac{3}{4} \\)")
        ])
        XCTAssertFalse(out.contains("\\frac"), "打印出来不该有 LaTeX 命令：\(out)")
        XCTAssertTrue(out.contains("(3)/(4)"), out)
    }

    func test题目编号连续() {
        let out = FavoritesExport.render(items: [
            item("math", "题一", "答一", at: 1),
            item("math", "题二", "答二", at: 2),
            item("math", "题三", "答三", at: 3),
        ])
        XCTAssertTrue(out.contains("1. 题一"), out)
        XCTAssertTrue(out.contains("2. 题二"), out)
        XCTAssertTrue(out.contains("3. 题三"), out)
    }

    func test同科内按时间正序() {
        let out = FavoritesExport.render(items: [
            item("math", "后收的", "A", at: 5_000),
            item("math", "先收的", "B", at: 1_000),
        ])
        XCTAssertLessThan(
            out.range(of: "先收的")!.lowerBound,
            out.range(of: "后收的")!.lowerBound
        )
    }

    func test空题目有占位不塌行() {
        let out = FavoritesExport.render(items: [item("math", "   ", "  ")])
        XCTAssertTrue(out.contains("（空）"), out)
    }

    func test含总数与导出时间() {
        let out = FavoritesExport.render(items: [item("math", "题", "答")])
        XCTAssertTrue(out.contains("共 1 题"), out)
        XCTAssertTrue(out.contains("导出时间"), out)
    }
}
