import Foundation

/// 重试 / 超时 / 限流判定 / 错误文案，全部纯函数，对齐安卓 `core/network/LlmClient.kt` 顶部的常量
/// 与 `ChatViewModel.friendlyError`。这些规则每一条都对应一次真机踩坑，改动前先看注释。
public enum LlmPolicy {

    public static let retryStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    /// 主家只给两次机会：免费档的 1305 不是退避几次能跨过去的，死磕不如换人。
    public static let maxRetries = 2
    /// 备用供应商同样两次：主家都限流了，备用大概率也忙，不要让学生等太久。
    public static let fallbackRetries = 2

    /// 单次尝试等首个字词的上限。对端过载时会先接受请求、持续发 keepalive，
    /// 连接不断但正文一行没有，readTimeout 永远不触发（安卓真机实测挂 200s+）；只能拿墙钟自己卡。
    public static let firstTokenBudgetSeconds = 40
    /// 思考关掉后正文是一直接着来的，真断流就是死了；给到 180s 会让一次卡住挂三分钟。
    public static let readTimeoutSeconds = 60
    public static let connectTimeoutSeconds = 30

    /// 指数退避：2^attempt 秒，15s 封顶。
    public static func backoffSeconds(attempt: Int) -> Int {
        min(1 << attempt, 15)
    }

    /// 上游在 SSE 流里回的错误对象是不是“忙”（值得重试），而不是“错了”（该直接告诉用户）。
    public static func isBusy(_ text: String) -> Bool {
        text.contains("1302") || text.contains("1305") || text.contains("拥塞")
            || text.contains("速率") || text.contains("稍后再试")
            || text.lowercased().contains("rate limit") || text.contains("429")
    }

    /// 只有“对端限流”值得换供应商；鉴权/余额/断网 切了也一样错。
    public static func isRateLimited(_ message: String) -> Bool {
        message.contains("429") || message.lowercased().contains("too many") || isBusy(message)
    }

    /// 连通性检查的失败原因：上游回的是 JSON，塞进提示里学生读不懂；压成一个词，原文留给日志。
    public static func pingDetail(_ raw: String) -> String {
        let lower = raw.lowercased()
        if raw.contains("1302") || raw.contains("1305") || raw.contains("429")
            || raw.contains("访问量过大") || raw.contains("速率") || raw.contains("拥塞") {
            return "限流中"
        }
        if raw.contains("401") || raw.contains("1002") || lower.contains("apikey") || lower.contains("auth") {
            return "Key 无效"
        }
        if raw.contains("403") || raw.contains("余额") || lower.contains("insufficient") {
            return "无权限/欠费"
        }
        if lower.contains("timeout") { return "响应超时" }
        if raw.contains("Unable to resolve") || raw.contains("Failed to connect") || lower.contains("network") {
            return "本机无网络"
        }
        return String(raw.prefix(24))
    }

    /// 回答失败时给用户看的那句话（与安卓 ChatViewModel.friendlyError 同表）。
    public static func friendlyError(_ msg: String?) -> String {
        guard let msg else { return "网络异常，请重试" }
        let lower = msg.lowercased()
        if msg.contains("401") || msg.contains("403") || lower.contains("auth")
            || lower.contains("api key") || lower.contains("api密钥") {
            return "模型身份验证失败，请到“模型服务设置”检查 API Key"
        }
        if msg.contains("繁忙") || msg.contains("429") || msg.contains("1302")
            || msg.contains("1305") || msg.contains("速率") {
            return "模型服务当前繁忙（两家都已试过），点“重试”或稍后再试"
        }
        if msg.contains("超时") || lower.contains("timeout") {
            return "响应超时，点“重试”再试一次"
        }
        if msg.contains("Unable to resolve") || msg.contains("Failed to connect") || lower.contains("network") {
            return "网络连接失败，检查手机是否联网后重试"
        }
        return msg
    }

    /// 按 UTF-16 计数截断，与安卓 String.take(n) 同口径（中文一个字算 1 还是 2 会影响日志对齐）。
    public static func utf16Prefix(_ s: String, _ n: Int) -> String {
        let units = Array(s.utf16)
        guard units.count > n else { return s }
        return String(utf16CodeUnits: Array(units[0..<n]), count: n)
    }
}

/// 一家供应商的连通性结果：`detail` 成功时是模型名，失败时是原因。
public struct PingResult: Equatable {
    public let provider: String
    public let ok: Bool
    public let detail: String
    public init(provider: String, ok: Bool, detail: String) {
        self.provider = provider
        self.ok = ok
        self.detail = detail
    }
}
