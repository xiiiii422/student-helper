import Foundation

/// 学习统计：从本地消息里算出来的纯数据，不做任何 UI。
///
/// 放 Core 是因为这些口径（按天分桶、连续天数、只数 user 提问）很容易算错，
/// 必须能在不启动模拟器的情况下用单测锁住。
public enum StudyStats {

    public struct DayCount: Equatable {
        /// yyyy-MM-dd
        public let day: String
        public let questions: Int
        public init(day: String, questions: Int) {
            self.day = day
            self.questions = questions
        }
    }

    public struct Summary: Equatable {
        public var totalQuestions: Int = 0
        public var totalAnswers: Int = 0
        /// 学科 -> 提问数
        public var bySubject: [String: Int] = [:]
        /// 最近 7 天（含今天）的每日提问数，缺失的天补 0，保证柱状图对齐
        public var last7Days: [DayCount] = []
        /// 连续学习天数：从今天（或昨天）往前数，中间断一天就断
        public var streakDays: Int = 0
        /// 有学习记录的天数
        public var activeDays: Int = 0
        /// 提问最多的学科，空库时为 nil
        public var topSubject: String? {
            bySubject.max { $0.value < $1.value }?.key
        }

        public init() {}
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 只数 role == "user" 的提问；作文不计入（那是另一条线）。
    public static func summarize(
        messages: [Message],
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> Summary {
        var s = Summary()
        var dayCounts: [String: Int] = [:]

        for m in messages {
            if m.role == "user" {
                s.totalQuestions += 1
                s.bySubject[m.subject, default: 0] += 1
                let date = Date(timeIntervalSince1970: Double(m.createdAt) / 1000)
                dayCounts[dayFormatter.string(from: date), default: 0] += 1
            } else if m.role == "assistant",
                      !m.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s.totalAnswers += 1
            }
        }
        s.activeDays = dayCounts.count

        // 最近 7 天：从今天往回数 6 天，每天一个桶，没数据的日子补 0
        var last7: [DayCount] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let dayDate = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = dayFormatter.string(from: dayDate)
            last7.append(DayCount(day: key, questions: dayCounts[key] ?? 0))
        }
        s.last7Days = last7

        // 连续天数：今天没学但从昨天开始也算，今天完全没学则从昨天往前数
        var streak = 0
        var cursor = now
        if dayCounts[dayFormatter.string(from: cursor)] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
                return s
            }
            cursor = yesterday
            guard dayCounts[dayFormatter.string(from: cursor)] != nil else { return s }
        }
        while dayCounts[dayFormatter.string(from: cursor)] != nil {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        s.streakDays = streak
        return s
    }
}
