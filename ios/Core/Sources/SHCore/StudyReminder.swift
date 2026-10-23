import Foundation

/// 学习提醒的文案。抽成纯函数：iOS 与安卓各自只会生成这几条轮换文案，
/// 单测能直接锁住「第几天对应哪条」，不会哪天被改坏。
public enum StudyReminder {

    /// 给某一天的提醒选一句文案。day 从 1 开始（第 1 天、第 2 天…）。
    /// 文案按数组下标轮换，超出长度就循环。
    public static func message(forDay day: Int) -> String {
        let lines = [
            "今天有题目还没弄懂吗？打开小助手，把不会的题讲一遍吧。",
            "坚持每天一题，比周末突击三小时更有用。现在就来做一道？",
            "错题本里还有没复习的题，点开小助手，花十分钟过一遍。",
            "语文、数学、英语，今天想先攻克哪一科？小助手随时在。",
            "学习像跑步，停一天没事，停一周就难捡回来。来一题热热身。",
        ]
        guard day > 0 else { return lines[0] }
        return lines[(day - 1) % lines.count]
    }

    /// 提醒标题。固定，方便家长在通知栏一眼认出是本 App。
    public static let title = "学习小助手 · 每日提醒"

    /// 通知请求的固定 identifier：每天重排时直接 replace，不会越排越多。
    public static let requestIdentifier = "daily-study-reminder"
}
