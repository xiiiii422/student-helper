import XCTest
@testable import SHCore

/// 错题本自测（掌握状态）的纯逻辑测试。
/// 最关键的是旧数据兼容：升级前存的库、安卓导来的备份都没有 review_state 这个键，
/// 一旦因此解码失败，用户会看到「所有数据凭空消失」，这是灾难级 bug。
final class ReviewStateTests: XCTestCase {

    private func makeStore() -> (AppStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-test-\(UUID().uuidString).json")
        return (AppStore(fileURL: url), url)
    }

    func test收藏后可记录掌握状态() throws {
        let (store, _) = makeStore()
        let q = store.insert(Message(subject: "math", role: "user", textContent: "3/4+1/8"))
        let a = store.insert(Message(subject: "math", role: "assistant", textContent: "7/8"))
        _ = q
        XCTAssertNotNil(store.toggleFavorite(messageId: a.id))
        XCTAssertTrue(store.setReviewed(messageId: a.id, mastered: true))
        let fav = store.favorites(subject: nil).first
        XCTAssertEqual(fav?.reviewState, "mastered")
    }

    func test不会的题标记为再做() throws {
        let (store, _) = makeStore()
        let a = store.insert(Message(subject: "math", role: "assistant", textContent: "答"))
        _ = store.toggleFavorite(messageId: a.id)
        store.setReviewed(messageId: a.id, mastered: false)
        XCTAssertEqual(store.favorites(subject: nil).first?.reviewState, "again")
    }

    func test未自测的收藏状态为nil() throws {
        let (store, _) = makeStore()
        let a = store.insert(Message(subject: "math", role: "assistant", textContent: "答"))
        _ = store.toggleFavorite(messageId: a.id)
        XCTAssertNil(store.favorites(subject: nil).first?.reviewState)
    }

    func test给不存在的收藏打状态返回false() throws {
        let (store, _) = makeStore()
        XCTAssertFalse(store.setReviewed(messageId: 99_999, mastered: true))
    }

    func test掌握计数分三类() throws {
        let (store, _) = makeStore()
        let m1 = store.insert(Message(subject: "math", role: "assistant", textContent: "a1"))
        let m2 = store.insert(Message(subject: "math", role: "assistant", textContent: "a2"))
        let m3 = store.insert(Message(subject: "math", role: "assistant", textContent: "a3"))
        for m in [m1, m2, m3] { _ = store.toggleFavorite(messageId: m.id) }
        store.setReviewed(messageId: m1.id, mastered: true)
        store.setReviewed(messageId: m2.id, mastered: false)
        let counts = store.reviewCounts(subject: nil)
        XCTAssertEqual(counts.mastered, 1)
        XCTAssertEqual(counts.again, 1)
        XCTAssertEqual(counts.untested, 1)
    }

    // MARK: 旧数据兼容

    func test缺reviewState键的旧库能解码() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-\(UUID().uuidString).json")
        // 手工拼一份「旧版本」写出的 JSON：favorites 里没有 review_state
        let legacy = """
        {"messages":[{"id":1,"subject":"math","role":"assistant","textContent":"答","isStreaming":false,"created_at":1700000000000}],
         "compositions":[],
         "favorites":[{"id":1,"message_id":1,"subject":"math","note":"","created_at":1700000000000}]}
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)
        let store = AppStore(fileURL: url)
        XCTAssertTrue(store.didLoadExistingData, "旧库必须能读出来，不能当空库")
        XCTAssertEqual(store.favorites(subject: nil).count, 1)
        XCTAssertNil(store.favorites(subject: nil).first?.reviewState)
    }

    func test安卓导来的无note字段也能解码() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-\(UUID().uuidString).json")
        // 安卓 Favorite 表可能没有 note，也没有 review_state
        let payload = """
        {"messages":[],
         "compositions":[],
         "favorites":[{"id":1,"message_id":7,"subject":"chinese","created_at":1700000000000}]}
        """
        try payload.write(to: url, atomically: true, encoding: .utf8)
        let store = AppStore(fileURL: url)
        XCTAssertTrue(store.didLoadExistingData)
        XCTAssertEqual(store.favorites(subject: nil).first?.note, "")
    }

    func test掌握状态会落盘并在重开后保留() throws {
        let (store, url) = makeStore()
        let a = store.insert(Message(subject: "math", role: "assistant", textContent: "答"))
        _ = store.toggleFavorite(messageId: a.id)
        store.setReviewed(messageId: a.id, mastered: true)
        let reopened = AppStore(fileURL: url)
        XCTAssertEqual(reopened.favorites(subject: nil).first?.reviewState, "mastered")
    }

    func test删掉原消息后掌握计数不再统计它() throws {
        let (store, _) = makeStore()
        let a = store.insert(Message(subject: "math", role: "assistant", textContent: "答"))
        _ = store.toggleFavorite(messageId: a.id)
        store.setReviewed(messageId: a.id, mastered: true)
        store.deleteMessage(id: a.id)   // 收藏行随外键级联删除
        let counts = store.reviewCounts(subject: nil)
        XCTAssertEqual(counts.mastered, 0)
    }
}
