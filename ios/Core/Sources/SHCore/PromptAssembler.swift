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
        maxTurns: Int = defaultMaxTurns,
        gradeMode: Bool = false
    ) throws -> [Msg] {
        guard let base = Prompts.systemPrompts[subject] else {
            throw LlmError.unknownSubject(subject)
        }
        // 批改模式：学生照片上已经写了答案，让老师先判对错再讲
        let system = gradeMode ? base + "\n\n" + Prompts.gradeModeNote : base
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
    /// 设置页的 Base URL 拼出来的地址不是合法 URL（用户手改错一个字就会命中）
    case badBaseURL(String)

    /// 与安卓 IllegalStateException 文案对齐，UI 侧的友好化映射两边共用同一份。
    public var message: String {
        switch self {
        case .unknownSubject(let s): return "unknown subject: \(s)"
        case .http(let code, let body): return "HTTP \(code) \(body)"
        case .busy(let last): return "模型服务繁忙（\(last)），请稍后重试"
        case .noFirstToken: return "\(LlmPolicy.firstTokenBudgetSeconds)s 内没等到首个字词"
        case .empty(let raw): return raw.isEmpty ? "响应提前结束，请重试" : raw
        case .badBaseURL(let raw): return "接口地址格式不对：\(raw)，请到「模型服务设置」检查"
        }
    }
}
