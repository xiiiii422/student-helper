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
