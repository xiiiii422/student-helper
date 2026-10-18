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

public struct StrengthItem: Codable, Equatable, Identifiable {
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

public struct IssueItem: Codable, Equatable, Identifiable {
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

public struct RewriteItem: Codable, Equatable, Identifiable {
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
