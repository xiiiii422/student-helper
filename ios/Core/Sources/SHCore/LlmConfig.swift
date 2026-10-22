import Foundation

/// 运行时直连大模型配置。
///
/// 与安卓的差别只有一处刻意为之：**这里不带任何 Key 字段默认值**。
/// 安卓把 Key 硬编码进了源码（自用版省事，但仓库一旦推上 GitHub 就永久进 git 历史）。
/// iOS 侧 Key 由 App 层从 Keychain / xcconfig 注入，Core 层保持零密钥，可单测可公开。
public struct LlmConfig: Equatable {

    public struct Channel: Equatable {
        public let model: String
        public let maxTokens: Int
        public init(model: String, maxTokens: Int) {
            self.model = model
            self.maxTokens = maxTokens
        }
    }

    public let providerId: String
    public let baseUrl: String
    public let apiKey: String
    public let chatModel: String
    public let vlModel: String
    public let chatMaxTokens: Int
    public let vlMaxTokens: Int
    /// true 时请求体里带 `thinking: {type: disabled}`，否则对端会先“想”几分钟不吐正文。
    public let disableThinking: Bool

    public init(
        providerId: String,
        baseUrl: String,
        apiKey: String,
        chatModel: String,
        vlModel: String,
        chatMaxTokens: Int,
        vlMaxTokens: Int,
        disableThinking: Bool = false
    ) {
        self.providerId = providerId
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.chatModel = chatModel
        self.vlModel = vlModel
        self.chatMaxTokens = chatMaxTokens
        self.vlMaxTokens = vlMaxTokens
        self.disableThinking = disableThinking
    }

    /// 按有没有图选模型通道。
    ///
    /// 视觉模型为空时回退到对话模型：自定义服务只填了 chat 模型、没填视觉模型是常见情况，
    /// 以前会拿空模型名去发请求，供应商返回 400，而这个状态码不在重试列表里——
    /// 学生看到的就是「拍照问了没反应」，完全不知道是自己少填了一个字段。
    /// 回退到对话模型至少能给出回答（多数服务现在 chat 模型也支持图片），
    /// 比直接失败有用得多。
    public func channel(hasImage: Bool) -> Channel {
        guard hasImage else {
            return Channel(model: chatModel, maxTokens: chatMaxTokens)
        }
        let useVL = !vlModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Channel(
            model: useVL ? vlModel : chatModel,
            maxTokens: useVL ? vlMaxTokens : chatMaxTokens
        )
    }

    public var endpoint: String { baseUrl + "/chat/completions" }
}

/// 大模型供应商预设：切换后 base/model 自动覆盖，仅需保留对应 Key。
public struct ProviderPreset: Equatable {
    public let id: String
    public let label: String
    /// 列表行右侧状态位用，全名（“智谱 GLM 免费”）塞不进去。
    public let short: String
    public let baseUrl: String
    public let chatModel: String
    public let vlModel: String
    public let vlMaxTokens: Int
    public let chatMaxTokens: Int
    /// 关掉“思考模式”。两家 flash 都是混合推理模型且默认开着思考，
    /// 实测不关时 SSE 只吐 reasoning_content、content 全空，App 把它丢了就变成“问了没人答”几分钟。
    /// 自定义服务无从推断参数是否兼容，一律不送。
    public let disableThinking: Bool

    public init(
        id: String, label: String, short: String, baseUrl: String,
        chatModel: String, vlModel: String,
        vlMaxTokens: Int, chatMaxTokens: Int, disableThinking: Bool = false
    ) {
        self.id = id
        self.label = label
        self.short = short
        self.baseUrl = baseUrl
        self.chatModel = chatModel
        self.vlModel = vlModel
        self.vlMaxTokens = vlMaxTokens
        self.chatMaxTokens = chatMaxTokens
        self.disableThinking = disableThinking
    }
}

public enum Presets {

    public static let glm = ProviderPreset(
        id: "glm", label: "智谱 GLM 免费", short: "智谱",
        baseUrl: "https://open.bigmodel.cn/api/paas/v4",
        chatModel: "glm-4.7-flash", vlModel: "glm-4v-flash",
        vlMaxTokens: 1024, chatMaxTokens: 4000,
        disableThinking: true
    )

    public static let deepseek = ProviderPreset(
        id: "deepseek", label: "DeepSeek", short: "DeepSeek",
        baseUrl: "https://api.deepseek.com",
        chatModel: "deepseek-flash", vlModel: "deepseek-flash",
        vlMaxTokens: 4000, chatMaxTokens: 4000,
        disableThinking: true
    )

    public static let all: [ProviderPreset] = [glm, deepseek]

    /// 给人看的供应商名（限流切换时要告诉学生现在换成谁了）。
    public static func label(of id: String) -> String {
        all.first { $0.id == id }?.label ?? "当前服务"
    }

    public static func short(of id: String) -> String {
        all.first { $0.id == id }?.short ?? "当前"
    }

    public static func preset(of id: String?) -> ProviderPreset {
        all.first { $0.id == id } ?? glm
    }

    /// 备用供应商：主家被限流时自动切过去。
    /// 免费档的 RPM 限制不是退避几十秒能跨过去的，自用版唯一可靠的兜底就是第 2 家 Key。
    /// 自定义配置无从推断 Key，返回 nil；主备地址相同也没必要切。
    public static func fallbackPreset(for cfg: LlmConfig) -> ProviderPreset? {
        let other: ProviderPreset
        switch cfg.providerId {
        case "glm": other = deepseek
        case "deepseek": other = glm
        default: return nil
        }
        if trimmedBase(other.baseUrl) == trimmedBase(cfg.baseUrl) { return nil }
        return other
    }

    private static func trimmedBase(_ url: String) -> String {
        var s = url
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
