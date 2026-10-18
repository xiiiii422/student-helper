import XCTest
@testable import SHCore

/// OCR 路由决策测试：覆盖「置信度 × 学科 × 公式特征」矩阵。
/// 与安卓 `OcrRouterTest.kt` 一一对应，两端规则必须同步。
final class OcrRouterTests: XCTestCase {

    private func mode(_ text: String, _ confidence: Double, _ subject: String) -> OcrMode {
        OcrRouter.decide(text: text, confidence: confidence, subject: subject)
    }

    func test高置信度普通文本走纯文字() {
        XCTAssertEqual(mode("小明有5个苹果，吃了2个还剩几个", 0.95, "math"), .textOnly)
        XCTAssertEqual(mode("请用“忽然”造一个句子", 0.92, "chinese"), .textOnly)
        XCTAssertEqual(mode("apple 是什么意思", 0.99, "english"), .textOnly)
    }

    func test高置信度但含数学算式仍走图文兜底() {
        XCTAssertEqual(mode("计算 3/4 + 1/8 的值", 0.95, "math"), .textAndImage)
        XCTAssertEqual(mode("12 + 7 =", 0.97, "math"), .textAndImage)
        XCTAssertEqual(mode("求这个△的面积", 0.99, "math"), .textAndImage)
    }

    func test数学题有效字符过少走图文兜底() {
        XCTAssertEqual(mode("5 × 3", 0.99, "math"), .textAndImage)
    }

    func test非数学学科不触发公式与稀疏规则() {
        // 语文题里出现 "/" 或短文本，仍按置信度判断
        XCTAssertEqual(mode("3/4", 0.95, "chinese"), .textOnly)
    }

    func test语文多行阅读版式强制带图() {
        let passage = """
        春天的花园里开满了桃花。
        小明说：春天真美。
        请回答：这段话写的是什么季节？
        为什么小明觉得春天美？
        """
        XCTAssertEqual(mode(passage, 0.97, "chinese"), .textAndImage)
    }

    func test英语多行阅读同样强制带图() {
        let passage = """
        Tom gets up at six.
        He has breakfast at seven.
        Question: What time does Tom get up?
        Answer it.
        """
        XCTAssertEqual(mode(passage, 0.95, "english"), .textAndImage)
    }

    func test数学多行短题干不受阅读版式规则影响() {
        // 数学多行算式：命中公式特征走图文；不会因为行数多而被误判成阅读题
        let text = """
        3/4 + 1/8 =
        1/2 × 6 =
        5/6 - 1/3 =
        """
        XCTAssertEqual(mode(text, 0.95, "math"), .textAndImage)
    }

    func test低置信度一律只发图() {
        XCTAssertEqual(mode("乱码一样的结果", 0.42, "math"), .imageOnly)
        XCTAssertEqual(mode("", 0.0, "english"), .imageOnly)
        XCTAssertEqual(mode("t h e e", 0.55, "english"), .imageOnly)
    }

    func test边界值() {
        // 恰好 0.90 且是干净文本 → 纯文字
        XCTAssertEqual(mode("let us go to the park together", 0.90, "english"), .textOnly)
        // 0.89 掉到图文档
        XCTAssertEqual(mode("let us go to the park together", 0.89, "english"), .textAndImage)
        // 恰好 0.60 → 图文，低于则只发图
        XCTAssertEqual(mode("some text here for testing", 0.60, "english"), .textAndImage)
        XCTAssertEqual(mode("some text here for testing", 0.59, "english"), .imageOnly)
    }
}
