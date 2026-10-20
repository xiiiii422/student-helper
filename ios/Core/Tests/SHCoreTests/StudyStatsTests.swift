import XCTest
@testable import SHCore

/// 学习统计与搜索的纯逻辑测试。这两个都是「算错一天/漏一条就全错」的东西，
/// 必须靠测试而不是靠肉眼看界面。
final class StudyStatsTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func msg(_ subject: String, _ role: String, text: String = "题", dayOffset: Int, now: Date) -> Message {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: now)!
        return Message(
            subject: subject, role: role, textContent: text,
            createdAt: Int(date.timeIntervalSince1970 * 1000)
        )
    }

    func test只数提问不数回答() {
        let now = Date()
        let messages = [
            msg("math", "user", dayOffset: 0, now: now),
            msg("math", "assistant", dayOffset: 0, now: now),
            msg("math", "assistant", text: "", dayOffset: 0, now: now),
        ]
        let s = StudyStats.summarize(messages: messages, now: now, calendar: calendar)
        XCTAssertEqual(s.totalQuestions, 1)
        // 空回答不算数
        XCTAssertEqual(s.totalAnswers, 1)
    }

    func test按学科汇总() {
        let now = Date()
        let messages = [
            msg("math", "user", dayOffset: 0, now: now),
            msg("math", "user", dayOffset: 0, now: now),
            msg("chinese", "user", dayOffset: 0, now: now),
        ]
        let s = StudyStats.summarize(messages: messages, now: now, calendar: calendar)
        XCTAssertEqual(s.bySubject["math"], 2)
        XCTAssertEqual(s.bySubject["chinese"], 1)
        XCTAssertEqual(s.topSubject, "math")
    }

    func test最近七天必须补齐空白天() {
        let now = Date()
        let messages = [msg("math", "user", dayOffset: -3, now: now)]
        let s = StudyStats.summarize(messages: messages, now: now, calendar: calendar)
        XCTAssertEqual(s.last7Days.count, 7)
        XCTAssertEqual(s.last7Days.last?.questions, 0)
        XCTAssertEqual(s.last7Days.reduce(0) { $0 + $1.questions }, 1)
    }

    func test连续天数从今天往前数() {
        let now = Date()
        let messages = [
            msg("math", "user", dayOffset: 0, now: now),
            msg("math", "user", dayOffset: -1, now: now),
            msg("math", "user", dayOffset: -2, now: now),
            // 第 3 天空着，第 4 天有——不能算进连续
            msg("math", "user", dayOffset: -4, now: now),
        ]
        let s = StudyStats.summarize(messages: messages, now: now, calendar: calendar)
        XCTAssertEqual(s.streakDays, 3)
    }

    func test今天没学但昨天学了连续从昨天起算() {
        let now = Date()
        let messages = [
            msg("math", "user", dayOffset: -1, now: now),
            msg("math", "user", dayOffset: -2, now: now),
        ]
        let s = StudyStats.summarize(messages: messages, now: now, calendar: calendar)
        XCTAssertEqual(s.streakDays, 2)
    }

    func test断在昨天之前连续为零() {
        let now = Date()
        let messages = [msg("math", "user", dayOffset: -3, now: now)]
        let s = StudyStats.summarize(messages: messages, now: now, calendar: calendar)
        XCTAssertEqual(s.streakDays, 0)
    }

    func test空库不崩() {
        let now = Date()
        let s = StudyStats.summarize(messages: [], now: now, calendar: calendar)
        XCTAssertEqual(s.totalQuestions, 0)
        XCTAssertNil(s.topSubject)
        XCTAssertEqual(s.last7Days.count, 7)
    }

    // MARK: 搜索

    private func makeStore() -> AppStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-test-\(UUID().uuidString).json")
        return AppStore(fileURL: url)
    }

    func test搜索命中提问正文() throws {
        let store = makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "一个圆的半径是3cm"))
        store.insert(Message(subject: "chinese", role: "user", textContent: "用忽然造句"))
        let hits = store.searchMessages(query: "圆")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.subject, "math")
    }

    func test搜索大小写不敏感() throws {
        let store = makeStore()
        store.insert(Message(subject: "english", role: "user", textContent: "He GOES to school"))
        XCTAssertEqual(store.searchMessages(query: "goes").count, 1)
    }

    func test空查询返回空而不是全量() throws {
        let store = makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "题"))
        XCTAssertTrue(store.searchMessages(query: "   ").isEmpty)
    }

    func test搜索可按学科过滤() throws {
        let store = makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "分数加法"))
        store.insert(Message(subject: "chinese", role: "user", textContent: "分数" as String))
        XCTAssertEqual(store.searchMessages(query: "分数").count, 2)
        XCTAssertEqual(store.searchMessages(query: "分数", subject: "math").count, 1)
        let counts = store.searchSubjectCounts(query: "分数")
        XCTAssertEqual(counts["math"], 1)
        XCTAssertEqual(counts["chinese"], 1)
    }

    func test搜索按时间倒序() throws {
        let store = makeStore()
        store.insert(Message(subject: "math", role: "user", textContent: "圆 早", createdAt: 1_000))
        store.insert(Message(subject: "math", role: "user", textContent: "圆 晚", createdAt: 9_000))
        let hits = store.searchMessages(query: "圆")
        XCTAssertEqual(hits.first?.textContent, "圆 晚")
    }
}
