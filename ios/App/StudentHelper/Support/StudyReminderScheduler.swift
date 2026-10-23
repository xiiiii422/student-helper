import Foundation
import UserNotifications
import SHCore

/// 学习提醒调度：每天定时弹一条本地通知，落到 App 打开「我的」页。
///
/// 为什么用本地通知而不是后端推送：自用版没有服务器，本地 UNNotification
/// 是零成本、零隐私泄露、关了 App 也能响的最稳方案。
///
/// 关键细节（都是真机踩坑点）：
/// - 必须在主线程调度 UNUserNotificationCenter（内部有主线程断言）
/// - 通知可能未授权：申请被拒时调度应直接放弃，不能崩
/// - 每天用同一个 request identifier 重排，replace 而非 add，避免重复堆叠
/// - iOS 自签 7 天过期后通知会被系统清掉，这是预期内的，不专门处理
enum StudyReminderScheduler {

    private static let center = UNUserNotificationCenter.current()

    /// 当前通知授权状态（用于设置页判断要不要提示去系统设置开）。
    static func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    /// 申请通知授权。用户同意后才真正能弹，拒绝则由调用方提示去系统设置。
    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion(granted)
        }
    }

    /// 重新排程：根据 settings 里的开关与时间，在主线程创建/替换每日通知。
    /// 关闭时调用会移除现有通知（用户关了就要彻底安静）。
    @MainActor
    static func reschedule(_ settings: SettingsStore) {
        if !settings.reminderOn {
            center.removePendingNotificationRequests(withIdentifiers: [StudyReminder.requestIdentifier])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = StudyReminder.title
        // 文案按「开启第几天」轮换：用存盘时写下的 day，而不是实时算，
        // 否则调一次时间就跳一条文案，家长会觉得文案乱跳。
        content.body = StudyReminder.message(forDay: settings.reminderDay)
        content.sound = .default
        content.userInfo = ["route": "me"]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: settings.reminderComponents, repeats: true
        )
        let request = UNNotificationRequest(
            identifier: StudyReminder.requestIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error { print("[Reminder] 排程失败: \(error.localizedDescription)") }
        }
    }

    /// 用户从通知点进来：由 AppDelegate 的 UNUserNotificationCenterDelegate 转交，
    /// 这里只负责把「想去我的页」的意图交给容器（复用既有的 pendingRoute 机制）。
    static func handleLaunch(from response: UNNotificationResponse) {
        guard response.notification.request.identifier == StudyReminder.requestIdentifier else { return }
        NotificationCenter.default.post(name: .studyReminderTapped, object: nil)
    }
}

extension Notification.Name {
    static let studyReminderTapped = Notification.Name("studyReminderTapped")
}
