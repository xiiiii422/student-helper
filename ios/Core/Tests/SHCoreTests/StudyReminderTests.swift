import XCTest
@testable import SHCore

/// 学习提醒文案与配置测试。
final class StudyReminderTests: XCTestCase {

    func test文案按天轮换且不越界() {
        let day1 = StudyReminder.message(forDay: 1)
        let day2 = StudyReminder.message(forDay: 2)
        XCTAssertNotEqual(day1, day2, "相邻两天文案应该不同")

        // 超出数组长度要循环，不能崩、不能出空串
        let wrapped = StudyReminder.message(forDay: 6)
        XCTAssertFalse(wrapped.isEmpty)
        XCTAssertEqual(wrapped, StudyReminder.message(forDay: 1), "第6天应循环回第1条")

        XCTAssertEqual(StudyReminder.message(forDay: 10), StudyReminder.message(forDay: 5))
    }

    func test非法天数回退首条() {
        XCTAssertEqual(StudyReminder.message(forDay: 0), StudyReminder.message(forDay: 1))
        XCTAssertEqual(StudyReminder.message(forDay: -3), StudyReminder.message(forDay: 1))
    }

    func test标题固定() {
        XCTAssertFalse(StudyReminder.title.isEmpty)
        XCTAssertTrue(StudyReminder.title.contains("学习小助手"))
    }

    func test通知Identifier固定() {
        // 每天重排靠同一个 identifier replace，不能变
        XCTAssertEqual(StudyReminder.requestIdentifier, "daily-study-reminder")
    }

    // 配置默认值：用独立 UserDefaults 套件，避免污染真实设置
    func test默认提醒时间() {
        let s = SettingsStore(defaults: UserDefaults(suiteName: "test.reminder.\(UUID())")!)
        XCTAssertFalse(s.reminderOn, "默认不开启，不能一上来弹授权")
        XCTAssertEqual(s.reminderHour, 19)
        XCTAssertEqual(s.reminderMinute, 30)
        XCTAssertEqual(s.reminderDay, 1)
    }

    func test开启后写回() {
        let s = SettingsStore(defaults: UserDefaults(suiteName: "test.reminder.\(UUID())")!)
        s.reminderOn = true
        s.reminderHour = 8
        s.reminderMinute = 5
        s.reminderDay = 4
        XCTAssertTrue(s.reminderOn)
        XCTAssertEqual(s.reminderHour, 8)
        XCTAssertEqual(s.reminderMinute, 5)
        XCTAssertEqual(s.reminderDay, 4)
        XCTAssertEqual(s.reminderComponents.hour, 8)
        XCTAssertEqual(s.reminderComponents.minute, 5)
    }
}
