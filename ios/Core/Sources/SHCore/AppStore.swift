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
    /// 自测掌握状态：nil = 还没自测过。
    /// 做成**可选**是为了兼容：旧版本存下来的库、以及安卓导来的备份都没有这个键，
    /// 若是非可选，缺字段会让整个 BackupSnapshot 解码失败，用户数据直接看没了。
    public var reviewState: String?

    public init(
        id: Int = 0, messageId: Int, subject: String, note: String = "",
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        reviewState: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.subject = subject
        self.note = note
        self.createdAt = createdAt
        self.reviewState = reviewState
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, note
        case messageId = "message_id"
        case createdAt = "created_at"
        case reviewState = "review_state"
    }

    /// 解码时缺 review_state 就当 nil，不报错（兼容旧数据）。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        messageId = try c.decode(Int.self, forKey: .messageId)
        subject = try c.decode(String.self, forKey: .subject)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decode(Int.self, forKey: .createdAt)
        reviewState = try c.decodeIfPresent(String.self, forKey: .reviewState)
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

    /// 这次启动是否成功读到了已有数据库（解码失败时为 false，用于避免误删图片）
    public private(set) var didLoadExistingData = false

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
            self.didLoadExistingData = true
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
        snapshot.messages
            .filter { $0.subject == subject }
            // 同一毫秒插入的 user/assistant 用 id 兜底，否则顺序可能翻转（Swift sort 不稳定）
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
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
    /// 返回该消息关联的图片路径：Core 不碰文件系统，由 App 层据此删文件，
    /// 否则图片会一直留在沙盒里（历史版本就是这么把磁盘吃满的）。
    @discardableResult
    public func deleteMessage(id: Int) -> String? {
        let imagePath = snapshot.messages.first { $0.id == id }?.imageUri
        snapshot.messages.removeAll { $0.id == id }
        snapshot.favorites.removeAll { $0.messageId == id }
        save()
        return imagePath
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

    /// 清空某学科；返回被删掉的图片路径（同上，交给 App 层删文件）。
    @discardableResult
    public func clearSubject(_ subject: String) -> [String] {
        let doomedMessages = snapshot.messages.filter { $0.subject == subject }
        let imagePaths = doomedMessages.compactMap(\.imageUri)
        let doomedIds = doomedMessages.map(\.id)
        snapshot.messages.removeAll { $0.subject == subject }
        snapshot.favorites.removeAll { doomedIds.contains($0.messageId) }
        save()
        return imagePaths
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

    /// 记录自测结果：mastered=true 表示「这题我会了」。找不到收藏行返回 false。
    @discardableResult
    public func setReviewed(messageId: Int, mastered: Bool) -> Bool {
        guard let i = snapshot.favorites.firstIndex(where: { $0.messageId == messageId }) else {
            return false
        }
        snapshot.favorites[i].reviewState = mastered ? "mastered" : "again"
        save()
        return true
    }

    /// 掌握状态计数，供错题本顶部显示「已掌握 X / 共 Y」。
    public func reviewCounts(subject: String?) -> (mastered: Int, again: Int, untested: Int) {
        var mastered = 0, again = 0, untested = 0
        for fav in favorites(subject: subject) where isFavoriteMessageStillThere(fav.messageId) {
            switch fav.reviewState {
            case "mastered": mastered += 1
            case "again": again += 1
            default: untested += 1
            }
        }
        return (mastered, again, untested)
    }

    private func isFavoriteMessageStillThere(_ messageId: Int) -> Bool {
        snapshot.messages.contains { $0.id == messageId }
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

    /// 删除作文；返回它的图片路径，交给 App 层删文件。
    @discardableResult
    public func deleteComposition(_ c: Composition) -> [String] {
        let imagePaths = c.imageUriList
        snapshot.compositions.removeAll { $0.id == c.id }
        save()
        return imagePaths
    }

    // MARK: 搜索

    /// 全学科搜题：按关键词在提问/回答正文里做大小写不敏感的子串匹配。
    /// 空查询返回空数组（而不是全部），避免空态页把整个库倒出来。
    public func searchMessages(query: String, subject: String? = nil, limit: Int = 60) -> [Message] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return snapshot.messages
            .filter { subject == nil || $0.subject == subject }
            .filter {
                $0.textContent.lowercased().contains(needle)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    /// 命中次数按学科汇总，搜索页顶部用来显示「语文 3 · 数学 5」。
    public func searchSubjectCounts(query: String) -> [String: Int] {
        let hits = searchMessages(query: query, limit: 100_000)
        var counts: [String: Int] = [:]
        for m in hits { counts[m.subject, default: 0] += 1 }
        return counts
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
