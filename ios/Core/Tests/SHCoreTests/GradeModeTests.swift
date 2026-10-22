import XCTest
@testable import SHCore

/// 「批改我的作答」意图的持久化测试。
///
/// 这个开关以前只活在请求参数里，没落到消息上：
/// 学生勾了批改 → 发送失败点重试（或重新生成）→ 意图丢失，悄悄退回普通讲题。
/// 用户完全不会意识到「我明明选了批改」。
final class GradeModeTests: XCTestCase {

    private func makeStore() -> (AppStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("grade-\(UUID().uuidString).json")
        return (AppStore(fileURL: url), url)
    }

    func test提问可带批改标记() throws {
        let (store, _) = makeStore()
        let m = store.insert(Message(
            subject: "math", role: "user", textContent: "这题我做对了没", gradeMode: true
        ))
        XCTAssertEqual(store.messages(subject: "math").first?.gradeMode, true)
        XCTAssertEqual(m.gradeMode, true)
    }

    func test普通提问不写标记() throws {
        let (store, _) = makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "这题怎么做"))
        XCTAssertNil(store.messages(subject: "math").first?.gradeMode)
    }

    func test批改标记能落盘并在重开后保留() throws {
        let (store, url) = makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "帮我批改", gradeMode: true))
        let reopened = AppStore(fileURL: url)
        XCTAssertEqual(reopened.messages(subject: "math").first?.gradeMode, true)
    }

    // MARK: 旧数据兼容

    func test缺gradeMode键的旧库能解码() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-grade-\(UUID().uuidString).json")
        let legacy = """
        {"messages":[{"id":1,"subject":"math","role":"user","textContent":"旧提问","isStreaming":false,"created_at":1700000000000}],
         "compositions":[],
         "favorites":[]}
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)
        let store = AppStore(fileURL: url)
        XCTAssertTrue(store.didLoadExistingData, "旧库必须能读出来")
        XCTAssertEqual(store.messages(subject: "math").count, 1)
        XCTAssertNil(store.messages(subject: "math").first?.gradeMode)
    }

    func test安卓备份缺isStreaming也能解码() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-grade-\(UUID().uuidString).json")
        // 安卓可能不带 isStreaming，也不带 grade_mode
        let payload = """
        {"messages":[{"id":1,"subject":"chinese","role":"assistant","textContent":"答","created_at":1700000000000}],
         "compositions":[],
         "favorites":[]}
        """
        try payload.write(to: url, atomically: true, encoding: .utf8)
        let store = AppStore(fileURL: url)
        XCTAssertTrue(store.didLoadExistingData)
        XCTAssertFalse(store.messages(subject: "chinese").first?.isStreaming ?? true)
    }
}
