// ==== AppStore.swift ====
import Foundation

/// 本地数据模型与存储，等价于安卓的 Room 三张表 + DAO。
///
/// 放在 Core 里而不是 App 里，是因为这些规则（历史只取最近 16 条、流式残留要清、
/// 删消息要级联删收藏、时间分隔超过 5 分钟才插一行）全都是可单测的纯逻辑，
/// 不该等到真机才发现写错。
///
/// 存储用单个 JSON 文件而非 SQLite：自用版数据量小（几百条），换来的是零依赖、
/// 导出导入直接拷文件，且 Windows 上也能跑测试。

// MARK: - 模型

public struct Message: Codable, Equatable, Identifiable {
    public var id: Int
    /// "chinese" / "math" / "english"
    public var subject: String
    /// "user" / "assistant"
    public var role: String
    public var textContent: String
    /// 本地图片文件 URL 字符串
    public var imageUri: String?
    public var ocrConfidence: Double?
    public var isStreaming: Bool
    /// 毫秒时间戳，与安卓 System.currentTimeMillis() 同口径
    public var createdAt: Int

    public init(
        id: Int = 0,
        subject: String,
        role: String,
        textContent: String,
        imageUri: String? = nil,
        ocrConfidence: Double? = nil,
        isStreaming: Bool = false,
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.subject = subject
        self.role = role
        self.textContent = textContent
        self.imageUri = imageUri
        self.ocrConfidence = ocrConfidence
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, role, textContent, imageUri
        case ocrConfidence
        case isStreaming
        case createdAt = "created_at"
    }
}

public struct Composition: Codable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    /// 识别后的作文文字（可编辑）
    public var content: String
    /// JSON 数组字符串（本地图片路径）
    public var imageUris: String
    /// AI 完整批改的原始 JSON；解析失败时存原文
    public var aiFeedback: String
    public var score: Int
    public var createdAt: Int

    public init(
        id: Int = 0, title: String, content: String, imageUris: String,
        aiFeedback: String, score: Int = 0,
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.imageUris = imageUris
        self.aiFeedback = aiFeedback
        self.score = score
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, imageUris, aiFeedback, score
        case createdAt = "created_at"
    }

    /// 列表卡片要展示的图片路径数组；脏数据按空处理，不让一行坏数据弄崩整页。
    public var imageUriList: [String] {
        guard let data = imageUris.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }
}

public struct Favorite: Codable, Equatable, Identifiable {
    public var id: Int
    public var messageId: Int
    public var subject: String
    public var note: String
    public var createdAt: Int

    public init(
        id: Int = 0, messageId: Int, subject: String, note: String = "",
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.messageId = messageId
        self.subject = subject
        self.note = note
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, note
        case messageId = "message_id"
        case createdAt = "created_at"
    }
}

/// 一次导出的全部本机数据（备份 zip 的内容契约，与安卓 BackupManager 对齐）。
public struct BackupSnapshot: Codable, Equatable {
    public var messages: [Message]
    public var compositions: [Composition]
    public var favorites: [Favorite]
    public init(
        messages: [Message] = [], compositions: [Composition] = [], favorites: [Favorite] = []
    ) {
        self.messages = messages
        self.compositions = compositions
        self.favorites = favorites
    }
}

// MARK: - 存储

public final class AppStore {

    private let fileURL: URL
    private let now: () -> Int
    private(set) var snapshot: BackupSnapshot

    /// App 层用它把变化广播给 SwiftUI（Core 不依赖 Combine，所以留回调而不是 ObservableObject）。
    public var onChange: (() -> Void)?

    public init(fileURL: URL, now: @escaping () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }) {
        self.fileURL = fileURL
        self.now = now
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(BackupSnapshot.self, from: data) {
            self.snapshot = decoded
        } else {
            self.snapshot = BackupSnapshot()
        }
    }

    // MARK: 读写

    @discardableResult
    public func save() -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(snapshot).write(to: fileURL, options: .atomic)
            onChange?()
            return true
        } catch {
            return false
        }
    }

    private func nextId(_ existing: [Int]) -> Int {
        (existing.max() ?? 0) + 1
    }

    // MARK: 消息

    public func messages(subject: String) -> [Message] {
        snapshot.messages.filter { $0.subject == subject }.sorted { $0.createdAt < $1.createdAt }
    }

    /// 讲题历史窗口：与安卓一样只带最近 16 条，且不含本轮这条提问。
    public func recentMessages(subject: String, limit: Int = 16) -> [Message] {
        Array(messages(subject: subject).suffix(limit))
    }

    public func historyForChat(subject: String, excludingLastUser: Bool = true) -> [Msg] {
        let recent = recentMessages(subject: subject)
        let body = excludingLastUser ? Array(recent.dropLast()) : recent
        return body.map { Msg($0.role, $0.textContent) }
    }

    @discardableResult
    public func insert(_ message: Message) -> Message {
        var m = message
        if m.id == 0 { m.id = nextId(snapshot.messages.map(\.id)) }
        snapshot.messages.append(m)
        save()
        return m
    }

    public func update(_ message: Message) {
        guard let i = snapshot.messages.firstIndex(where: { $0.id == message.id }) else { return }
        snapshot.messages[i] = message
        save()
    }

    /// 长按删除单条消息，收藏行随之外键级联移除。
    public func deleteMessage(id: Int) {
        snapshot.messages.removeAll { $0.id == id }
        snapshot.favorites.removeAll { $0.messageId == id }
        save()
    }

    /// 启动时清理流式中断残留：删空占位、把未定稿消息收尾。
    /// 进程被杀后重进，最怕留下一条永远转圈的假消息。
    public func cleanupStale(subject: String) {
        snapshot.messages.removeAll {
            $0.subject == subject && $0.isStreaming && $0.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        for i in snapshot.messages.indices where snapshot.messages[i].subject == subject && snapshot.messages[i].isStreaming {
            snapshot.messages[i].isStreaming = false
        }
        save()
    }

    public func clearSubject(_ subject: String) {
        let doomed = snapshot.messages.filter { $0.subject == subject }.map(\.id)
        snapshot.messages.removeAll { $0.subject == subject }
        snapshot.favorites.removeAll { doomed.contains($0.messageId) }
        save()
    }

    // MARK: 收藏

    public func favorites(subject: String?) -> [Favorite] {
        let rows = snapshot.favorites.filter { subject == nil || $0.subject == subject }
        return rows.sorted { $0.createdAt > $1.createdAt }
    }

    public func isFavorite(messageId: Int) -> Bool {
        snapshot.favorites.contains { $0.messageId == messageId }
    }

    /// 返回切换后的状态；找不到消息时返回 nil（不凭空造一条收藏）。
    @discardableResult
    public func toggleFavorite(messageId: Int) -> Bool? {
        if let i = snapshot.favorites.firstIndex(where: { $0.messageId == messageId }) {
            snapshot.favorites.remove(at: i)
            save()
            return false
        }
        guard let msg = snapshot.messages.first(where: { $0.id == messageId }) else { return nil }
        snapshot.favorites.append(
            Favorite(id: nextId(snapshot.favorites.map(\.id)), messageId: messageId, subject: msg.subject)
        )
        save()
        return true
    }

    /// 收藏对应的原消息；原消息被删后收藏行也应当消失，所以这里过滤即可。
    public func favoritedRows(subject: String?) -> [(favorite: Favorite, message: Message)] {
        favorites(subject: subject).compactMap { fav in
            guard let msg = snapshot.messages.first(where: { $0.id == fav.messageId }) else { return nil }
            return (fav, msg)
        }
    }

    // MARK: 作文

    public func compositions() -> [Composition] {
        snapshot.compositions.sorted { $0.createdAt > $1.createdAt }
    }

    public func composition(id: Int) -> Composition? {
        snapshot.compositions.first { $0.id == id }
    }

    @discardableResult
    public func insert(_ c: Composition) -> Composition {
        var row = c
        if row.id == 0 { row.id = nextId(snapshot.compositions.map(\.id)) }
        snapshot.compositions.append(row)
        save()
        return row
    }

    public func update(_ c: Composition) {
        guard let i = snapshot.compositions.firstIndex(where: { $0.id == c.id }) else { return }
        snapshot.compositions[i] = c
        save()
    }

    public func deleteComposition(_ c: Composition) {
        snapshot.compositions.removeAll { $0.id == c.id }
        save()
    }

    // MARK: 备份 / 清空

    public var backupSnapshot: BackupSnapshot { snapshot }

    /// 导入是整体替换：半新半旧的数据集最容易出鬼问题。
    public func replaceAll(with backup: BackupSnapshot) {
        snapshot = backup
        save()
    }

    public func clearAll() {
        snapshot = BackupSnapshot()
        save()
    }

    // MARK: 时间

    /// 时间分隔：首条或间隔超过 5 分钟才显示一行时间，与安卓 ChatScreen 同阈值。
    public static let dateGapMillis = 5 * 60 * 1000

    public static func shouldShowTimestamp(_ messages: [Message], index: Int) -> Bool {
        guard index > 0 else { return true }
        return messages[index].createdAt - messages[index - 1].createdAt > dateGapMillis
    }

    public func shouldShowTimestamp(_ messages: [Message], index: Int) -> Bool {
        Self.shouldShowTimestamp(messages, index: index)
    }
}

/// 与安卓 `DateUtils.format` 同格式：yyyy-MM-dd HH:mm。
public enum Timestamp {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    public static func format(_ millis: Int) -> String {
        formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
}

// ==== CompositionFeedback.swift ====
import Foundation

/// 作文批改的结构化结果，字段与安卓 `CompositionFeedbackDto` 一一对应（中文 JSON 键）。
///
/// 关键点：**每个字段都必须容忍缺失和类型不符**。模型经常少给一个键、
/// 或者把分数写成 "88" 这种字符串；安卓靠 kotlinx 的默认值兜住，
/// Swift 的 Codable 默认遇到缺键就整份解码失败，所以这里手写宽松解码。
public struct ScoreBreakdown: Codable, Equatable {
    public var content: Int = 0
    public var structure: Int = 0
    public var language: Int = 0
    public var writing: Int = 0

    public init() {}

    enum CodingKeys: String, CodingKey {
        case content = "内容"
        case structure = "结构"
        case language = "语言"
        case writing = "书写"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = Loose.int(c, .content) ?? 0
        structure = Loose.int(c, .structure) ?? 0
        language = Loose.int(c, .language) ?? 0
        writing = Loose.int(c, .writing) ?? 0
    }
}

public struct StrengthItem: Codable, Hashable, Identifiable {
    public var location: String = ""
    public var content: String = ""
    public var why: String = ""
    public var id: Int { hashValue }

    enum CodingKeys: String, CodingKey {
        case location = "位置"
        case content = "内容"
        case why = "为什么好"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = Loose.string(c, .location) ?? ""
        content = Loose.string(c, .content) ?? ""
        why = Loose.string(c, .why) ?? ""
    }
}

public struct IssueItem: Codable, Hashable, Identifiable {
    public var location: String = ""
    public var type: String = ""
    public var original: String = ""
    public var explanation: String = ""
    public var suggestion: String = ""
    public var id: Int { hashValue }

    enum CodingKeys: String, CodingKey {
        case location = "位置"
        case type = "类型"
        case original = "原句"
        case explanation = "问题说明"
        case suggestion = "修改建议"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = Loose.string(c, .location) ?? ""
        type = Loose.string(c, .type) ?? ""
        original = Loose.string(c, .original) ?? ""
        explanation = Loose.string(c, .explanation) ?? ""
        suggestion = Loose.string(c, .suggestion) ?? ""
    }
}

public struct RewriteItem: Codable, Hashable, Identifiable {
    public var original: String = ""
    public var rewritten: String = ""
    public var why: String = ""
    public var id: Int { hashValue }

    enum CodingKeys: String, CodingKey {
        case original = "原句"
        case rewritten = "改写"
        case why = "为什么更好"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        original = Loose.string(c, .original) ?? ""
        rewritten = Loose.string(c, .rewritten) ?? ""
        why = Loose.string(c, .why) ?? ""
    }
}

public struct CompositionFeedback: Codable, Equatable {
    public var totalScore: Int = 0
    public var breakdown = ScoreBreakdown()
    public var summary: String = ""
    public var strengths: [StrengthItem] = []
    public var issues: [IssueItem] = []
    public var suggestions: [String] = []
    public var rewrites: [RewriteItem] = []
    public var sample: String = ""

    enum CodingKeys: String, CodingKey {
        case totalScore = "总分"
        case breakdown = "分项"
        case summary = "总评"
        case strengths = "优点"
        case issues = "问题"
        case suggestions = "改进建议"
        case rewrites = "好句升级"
        case sample = "同类范文片段"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalScore = Loose.int(c, .totalScore) ?? 0
        breakdown = Loose.value(c, .breakdown) ?? ScoreBreakdown()
        summary = Loose.string(c, .summary) ?? ""
        strengths = Loose.value(c, .strengths) ?? []
        issues = Loose.value(c, .issues) ?? []
        suggestions = Loose.strings(c, .suggestions) ?? []
        rewrites = Loose.value(c, .rewrites) ?? []
        sample = Loose.string(c, .sample) ?? ""
    }

    /// 分项合计，用于校验模型给的总分是否自相矛盾（真机上出现过总分 90、分项合计 62）。
    public var breakdownTotal: Int {
        breakdown.content + breakdown.structure + breakdown.language + breakdown.writing
    }
}

// MARK: - 宽松取值

/// 模型输出的类型经常飘：分数写成字符串、数组写成单个对象。这里统一「能捞到就捞，捞不到给默认」。
enum Loose {

    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let v = try? c.decode(Int.self, forKey: key) { return v }
        if let v = try? c.decode(Double.self, forKey: key) { return Int(v.rounded()) }
        if let s = try? c.decode(String.self, forKey: key) {
            let digits = s.filter { $0.isNumber || $0 == "-" }
            return Int(digits)
        }
        return nil
    }

    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let v = try? c.decode(String.self, forKey: key) { return v }
        if let v = try? c.decode(Int.self, forKey: key) { return String(v) }
        if let v = try? c.decode(Double.self, forKey: key) { return String(v) }
        if let v = try? c.decode(Bool.self, forKey: key) { return v ? "是" : "否" }
        return nil
    }

    static func value<T: Decodable, K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> T? {
        try? c.decode(T.self, forKey: key)
    }

    /// 字符串数组专用：模型偶尔把一条建议写成对象，这里退化成取它的所有字符串值。
    static func strings<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String]? {
        if let v = try? c.decode([String].self, forKey: key) { return v }
        if let single = try? c.decode(String.self, forKey: key) { return [single] }
        if let objects = try? c.decode([[String: String]].self, forKey: key) {
            return objects.compactMap { dict in dict.values.first }
        }
        return nil
    }
}

/// 把模型回的 raw 文本安全解析成结构；失败返回 nil（调用方按「原文展示」降级）。
public enum FeedbackParser {

    public static func parse(_ raw: String) -> CompositionFeedback? {
        guard let json = extractJson(raw) else { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CompositionFeedback.self, from: data)
    }

    /// 剥 ```json 围栏、掐头去尾找最外层大括号：模型很爱在 JSON 前后加一句「好的，以下是批改结果：」。
    static func extractJson(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.hasPrefix("```json") { text = String(text.dropFirst(7)) }
        else if text.hasPrefix("```") { text = String(text.dropFirst(3)) }
        if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }
}

// ==== LlmConfig.swift ====
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

    public func channel(hasImage: Bool) -> Channel {
        hasImage ? Channel(model: vlModel, maxTokens: vlMaxTokens)
                 : Channel(model: chatModel, maxTokens: chatMaxTokens)
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

// ==== LlmPolicy.swift ====
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
        // `read timed out`（Foundation 的 URLSession 文案）里没有 "timeout" 连写，得单独认
        if lower.contains("timeout") || lower.contains("timed out") { return "响应超时" }
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

// ==== LlmWire.swift ====
import Foundation

/// 请求体与 SSE 响应行的纯函数处理，对齐安卓 `LlmClient.buildBody` 与 `drain` 里的解析分支。
/// 网络 IO 留在 App 层，这里只负责“给一行文本，告诉上层该怎么反应”，
/// 因为这两处的分支条件（thinking 字段、error 对象、[DONE]、空 delta）历史上每次都踩过。

// MARK: - 请求体

public enum RequestBody {

    /// `disableThinking` 为真时补 `"thinking": {"type":"disabled"}`。
    /// 混合推理模型（glm-4.x-flash / deepseek-flash）默认 thinking=enabled，
    /// 不关掉就只拿得到 reasoning_content；实测两家连 VL 通道都接受这个字段（返回 200）。
    public static func dict(
        channel: LlmConfig.Channel,
        temperature: Double,
        messages: [Msg],
        imagesBase64: [String] = [],
        stream: Bool,
        maxTokensOverride: Int? = nil,
        disableThinking: Bool = false
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": channel.model,
            "stream": stream,
            "temperature": temperature,
            "max_tokens": maxTokensOverride ?? channel.maxTokens,
        ]
        if disableThinking { body["thinking"] = ["type": "disabled"] }

        var payload: [[String: Any]] = []
        for (i, msg) in messages.enumerated() {
            var entry: [String: Any] = ["role": msg.role]
            let parts = i == messages.count - 1
                ? PromptAssembler.buildUserContent(text: msg.content, imagesBase64: imagesBase64)
                : []
            if !parts.isEmpty && msg.role == "user" {
                entry["content"] = parts.map { part -> [String: Any] in
                    var obj: [String: Any] = ["type": part.type]
                    if let t = part.text { obj["text"] = t }
                    if let url = part.imageUrl { obj["image_url"] = ["url": url] }
                    return obj
                }
            } else {
                entry["content"] = msg.content
            }
            payload.append(entry)
        }
        body["messages"] = payload
        return body
    }

    /// key 排序固定，方便单测里逐字节比对，也方便日志里贴出来排查。
    public static func jsonData(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    public static func body(
        channel: LlmConfig.Channel,
        temperature: Double,
        messages: [Msg],
        imagesBase64: [String] = [],
        stream: Bool,
        maxTokensOverride: Int? = nil,
        disableThinking: Bool = false
    ) throws -> Data {
        try jsonData(dict(
            channel: channel, temperature: temperature, messages: messages,
            imagesBase64: imagesBase64, stream: stream,
            maxTokensOverride: maxTokensOverride, disableThinking: disableThinking
        ))
    }
}

// MARK: - SSE 行解析

/// 一行 SSE 文本的判定结果。`ignored` 表示这行不含正文增量（keepalive、role-only 首帧、
/// reasoning_content、解析失败的脏行），上层继续读下一行。
public enum SseEvent: Equatable {
    case delta(String)
    case done
    case upstreamError(String)
    case ignored
}

public enum SseParser {

    public static func handle(line raw: String) -> SseEvent {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        guard line.hasPrefix("data:") else { return .ignored }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ignored
        }
        if let err = obj["error"] {
            return .upstreamError(errorText(err))
        }
        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else {
            // reasoning_content 一律忽略：思考已在请求侧关掉，这里只是兜底
            return .ignored
        }
        return .delta(content)
    }

    /// 与安卓 `JsonElement.toString()` 同用途：把错误对象压成一段可 grep 的文本。
    static func errorText(_ err: Any) -> String {
        if let s = err as? String { return s }
        guard JSONSerialization.isValidJSONObject(err),
              let data = try? JSONSerialization.data(withJSONObject: err, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return String(describing: err)
        }
        return s
    }
}

// ==== MarkdownLite.swift ====
import Foundation

/// 轻量 Markdown / 中文禁则处理，逐条对齐安卓 `core/util/MarkdownLite.kt`。
///
/// 三科讲解文本长这样：`【答案】`、`**加粗**`、`### 标题`、`- 列表`、`\(...\)` 公式。
/// 模型输出并不总是守规矩，所以渲染前先规范化。三种形态：
/// - `strip`：流式期间纯文本预览
/// - `toRich`：定稿气泡用的分段结构（iOS 侧由 UI 层映射成 AttributedString）
/// - `toHtml`：喂给 WKWebView + KaTeX 的 HTML 片段
///
/// 所有转换都不触碰 LaTeX 定界符 `\(` `\)` `\[` `\]` 与反斜杠命令。
public enum MarkdownLite {

    // MARK: - 规则

    private static let bold = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let heading = try! NSRegularExpression(pattern: #"^\s{0,3}#{1,4}\s+(.*)$"#)
    private static let bullet = try! NSRegularExpression(pattern: #"^\s*[-*•]\s+"#)
    private static let rule = try! NSRegularExpression(pattern: #"^\s*(-{3,}|\*{3,})\s*$"#)
    private static let code = try! NSRegularExpression(pattern: "`([^`]+)`")
    private static let section = try! NSRegularExpression(pattern: #"^\s*(【[^】]{2,14}】)\s*$"#)

    /// 中文行首标点：模型常在 LaTeX 公式后断开，导致“。”孤零零占一行。
    /// 只含收尾类标点；故意不含“（”，因为“（1）xxx”是常见的合法换行项。
    private static let orphanPunct = try! NSRegularExpression(
        pattern: #"^[\u3002\uff0c\u3001\uff1b\uff1a\uff1f\uff01\u201d\u2019\u2014\u2026\uff09\u3011\u300b,;?!]"#
    )

    /// 公式与收尾标点之间多一个空格，浏览器就会把“。”单独折到下一行。
    private static let spaceBeforeClose = try! NSRegularExpression(
        pattern: #"\s+(?=[\u3002\uff0c\uff1b\uff1a\uff01\uff1f\uff09\u3011\u300b])"#
    )

    /// 中文禁则（标点不得出现在行首）不能指望渲染端：
    /// WebView 实测 lang="zh-CN" + line-break:strict 无效，公式又是 atomic inline，禁则更管不到；
    /// 这里直接把「前一个词 + 收尾标点」包成 nowrap，标点永远跟着前面的字走。
    ///
    /// 公式那段必须写成 `(?:(?!\\\().){1,40}?`：只写 `\\\(.{1,40}?\\\)` 的话，非贪婪只是优先短匹配，
    /// 为了让后面的标点成立，引擎会一路扩到本行最后一个 `\)`，把整句锁成一个不可断的块，
    /// 行首那一长串塞不下就整体挪到下一行，留下大片空白（安卓真机踩过，iOS 的 WKWebView 同引擎）。
    /// 40 字封顶：再长的算式宁可让它可以断，也别把整行顶到下一行。
    private static let punctGlue = try! NSRegularExpression(
        pattern: #"(\\\((?:(?!\\\().){1,40}?\\\)|[0-9A-Za-z.%\-]{1,24}|[\u4e00-\u9fff])([\u3002\uff0c\u3001\uff1b\uff1a\uff01\uff1f\u201d\u2019\u2014\u2026\uff09\u3011\u300b\)\]]+)"#
    )

    // MARK: - 对外判定

    public static func containsMarkdown(_ text: String) -> Bool {
        if bold.firstMatch(in: text, range: nsRange(text)) != nil { return true }
        for line in splitLines(text) {
            if isFullMatch(heading, line) { return true }
            if bullet.firstMatch(in: line, range: nsRange(line)) != nil { return true }
            if isFullMatch(rule, line) { return true }
        }
        return false
    }

    public static func containsLatex(_ text: String) -> Bool {
        text.contains("\\(") || text.contains("\\[")
    }

    // MARK: - 行规范化

    /// 丢弃分隔线，并把以标点开头的行并回上一行末尾。
    /// 三种渲染形态共用，保证流式预览 / 定稿气泡 / KaTeX WebView 表现一致。
    public static func normalizedLines(_ text: String) -> [String] {
        var out: [String] = []
        out.reserveCapacity(16)
        for raw in splitLines(text) {
            if isFullMatch(rule, raw) { continue }
            var trimmed = trimStart(raw)
            trimmed = replacing(spaceBeforeClose, trimmed) { _ in "" }
            if !out.isEmpty,
               !trimmed.isEmpty,
               orphanPunct.firstMatch(in: trimmed, range: nsRange(trimmed)) != nil {
                out[out.count - 1] = trimEnd(out[out.count - 1]) + trimmed
            } else {
                out.append(trimmed)
            }
        }
        return out
    }

    // MARK: - 三种输出形态

    /// 纯文本化（流式预览用）。
    public static func strip(_ text: String) -> String {
        normalizedLines(text).map { line in
            let base = firstGroup(heading, line) ?? line
            let unbuilt = replacingFirst(bullet, base) { _ in "• " }
            let afterBold = replacing(bold, unbuilt) { group($0, 1, in: unbuilt) }
            return replacing(code, afterBold) { group($0, 1, in: afterBold) }
        }.joined(separator: "\n")
    }

    /// 定稿气泡用：按行给出带加粗标记的分段。
    public static func toRich(_ text: String) -> [RichLine] {
        normalizedLines(text).map { raw in
            let headingTitle = firstGroup(heading, raw)
            let emphasized = headingTitle != nil || isFullMatch(section, raw)
            let line = headingTitle ?? raw
            let hasBullet = bullet.firstMatch(in: line, range: nsRange(line)) != nil
            let body = replacingFirst(bullet, line) { _ in "" }
            var segments = boldSegments(body, baseBold: emphasized)
            if hasBullet {
                segments.insert(RichSegment(text: "• ", bold: emphasized), at: 0)
            }
            return RichLine(segments: segments)
        }
    }

    /// WKWebView + KaTeX 用：先转义再还原标记，公式反斜杠不受影响。
    public static func toHtml(_ text: String) -> String {
        normalizedLines(text).map { raw in
            let headingTitle = firstGroup(heading, raw)
            let emphasized = headingTitle != nil || isFullMatch(section, raw)
            var line = escapeHtml(headingTitle ?? raw)
            line = replacingFirst(bullet, line) { _ in "• " }
            let afterBullet = line
            line = replacing(bold, afterBullet) { "<b>" + group($0, 1, in: afterBullet) + "</b>" }
            let afterBold = line
            line = replacing(code, afterBold) { "<code>" + group($0, 1, in: afterBold) + "</code>" }
            // 实体（&lt; &#39;）里的分号会被误当成标点，所以转义之后再包、且禁则集不含 ASCII 分号
            let beforeGlue = line
            line = replacing(punctGlue, beforeGlue) { m in
                "<span class=\"nw\">" + group(m, 0, in: beforeGlue) + "</span>"
            }
            return emphasized ? "<b>\(line)</b>" : line
        }.joined(separator: "<br>")
    }

    // MARK: - 输出结构

    public struct RichSegment: Equatable {
        public let text: String
        public let bold: Bool
        public init(text: String, bold: Bool) {
            self.text = text
            self.bold = bold
        }
    }

    public struct RichLine: Equatable {
        public let segments: [RichSegment]
        public init(segments: [RichSegment]) { self.segments = segments }
        public var plainText: String { segments.map(\.text).joined() }
    }

    // MARK: - 内部工具

    /// 与安卓 appendWithBold 同序：先清 `code` 再找 `**bold**`（替换会移动索引，简化处理）。
    private static func boldSegments(_ text: String, baseBold: Bool) -> [RichSegment] {
        let cleaned = replacing(code, text) { group($0, 1, in: text) }
        var segments: [RichSegment] = []
        var cursor = 0
        for m in bold.matches(in: cleaned, range: nsRange(cleaned)) {
            if m.range.location > cursor {
                segments.append(RichSegment(
                    text: substring(cleaned, NSRange(location: cursor, length: m.range.location - cursor)),
                    bold: baseBold
                ))
            }
            segments.append(RichSegment(text: group(m, 1, in: cleaned), bold: true))
            cursor = NSMaxRange(m.range)
        }
        if cursor < (cleaned as NSString).length {
            segments.append(RichSegment(
                text: substring(cleaned, NSRange(location: cursor, length: (cleaned as NSString).length - cursor)),
                bold: baseBold
            ))
        }
        return segments.filter { !$0.text.isEmpty }
    }

    private static func escapeHtml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Kotlin 的 lineSequence 认 \n、\r\n、\r；这里对齐，避免 Windows 风格换行留个孤零零的 \r。
    private static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func trimStart(_ s: String) -> String {
        String(s.drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func trimEnd(_ s: String) -> String {
        String(s.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
    }

    private static func nsRange(_ s: String) -> NSRange {
        NSRange(location: 0, length: (s as NSString).length)
    }

    private static func substring(_ s: String, _ r: NSRange) -> String {
        (s as NSString).substring(with: r)
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : substring(s, r)
    }

    private static func firstGroup(_ re: NSRegularExpression, _ s: String) -> String? {
        guard let m = re.firstMatch(in: s, range: nsRange(s)) else { return nil }
        let r = m.range(at: 1)
        return r.location == NSNotFound ? nil : substring(s, r)
    }

    /// Kotlin 的 Regex.matches 语义：整串必须被规则吃掉。
    private static func isFullMatch(_ re: NSRegularExpression, _ s: String) -> Bool {
        guard let m = re.firstMatch(in: s, range: nsRange(s)) else { return false }
        return m.range == nsRange(s)
    }

    /// 逐条替换，替换文本按字面插入（不像 withTemplate 那样解释 `$` 与 `\`）。
    private static func replacing(
        _ re: NSRegularExpression, _ input: String, _ transform: (NSTextCheckingResult) -> String
    ) -> String {
        let ns = input as NSString
        var out = ""
        var cursor = 0
        for m in re.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            }
            out += transform(m)
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length {
            out += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return out
    }

    private static func replacingFirst(
        _ re: NSRegularExpression, _ input: String, _ transform: (NSTextCheckingResult) -> String
    ) -> String {
        guard let m = re.firstMatch(in: input, range: nsRange(input)) else { return input }
        let ns = input as NSString
        return ns.substring(with: NSRange(location: 0, length: m.range.location))
            + transform(m)
            + ns.substring(with: NSRange(location: NSMaxRange(m.range), length: ns.length - NSMaxRange(m.range)))
    }
}

// ==== MathHtml.swift ====
import Foundation

/// KaTeX 渲染页的 HTML 外壳，与安卓 `ui/components/MathText.kt` 的 buildHtml 同一份模板。
///
/// 两端共用一个模板而不是各写一份，是因为这里的每条 CSS 都对应一次真机回归：
/// 行高、字重、nowrap、overflow-wrap 任何一处不一致，iOS 和安卓的同一条答案就会长得不一样。
public enum MathHtml {

    /// `colorHex` 形如 "#1D2129"，由调用方从语义色板换算，避免把颜色写死在模板里。
    public static func document(content: String, colorHex: String) -> String {
        let body = MarkdownLite.toHtml(content)
        return #"""
        <!DOCTYPE html>
        <html lang="zh-CN"><head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <link rel="stylesheet" href="katex.min.css">
        <script src="katex.min.js"></script>
        <script src="auto-render.min.js"></script>
        <style>
          html,body{margin:0;padding:0;background:transparent;}
          /* 不给 body 设 overflow-wrap：它会为了塞下长词而硬拆，把“）。”这类收尾标点甩到行首；
             中文本来每两个字之间都有断点，只有 code 这种长串才需要强行可断。
             line-break:strict 实测不生效，反而会把整句的断点吞掉（行尾留一大块空白），禁则改由 MarkdownLite 保证 */
          body{font-size:16px;line-height:1.85;color:\#(colorHex);
            font-family:-apple-system,"PingFang SC","Heiti SC",sans-serif;-webkit-text-size-adjust:100%;}
          /* KaTeX 默认 1.21em 会把行高撑开、中文标点挤到下一行，收敛到接近正文字号 */
          .katex{font-size:1.06em;line-height:1.1;}
          .katex-display{margin:8px 0;overflow-x:auto;overflow-y:hidden;padding:2px 0;}
          code{font-family:ui-monospace,Menlo,monospace;font-size:0.94em;overflow-wrap:break-word;}
          /* MarkdownLite 把「前一个词 + 收尾标点」包进这个 span，避免“。”单独成行 */
          .nw{white-space:nowrap;}
          /* 600 比 SwiftUI .bold(700) 弱，两条渲染路径同一句话字重会不一致 */
          b,strong{font-weight:700;}
          p{margin:0 0 2px 0;}
        </style>
        </head><body>\#(body)
        <script>
          renderMathInElement(document.body, {delimiters:[
            {left:"\\[", right:"\\]", display:true},
            {left:"\\(", right:"\\)", display:false}
          ]});
        </script>
        </body></html>
        """#
    }

    /// 回读内容高度用的 JS。WebView 不会自己撑高，量到 0（页面未就绪）时调用方要保持原样，
    /// 不能把自己压成一条线。
    public static let heightProbe =
        "(function(){var b=document.body;return b?Math.ceil(b.scrollHeight):0;})();"

    /// SRGB 颜色 → "#RRGGBB"，与安卓 String.format("#%06X", ...) 同结果。
    public static func hexColor(red: Double, green: Double, blue: Double) -> String {
        let r = Int((max(0, min(1, red)) * 255).rounded())
        let g = Int((max(0, min(1, green)) * 255).rounded())
        let b = Int((max(0, min(1, blue)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// ==== PromptAssembler.swift ====
import Foundation

/// 一条 OpenAI 格式消息（content 纯文本；多模态 parts 由 `buildUserContent` 生成）。
public struct Msg: Equatable, Codable {
    public let role: String
    public let content: String
    public init(_ role: String, _ content: String) {
        self.role = role
        self.content = content
    }
}

/// 多模态 content 数组的元素（text 或 image_url data URL）。
public struct ContentPart: Equatable {
    public let type: String
    public let text: String?
    public let imageUrl: String?
    public init(type: String, text: String? = nil, imageUrl: String? = nil) {
        self.type = type
        self.text = text
        self.imageUrl = imageUrl
    }
}

/// 纯函数消息组装器，对齐安卓 `core/llm/PromptAssembler.kt`，另加 iOS 独有的 ESSAY。
/// 不依赖 UI，可在 Windows 上跑单测。
public enum PromptAssembler {

    public static let defaultMaxTurns = 8

    public enum Kind {
        case chat, composition, rewrite, essay

        /// 讲题求准确，改写与生成范文求多样。
        public var temperature: Double {
            switch self {
            case .chat, .composition: return 0.3
            case .rewrite: return 0.7
            case .essay: return 0.85
            }
        }
    }

    public static func chatMessages(
        subject: String,
        userText: String,
        history: [Msg],
        maxTurns: Int = defaultMaxTurns
    ) throws -> [Msg] {
        guard let system = Prompts.systemPrompts[subject] else {
            throw LlmError.unknownSubject(subject)
        }
        let trimmed = Array(history.suffix(maxTurns * 2))
        return [Msg("system", system)] + trimmed + [Msg("user", userText)]
    }

    public static func compositionUserMessage(
        title: String,
        grade: String,
        content: String?,
        requirement: String?,
        imageCount: Int = 0
    ) -> String {
        let body = content.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? "（图片形式提交，请先识别图中作文内容）"
        var sb = "作文标题：\(title)\n年级：\(grade)\n"
        if let requirement, !requirement.trimmingCharacters(in: .whitespaces).isEmpty {
            sb += "题目要求：\(requirement)\n"
        }
        if imageCount > 1 {
            sb += "说明：作者共上传了 \(imageCount) 页手稿图片，按页码顺序排列，请通读全部页面后再批改，引用时注明第几页。\n"
        }
        sb += "作文正文：\n\(body)"
        return sb
    }

    public static func compositionMessages(
        title: String,
        grade: String,
        content: String?,
        requirement: String?,
        imageCount: Int = 0
    ) -> [Msg] {
        [
            Msg("system", Prompts.compositionPrompt),
            Msg("user", compositionUserMessage(
                title: title, grade: grade, content: content,
                requirement: requirement, imageCount: imageCount
            )),
        ]
    }

    /// 段落改写。
    public static func rewriteMessages(_ text: String) -> [Msg] {
        [Msg("system", Prompts.rewritePrompt), Msg("user", text)]
    }

    /// 生成作文（iOS 新增）：题目 + 可选要求/体裁/字数。
    public static func essayUserMessage(
        title: String,
        requirement: String?,
        genre: String?,
        wordCount: Int?
    ) -> String {
        var sb = "作文题目：\(title)\n年级：六年级"
        if let genre, !genre.trimmingCharacters(in: .whitespaces).isEmpty {
            sb += "\n体裁：\(genre)"
        }
        if let wordCount, wordCount > 0 {
            sb += "\n字数要求：\(wordCount)字左右"
        }
        if let requirement, !requirement.trimmingCharacters(in: .whitespaces).isEmpty {
            sb += "\n题目要求：\(requirement)"
        }
        return sb
    }

    public static func essayMessages(
        title: String,
        requirement: String?,
        genre: String?,
        wordCount: Int?
    ) -> [Msg] {
        [
            Msg("system", Prompts.essayPrompt),
            Msg("user", essayUserMessage(
                title: title, requirement: requirement, genre: genre, wordCount: wordCount
            )),
        ]
    }

    /// 多模态 user 消息的 content 数组：文字在前，图片按顺序在后（支持作文多页手稿）。
    /// images 为空时返回空数组，调用方降级为纯文本 content。
    public static func buildUserContent(text: String, imagesBase64: [String]) -> [ContentPart] {
        if imagesBase64.isEmpty { return [] }
        return [ContentPart(type: "text", text: text)]
            + imagesBase64.map { ContentPart(type: "image_url", imageUrl: "data:image/jpeg;base64,\($0)") }
    }

    public static func temperature(for kind: Kind) -> Double { kind.temperature }
}

public enum LlmError: Error, Equatable {
    case unknownSubject(String)
    case http(Int, String)
    case busy(String)
    case noFirstToken
    case empty(String)

    /// 与安卓 IllegalStateException 文案对齐，UI 侧的友好化映射两边共用同一份。
    public var message: String {
        switch self {
        case .unknownSubject(let s): return "unknown subject: \(s)"
        case .http(let code, let body): return "HTTP \(code) \(body)"
        case .busy(let last): return "模型服务繁忙（\(last)），请稍后重试"
        case .noFirstToken: return "\(LlmPolicy.firstTokenBudgetSeconds)s 内没等到首个字词"
        case .empty(let raw): return raw.isEmpty ? "响应提前结束，请重试" : raw
        }
    }
}

// ==== Prompts.swift ====
import Foundation

/// 三科 System Prompt + 作文批改 + 段落改写 + 生成范文。
/// 与安卓 `core/llm/Prompts.kt` 同源，改动必须两处同步；全文不使用 emoji。
///
/// iOS 侧多一项 ESSAY（生成作文）：安卓没有这个入口，属于本次移植新增的特色功能，
/// 但它的输出同样要能被朗读器自然读出来，所以提示词里写死了「便于朗读」的约束。
public enum Prompts {

    static let imageNote = """
    【图片优先规则】消息中若附带图片，图片就是题目原貌（语文/英语可能含整段文章与多道小题）。
    一切以图片为准；随附文字只是机器识别的参考，识别与图片不一致时按图片处理。
    图片中题目不完整或有多道小题时，先说明你看到了哪道题，再作答。
    """

    public static let systemPrompts: [String: String] = [
        // ───────────────────────── 语文 ─────────────────────────
        "chinese": """
        你是一位耐心温柔的小学六年级语文老师，名叫“小语”。学生是11-12岁的小学生。请严格遵守：

        【输出结构】每次讲题必须包含以下四个板块，小标题单独占一行，只用纯文字和【】标题：
        【答案】先给出完整明确的参考答案。选择填空直接给结论；简答、赏析、作文类要写出可以照着答的完整答案，不许只引导不给答案。
        【讲一讲】分步骤解释为什么这样答。每一步一两句话，引用原文中的关键词句，让学生看懂答案是怎么来的。
        【易错提醒】指出这类题小学生最容易犯的一两个错误。
        【方法与练习】给一句好记的方法口诀，再出一道同类型练习题（必须附答案）。

        【语言要求】
        1. 口语化短句，每步不超过两行，重点答案可以用“答：”开头单独成行
        2. 禁用初高中术语（如“意象”“通感”“借景抒情”等），必须出现时用一句话解释成大白话
        3. 语气温柔鼓励，禁止说“很简单”“你应该会”
        4. 不要使用任何emoji，也不要使用Markdown符号（#、*、反引号、---），只用纯文字和【】标题分节
        5. 全文不超过600字

        【题型特殊处理】
        - 古诗、文言文：【讲一讲】里必须有逐句白话翻译、作者朝代一句话简介、表达的情感
        - 阅读理解：【答案】写成可以直接抄到答题卷上的完整句子；【讲一讲】点出依据的原文句子
        - 字词、造句、按课文填空：【答案】明确给出填什么、为什么这样填
        - 习作、写人记事类大题：给出简单提纲加一个示范开头段落，不许拒答

        【禁止事项】
        - 禁止只引导不给答案
        - 禁止讨论与学习无关的话题；学生问了就礼貌引导回学习
        - 禁止出现“作为AI”这类表述

        """ + "\n" + imageNote,

        // ───────────────────────── 数学 ─────────────────────────
        "math": """
        你是一位耐心温柔的小学六年级数学老师，名叫“小数”。学生是11-12岁的小学生。请严格遵守：

        【回答结构】每次讲题必须分为6个固定板块，用【】小标题分隔，标题单独占一行：
        【答案】
        【题目在考什么】
        【常见错误】
        【解题思路】
        【知识点小课堂】
        【改错建议与同类练习】

        【语言风格】
        1. 短句为主，禁止长段落
        2. 禁用初中术语（如“设未知数”“方程”优先用“用字母代替”“天平两边”）
        3. 数字计算必须写出完整过程，不能跳步
        4. 遇到分数、小数、百分数，先化为最简形式再讲
        5. 正文里不许出现裸算式：分数、百分数、带未知数的式子一律写 LaTeX，`7/8` 要写成 \\( \\frac{7}{8} \\)，`x^2` 要写成 \\( x^2 \\)；单位（厘米、平方厘米、元）留在 LaTeX 外面

        【内容要求】
        1. 【答案】：开门见山，单独一行写“答：XXX”，带单位，不写任何过程（学生先知道自己该填什么，再看讲解）；答案里的分数也要用 LaTeX，写成“答：\\( \\frac{7}{8} \\)”而不是“答：7/8”
        2. 【题目在考什么】：指出考查的知识点（如“分数应用题”“圆的面积”“比例”）
        3. 【常见错误】：列1-2个易错点，如“忘了单位换算”“分母没通分”
        4. 【解题思路】：必须分步骤，每步单独一行，格式：
           第1步：...
           第2步：...
           第3步：...
           步骤末尾不必再写“答：”，答案已在开头给出
           计算过程用 LaTeX 行内格式 \\( ... \\)，独立公式用 \\[ ... \\]
        5. 【知识点小课堂】：讲公式来源或生活实例
        6. 【改错建议与同类练习】：1条建议 + 1道同类题的题干。练习题只出题，不要给出它的解题步骤和答案，最后用一句话提醒“做完后再来核对答案”

        【数学公式输出规范】（这一条优先级高于字数与排版，违反即视为答错）
        - 所有变量、数字表达式必须用 LaTeX 包裹
        - 行内：\\( x + 3 = 5 \\)
        - 独立：\\[ S = \\pi r^2 \\]
        - 分数：\\( \\frac{3}{4} \\)
        - 一行只写一个等号：连等式（A = B = C = D）拆成多行，一行一步，否则算式会被挤到行中拆断
        - 禁止用纯文本写公式（如“x^2”必须写成 \\( x^2 \\)）

        【应用题特殊处理】
        用“翻译法”：把中文一句一句翻译成数学式，例如：
        “小明有5个苹果” → 设小明苹果数 = 5
        “比小红多2个” → 小红 = 5 - 2 = 3

        【几何题特殊处理】
        - 先用文字描述图形（如“这是一个直角三角形，两条直角边分别是3和4”）
        - 强调“看图找已知”
        - 公式必须写出（如 \\( S = \\frac{1}{2} \\times 底 \\times 高 \\)）

        【禁止事项】
        - 不要使用任何 emoji，也不要使用 Markdown 符号（#、*、反引号、---），只用纯文字和【】小标题分节
        - 只给答案不写步骤过程
        - 超过600字
        - 使用负数、无理数、方程组等超出六年级范围的解法（除非题目本身要求）

        """ + "\n" + imageNote,

        // ───────────────────────── 英语 ─────────────────────────
        "english": """
        你是一位耐心温柔的小学六年级英语老师，名叫“小英”。学生是11-12岁的中国小学生。你的回答用中文为主，英语为辅，严格遵守：

        【回答结构】必须分为6个固定板块，用【】小标题分隔，标题单独占一行：
        【答案】
        【题目在考什么】
        【常见错误】
        【解题思路】
        【知识点小课堂】
        【改错建议与同类练习】

        【语言要求】
        1. 讲解全部用中文，只有例句、单词、音标保留英语
        2. 单词必须给：英文 + 音标 + 中文谐音（近似读法） + 中文意思 + 1个例句
           例如：apple /ˈæpəl/ 【挨剖】n. 苹果 → I eat an apple every day.
        3. 语法讲解用“口诀”或“生活比喻”，禁止用“主谓宾定状补”等语法术语
        4. 不要使用任何 emoji，也不要使用 Markdown 符号（#、*、反引号、---）

        【内容要求】
        1. 【答案】：单独一行直接给出正确答案（填空就给要填的词/句子，选择就给选项），不解释
        2. 【题目在考什么】：指出考点（如“一般现在时”“第三人称单数”“介词in/on/at”）
        3. 【常见错误】：中国小学生最容易犯的1-2个错，如“He go to school”（漏s）
        4. 【解题思路】：分步骤，每步一行，步骤末尾不必再写“答：”
        5. 【知识点小课堂】：
           - 语法点：用口诀（如“我am你are，他她它is”）
           - 词汇题：给联想记忆法（如“family = Father And Mother I Love You”）
        6. 【改错建议与同类练习】：1条建议 + 1道同类题的题干（只出题，不给答案，末句提醒“做完后再来核对答案”）

        【题型特殊处理】
        - 听力题：给出发音要点 + 常见连读
        - 阅读理解：先给全文简短翻译，再逐题给出完整答案句
        - 完形填空：讲上下文逻辑，逐空给答案
        - 作文：给出好句模板，如 "In my opinion, ..." / "First, ... Second, ... Finally, ..."，并给一篇可模仿的范文

        【禁止事项】
        - 用纯英语回答（学生看不懂）
        - 使用高中词汇（如 utilize, subsequently）
        - 讲解超过500字
        - 只讲方法不给明确答案

        """ + "\n" + imageNote,
    ]

    // ───────────────────────── 作文批改 ─────────────────────────
    public static let compositionPrompt = """
    你是一位资深小学语文老师，专门批改六年级作文。请严格按以下JSON格式返回，不要输出任何JSON以外的内容（不要用```json包裹，直接输出纯JSON）：

    {
      "总分": 0到100的整数,
      "分项": {
        "内容": 0到25,
        "结构": 0到25,
        "语言": 0到25,
        "书写": 0到25
      },
      "总评": "50字以内的总体评价，语气温柔鼓励",
      "优点": [
        {"位置": "第X段或开头结尾", "内容": "具体到句子", "为什么好": "一句话"}
      ],
      "问题": [
        {
          "位置": "第X段",
          "类型": "错别字或病句或跑题或逻辑跳跃或标点或用词不当",
          "原句": "原文",
          "问题说明": "小学生能懂的解释",
          "修改建议": "改后的句子"
        }
      ],
      "改进建议": [
        "具体可执行的3条建议，每条不超过30字"
      ],
      "好句升级": [
        {"原句": "原文", "改写": "升级后", "为什么更好": "一句话"}
      ],
      "同类范文片段": "给出一段50-100字的同题材优秀范文片段供学习"
    }

    【评分标准】
    - 内容（25分）：切题、有真情实感、有细节
    - 结构（25分）：开头结尾呼应、段落清晰、过渡自然
    - 语言（25分）：用词准确、有修辞、句式多样
    - 书写（25分）：如果提供了图片，看字迹工整度；如果只有文字，默认给20分

    【要求】
    1. “优点”至少给2条，最多4条
    2. “问题”至少给1条，最多6条，按严重程度排序
    3. “改进建议”必须具体可执行，如“在第2段加入外貌描写”，禁止“多读书”这种空话
    4. “好句升级”至少1条，最多3条
    5. 语气始终温柔鼓励，即使作文很差也要先肯定优点
    6. 所有字段文本中不要使用任何 emoji，也不要使用 Markdown 符号，只用纯文字
    7. 只输出JSON，不要有任何前后说明文字
    8. 若附带图片：图片是手写作文原稿，先完整识别正文再批改；识别的文字与图片不一致时以图片为准
    9. 输出务必精炼：每个字段短句表达，总JSON控制在700字以内，防止被截断
    """

    // ───────────────────────── 段落改写 ─────────────────────────
    public static let rewritePrompt = """
    你是小学六年级语文老师。用户会给你一段作文，请：
    1. 保留原意和小学生的口吻
    2. 优化用词、句式、修辞
    3. 不要过度文学化，保持六年级学生能写出的水平
    4. 不要使用任何 emoji 或 Markdown 符号，只用纯文字
    5. 输出格式：
       【改写后】
       <改写后的段落>

       【改了哪里】
       - <改动点1>
       - <改动点2>

       【为什么这样改】
       <一段话，不超过50字>
    """

    // ───────────────────────── 生成作文（iOS 新增） ─────────────────────────
    /// 给题目就产出一份「能照着写」的范文包，而不是只丢一篇文章让学生抄。
    /// 结构与讲题保持一致（【】分节），这样同一套排版与朗读器都能直接复用。
    public static let essayPrompt = """
    你是一位耐心温柔的小学六年级语文老师，名叫“小语”。学生是11-12岁的小学生，他给你一个作文题目，你要带他把这篇作文写出来。请严格遵守：

    【输出结构】必须包含以下四个板块，小标题单独占一行，只用纯文字和【】标题：
    【审题】一两句话讲清这道题要求写什么、重点落在哪个词上，不许跑题。
    【提纲】3到5条，每条一句话，按写作顺序排列，学生能照着一条条往下写。
    【范文】一篇完整的示范作文，另起一行写标题，正文分段，段与段之间空一行。
    【好词好句】3到5条，从范文里挑出来，每条后面用一句话说明好在哪儿。

    【范文要求】
    1. 字数按用户给的要求来；没给就写500到600字
    2. 必须是六年级学生写出来的水平：句子短、用词朴素，可以有童趣的小毛病式表达，禁止成人化的华丽辞藻
    3. 有真情实感和具体细节，写人要有动作和语言，记事要有过程，写景要有顺序
    4. 开头三两句话入题，结尾呼应开头，不许喊口号
    5. 禁用初高中词汇和成语堆砌，禁止引用名人名言
    6. 体裁按题目来：记叙文为主；说明文、读后感、书信等按题目要求切换格式

    【便于朗读】这篇范文会被语音朗读出来，所以：
    1. 句子要短，一句话说一件事，少用长定语和多重从句
    2. 少用括号、引号套引号、顿号连用；数字尽量写成中文或者简单阿拉伯数字
    3. 不要用省略号连排、不要重复标点，读起来会卡顿

    【禁止事项】
    - 不要使用任何 emoji，也不要使用 Markdown 符号（#、*、反引号、---）
    - 不要说“作为AI”“我不能写作”这类话，必须完整给出范文
    - 不要只给提纲不给范文
    - 全文（含四个板块）不超过1200字

    """ + "\n" + imageNote
}

// ==== RawDeflate.swift ====
import Foundation

#if canImport(Compression)
import Compression

/// ZIP 里 deflate 条目的解压。
///
/// 只在 Apple 平台编译：Windows 侧只跑单测，测试数据一律用 store（不压缩），
/// 这样 Core 在两端都能编译，而 iOS 仍然读得懂用户在「文件」App 里重新压缩过的备份包。
enum RawDeflate {

    enum Failure: Swift.Error {
        case corrupted
    }

    /// raw deflate（无 zlib/gzip 头），正是 ZIP method=8 的格式。
    /// COMPRESSION_ZLIB 在 Apple 的 Compression 里就是裸 deflate 流。
    static func inflate(_ input: Data, expected: Int) throws -> Data {
        guard !input.isEmpty else { return Data() }
        // 解压炸弹兜底：允许比声明的大小多出 1MB，超了直接判定损坏
        let capacity = max(expected, 0) + 1_048_576
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        let written: Int = input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                buffer, capacity,
                base, input.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written > 0 else { throw Failure.corrupted }
        return Data(bytes: buffer, count: written)
    }
}
#endif

// ==== SpeechText.swift ====
import Foundation

/// 朗读前的文本归一化：把讲稿变成「人会说出口」的话。
///
/// 这是「用尽可能像人的语速和音色朗读」这条需求里真正容易做错的一半 ——
/// 音色由系统语音决定，但如果直接把 Markdown 喂给 TTS，学生会听到
/// 「左括号 反斜杠 frac 七 八 右括号」，而老师说的一定是「八分之七」。
///
/// 放在 Core 里是因为这套替换全是纯字符串规则，必须能在不启动模拟器的情况下测。
public enum SpeechText {

    public enum Language: String, Equatable {
        case chinese, english
    }

    public struct Chunk: Equatable {
        public let text: String
        public let language: Language
        public init(text: String, language: Language) {
            self.text = text
            self.language = language
        }
    }

    // MARK: 规则表

    private static let displayMath = try! NSRegularExpression(pattern: #"\\\[(.+?)\\\]"#, options: [.dotMatchesLineSeparators])
    private static let inlineMath = try! NSRegularExpression(pattern: #"\\\((.+?)\\\)"#, options: [.dotMatchesLineSeparators])
    private static let sectionTag = try! NSRegularExpression(pattern: "【([^】]{1,14})】")
    private static let bullet = try! NSRegularExpression(pattern: "^[ \\t]*[•·][ \\t]*", options: [])
    private static let frac = try! NSRegularExpression(pattern: #"\\d?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#)
    private static let sqrt = try! NSRegularExpression(pattern: #"\\sqrt\s*\{([^{}]*)\}"#)
    private static let power2 = try! NSRegularExpression(pattern: #"\^\s*2|\\times\s*2(?![0-9])"#)
    private static let power3 = try! NSRegularExpression(pattern: #"\^\s*3"#)
    // LaTeX 里的百分号可能是 `%` 也可能是 `\%`，两种都得认出「百分之」；
    // 只认裸 `%` 时 `25\%` 会漏到 wordMap 里变成 "25%"，TTS 会念成「二十五 percent」。
    private static let percent = try! NSRegularExpression(pattern: #"([0-9.]+)\s*\\?%"#)
    private static let leftoverCmd = try! NSRegularExpression(pattern: #"\\[a-zA-Z]+"#)
    private static let multiSpace = try! NSRegularExpression(pattern: "[ \\t]{2,}")
    private static let cjk = try! NSRegularExpression(pattern: #"[\u4e00-\u9fff]"#)

    /// 一条命令词的读法替换。顺序敏感：先长后短。
    private static let wordMap: [(String, String)] = [
        ("\\times", " 乘 "),
        ("\\div", " 除以 "),
        ("\\frac", " "),          // 已由 frac 正则处理，剩下的当噪声清掉
        ("\\dfrac", " "),
        ("\\pi", "π"),
        ("\\approx", " 约等于 "),
        ("\\geq", " 大于等于 "),
        ("\\leq", " 小于等于 "),
        ("\\neq", " 不等于 "),
        ("\\left", " "),
        ("\\right", " "),
        ("\\%", "%"),
        ("=", " 等于 "),
        ("+", " 加 "),
        ("-", " 减 "),
        ("(", "（"),
        (")", "）"),
    ]

    // MARK: 对外

    /// Markdown + LaTeX → 可直接交给 TTS 的中文口语串。
    public static func normalize(_ raw: String) -> String {
        var s = MarkdownLite.strip(raw)

        // 独立公式块先摘掉定界符，内容按行内公式同样处理
        s = replacing(displayMath, s) { group($0, 1, in: s) }

        // 每个 \( ... \) 内部整体翻译成口语
        s = replacing(inlineMath, s) { m in
            " " + speakMath(group(m, 1, in: s)) + " "
        }

        // 【答案】这类小标题读成「答案，」，让耳朵能分出段落
        s = replacing(sectionTag, s) { m in group(m, 1, in: s) + "，" }
        s = replacing(bullet, s) { _ in "" }
        s = s.replacingOccurrences(of: "——", with: "，")
            .replacingOccurrences(of: "---", with: "")
        s = replacing(multiSpace, s) { _ in " " }

        // 连续空行压成一个换行，分句时按它断
        s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 把 `\frac{7}{8}`、`r^2`、`3.14 × 6` 这类式子翻成中文读法。
    static func speakMath(_ inner: String) -> String {
        var s = inner
        // 中文分数先说分母再说分子：\frac{7}{8}（7/8）要念「八分之七」。
        // 正则只吃不含花括号的一层，所以嵌套分数天然从最内层开始替，循环几次就能剥完。
        for _ in 0..<4 {
            let next = replacing(frac, s) { m in
                let num = chineseNumber(group(m, 1, in: s))
                let den = chineseNumber(group(m, 2, in: s))
                return " \(den)分之\(num) "
            }
            if next == s { break }
            s = next
        }
        s = replacing(sqrt, s) { "根号" + group($0, 1, in: s) }
        s = replacing(power3, s) { _ in " 的立方 " }
        s = replacing(power2, s) { _ in " 的平方 " }
        s = replacing(percent, s) { "百分之" + group($0, 1, in: s) }

        for (from, to) in wordMap {
            s = s.replacingOccurrences(of: from, with: to)
        }
        // 兜底：没进映射表的 \command 直接删掉，念出来只会是噪声
        s = replacing(leftoverCmd, s) { _ in " " }
        s = s.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        s = replacing(multiSpace, s) { _ in " " }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: 数字转中文

    /// 分数里的阿拉伯数字要先转成汉字：`\frac{7}{8}` 应念「八分之七」，
    /// 若留成 "8分之7"，TTS 会把前半读成英文字母、后半读成数字，语速和音色都会跳。
    private static func chineseNumber(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber }), let n = Int(t), n >= 0, n <= 9999 else { return t }
        return chineseNumber(n)
    }

    private static func chineseNumber(_ n: Int) -> String {
        let d = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n < 10 { return d[n] }
        if n < 20 { return n == 10 ? "十" : "十" + d[n % 10] }
        if n < 100 {
            let tens = d[n / 10] + "十"
            return n % 10 == 0 ? tens : tens + d[n % 10]
        }
        if n < 1000 {
            let head = d[n / 100] + "百"
            let rem = n % 100
            if rem == 0 { return head }
            if rem < 10 { return head + "零" + d[rem] }
            return head + chineseNumber(rem)
        }
        let head = d[n / 1000] + "千"
        let rem = n % 1000
        if rem == 0 { return head }
        if rem < 100 { return head + "零" + chineseNumber(rem) }
        return head + chineseNumber(rem)
    }

    /// 归一化 + 按呼吸断句 + 逐段判定语种。
    /// 英语题的讲解是中文夹英文，一个中文音色念 English 单词很难听，所以按脚本切段交给不同 voice。
    public static func chunks(_ raw: String, maxChunkChars: Int = 42) -> [Chunk] {
        let text = normalize(raw)
        guard !text.isEmpty else { return [] }
        var out: [Chunk] = []
        for sentence in splitSentences(text, maxChunkChars: maxChunkChars) {
            for piece in splitByScript(sentence) {
                out.append(Chunk(text: piece, language: language(of: piece)))
            }
        }
        return out
    }

    /// 句子级切分：中文句末标点、换行都断；过长的句子再按逗号找换气口。
    static func splitSentences(_ text: String, maxChunkChars: Int) -> [String] {
        var result: [String] = []
        var current = ""
        let delimiters: Set<Character> = ["。", "！", "？", "；", "…", "\n", ".", "!", "?", ";"]
        for ch in text {
            current.append(ch)
            if delimiters.contains(ch) {
                flush(&result, &current, maxChunkChars: maxChunkChars)
            }
        }
        flush(&result, &current, maxChunkChars: maxChunkChars)
        return result
    }

    private static func flush(_ result: inout [String], _ current: inout String, maxChunkChars: Int) {
        var rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        current = ""
        guard !rest.isEmpty else { return }
        // 太长：反复从最后一个逗号/顿号/空格处劈开，保证 TTS 有换气，不至于越念越快。
        // 旧实现只在整串里找「最后一个」软分隔，结果把 200+ 字整段又塞回去，等于没切。
        let soft: [Character] = ["，", "、", ",", " "]
        while rest.count > maxChunkChars {
            // 软分隔最多允许落到 1.5 倍上限（测试容许 60/42），再远就硬切
            let windowEnd = rest.index(rest.startIndex, offsetBy: min(rest.count, maxChunkChars + maxChunkChars / 2))
            let window = rest[rest.startIndex..<windowEnd]
            var cut: String.Index?
            for mark in soft {
                if let idx = window.lastIndex(of: mark) {
                    let after = rest.index(after: idx)
                    if after > rest.startIndex, rest.distance(from: rest.startIndex, to: after) > maxChunkChars / 2 {
                        cut = after
                    }
                    break
                }
            }
            let boundary = cut ?? rest.index(rest.startIndex, offsetBy: maxChunkChars)
            let head = String(rest[rest.startIndex..<boundary]).trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { result.append(head) }
            rest = String(rest[boundary...]).trimmingCharacters(in: .whitespaces)
        }
        if !rest.isEmpty { result.append(rest) }
    }

    /// 中文段与拉丁段分开，交给各自的音色。
    static func splitByScript(_ sentence: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var currentIsLatin: Bool?
        for ch in sentence {
            let latin = ch.isASCII && (ch.isLetter || ch.isNumber)
            let isCjk = isCjkChar(ch)
            guard !isCjk else {
                if !current.isEmpty { pieces.append(current); current = "" }
                currentIsLatin = nil
                current.append(ch)
                continue
            }
            if latin {
                if currentIsLatin == false, !current.isEmpty { pieces.append(current); current = "" }
                currentIsLatin = true
                current.append(ch)
            } else {
                // 标点等中性字符跟在当前段尾巴上
                current.append(ch)
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func language(of piece: String) -> Language {
        if cjk.firstMatch(in: piece, range: NSRange(location: 0, length: (piece as NSString).length)) != nil {
            return .chinese
        }
        return .english
    }

    private static func isCjkChar(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(Int(scalar.value))
    }

    // MARK: 正则小工具（与 MarkdownLite 同一套字面替换语义）

    private static func replacing(
        _ re: NSRegularExpression, _ input: String, _ transform: (NSTextCheckingResult) -> String
    ) -> String {
        let ns = input as NSString
        var out = ""
        var cursor = 0
        for m in re.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            }
            out += transform(m)
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length {
            out += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return out
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : (s as NSString).substring(with: r)
    }
}

// ==== Zip.swift ====
import Foundation

/// 极简 ZIP 读写（无第三方依赖，纯 Foundation）。
///
/// 为什么自己写：备份必须跨端 —— 安卓导出的 zip 要能在 iOS 导入，反之亦然。
/// iOS 系统没有公开的 zip 打包 API，而我们的载荷已经是 JPEG/JSON，
/// 再压一遍收益接近 0，所以**写出用 store（不压缩）**；读取则同时支持
/// store 与 deflate（用户在「文件」里重新打包会变成 deflate）。
///
/// CRC32 是 ZIP 规范的强制项，写错一个位整包就废了，因此单独可测。
public enum Zip {

    public struct Entry: Equatable {
        public let name: String
        public let data: Data
        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    public enum ZipError: Error, Equatable {
        case badMagic
        case truncated
        case unsupportedMethod(UInt16)
    }

    // MARK: - 写

    public static func write(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            var local = Data()
            local += le(0x04034b50)          // local file header 魔数
            local += le16(20)                // version needed
            local += le16(0)                 // flags
            local += le16(0)                 // method = store
            local += le16(0)                 // mod time
            local += le16(0x21)              // mod date（1980-01-01，够用即可，备份不靠它排序）
            local += le(crc)
            local += le(size)                // compressed size
            local += le(size)                // uncompressed size
            local += le16(UInt16(nameData.count))
            local += le16(0)                 // extra length
            local += nameData
            local += entry.data

            var record = Data()
            record += le(0x02014b50)         // central directory 魔数
            record += le16(20)               // version made by
            record += le16(20)               // version needed
            record += le16(0)
            record += le16(0)                // method = store
            record += le16(0)
            record += le16(0x21)
            record += le(crc)
            record += le(size)
            record += le(size)
            record += le16(UInt16(nameData.count))
            record += le16(0)                // extra
            record += le16(0)                // comment
            record += le16(0)                // disk number
            record += le16(0)                // internal attrs
            record += le(0)                  // external attrs
            record += le(offset)             // 本地头偏移
            record += nameData

            out += local
            central += record
            offset += UInt32(local.count)
        }

        let centralOffset = offset
        let centralSize = UInt32(central.count)
        var end = Data()
        end += le(0x06054b50)
        end += le16(0)
        end += le16(0)
        end += le16(UInt16(entries.count))
        end += le16(UInt16(entries.count))
        end += le(centralSize)
        end += le(centralOffset)
        end += le16(0)                       // comment length

        out += central
        out += end
        return out
    }

    // MARK: - 读

    /// 从 zip 里读出全部文件。容忍 store 与 deflate 两种方法。
    public static func read(_ data: Data) throws -> [Entry] {
        guard let endOffset = findEndOfCentral(in: data) else { throw ZipError.badMagic }
        let slice = data.subdata(in: endOffset..<data.count)
        guard slice.count >= 22 else { throw ZipError.truncated }
        let count = Int(read16(slice, 10))
        var centralOffset = UInt32(read32(slice, 16))
        var cursor = Int(centralOffset)

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            let header = data.subdata(in: cursor..<(cursor + 46))
            guard header.count == 46, read32(header, 0) == 0x02014b50 else { throw ZipError.truncated }
            let method = read16(header, 10)
            let compressedSize = Int(read32(header, 20))
            let nameLength = Int(read16(header, 28))
            let extraLength = Int(read16(header, 30))
            let commentLength = Int(read16(header, 32))
            let localHeaderOffset = Int(read32(header, 42))
            let nameRange = (cursor + 46)..<(cursor + 46 + nameLength)
            guard nameRange.upperBound <= data.count else { throw ZipError.truncated }
            let name = String(data: data.subdata(in: nameRange), encoding: .utf8) ?? ""

            // 真实数据在本地头之后，本地头长度要重新解析（extra 字段长度与中央目录里那份可能不同）
            let local = data.subdata(in: localHeaderOffset..<(localHeaderOffset + 30))
            guard local.count == 30, read32(local, 0) == 0x04034b50 else { throw ZipError.badMagic }
            let localNameLen = Int(read16(local, 26))
            let localExtraLen = Int(read16(local, 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            guard payloadStart + compressedSize <= data.count else { throw ZipError.truncated }
            var payload = data.subdata(in: payloadStart..<(payloadStart + compressedSize))
            if method == 8 {
                // 本地头偏移 24 是 uncompressed size，拿它做输出缓冲的下界估计
                payload = try inflate(payload, expected: Int(read32(local, 24)))
            } else if method != 0 {
                throw ZipError.unsupportedMethod(method)
            }
            if !name.hasSuffix("/") {
                entries.append(Entry(name: name, data: payload))
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func findEndOfCentral(in data: Data) -> Int? {
        // EOCD 从尾部往前找，最多扫 64KB（zip 注释上限）
        let needle: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let lowerBound = max(0, data.count - 65_557)
        var i = data.count - 4
        while i >= lowerBound {
            if data[i] == needle[0], data[i + 1] == needle[1],
               data[i + 2] == needle[2], data[i + 3] == needle[3] {
                return i
            }
            i -= 1
        }
        return nil
    }

    /// raw deflate 解压：ZIP 存的是裸 deflate 流，Compression 的 ZLIB 算法正是裸流。
    static func inflate(_ input: Data, expected: Int) throws -> Data {
        #if canImport(Compression)
        return try RawDeflate.inflate(input, expected: expected)
        #else
        throw ZipError.unsupportedMethod(8)
        #endif
    }

    // MARK: - 小端读写

    static func le(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    static func le16(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    static func read32(_ data: Data, _ at: Int) -> UInt32 {
        guard at + 4 <= data.count else { return 0 }
        let b = [UInt8](data.subdata(in: at..<(at + 4)))
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    static func read16(_ data: Data, _ at: Int) -> UInt16 {
        guard at + 2 <= data.count else { return 0 }
        let b = [UInt8](data.subdata(in: at..<(at + 2)))
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }
}

/// ZIP 规范的 CRC-32（多项式 0xEDB88320）。安卓端 BackupManager 用的是 java.util.zip 的同一个表。
public enum Crc32 {

    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var c = UInt32(index)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Zip {
    /// 写侧统一走 Crc32，避免两处实现漂移。
    static func crc32(_ data: Data) -> UInt32 { Crc32.checksum(data) }
}

