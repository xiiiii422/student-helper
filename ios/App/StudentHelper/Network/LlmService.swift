import Foundation
import SHCore

/// 跨主备两轮传递的「已经吐过字」标志。
/// 已吐字之后不许重发，否则学生看到重复段落；actor 之间传引用需要这个装箱。
final class EmittedFlag: @unchecked Sendable {
    var value = false
}

/// 设置提供者：App 层用 Keychain + UserDefaults 实现，Core 只认协议，便于测试注入。
public protocol SettingsProviding: Sendable {
    func current() async -> LlmConfig
    func fallback(for cfg: LlmConfig) async -> LlmConfig?
}

/// 直连 OpenAI 兼容接口（智谱 GLM / DeepSeek）的流式客户端。
///
/// 逐条对齐安卓 `core/network/LlmClient.kt`；判定规则本身都在 Core 的
/// `LlmPolicy` / `SseParser` / `RequestBody` 里，这个文件只管网络与循环，
/// 两端同一套规则、各写各的 IO。
///
/// 三条来自真机事故的硬约束：
/// 1. 对端过载时只发 keepalive 不出正文，连接不断，readTimeout 永不触发 → 每次尝试带墙钟预算
/// 2. 免费档限流靠退避跨不过去 → 主家耗尽后切备用 Key 再来一轮
/// 3. 混合推理模型默认开思考，只吐 reasoning_content → 请求侧关掉思考（`disableThinking`）
public actor LlmService {

    /// 等待期反馈：退避重试与切供应商都要透到 UI，否则长等待会被当成死机。
    public struct Signals: Sendable {
        public var onRetry: (@Sendable (Int, Int) -> Void)?
        public var onFallback: (@Sendable (String) -> Void)?
        public init(
            onRetry: (@Sendable (Int, Int) -> Void)? = nil,
            onFallback: (@Sendable (String) -> Void)? = nil
        ) {
            self.onRetry = onRetry
            self.onFallback = onFallback
        }
    }

    private let settings: SettingsProviding
    private let session: URLSession

    public init(settings: SettingsProviding, session: URLSession? = nil) {
        self.settings = settings
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = TimeInterval(LlmPolicy.readTimeoutSeconds)
            cfg.timeoutIntervalForResource = 600
            cfg.waitsForConnectivity = false
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: cfg)
        }
    }

    // MARK: - 对外接口

    /// 学科讲解：流式增量文本。带图自动切 VL 通道。
    public func chatStream(
        subject: String,
        userText: String,
        history: [Msg],
        imagesBase64: [String] = [],
        signals: Signals = .init()
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let cfg = await self.settings.current()
                    let fb = await self.settings.fallback(for: cfg)
                    let msgs = try PromptAssembler.chatMessages(
                        subject: subject, userText: userText, history: history
                    )
                    try await self.runStream(
                        cfg: cfg, fallback: fb, messages: msgs, imagesBase64: imagesBase64,
                        temperature: PromptAssembler.temperature(for: .chat),
                        maxTokensOverride: nil, signals: signals
                    ) { delta in
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 作文批改 / 生成范文 / 段落改写：内部同样流式收，只是攒成整串再返回。
    public func complete(
        systemPrompt: String,
        userText: String,
        imagesBase64: [String] = [],
        temperature: Double,
        maxTokensOverride: Int? = nil,
        signals: Signals = .init()
    ) async throws -> String {
        let cfg = await settings.current()
        let fb = await settings.fallback(for: cfg)
        let msgs = [Msg("system", systemPrompt), Msg("user", userText)]
        var collected = ""
        try await runStream(
            cfg: cfg, fallback: fb, messages: msgs, imagesBase64: imagesBase64,
            temperature: temperature, maxTokensOverride: maxTokensOverride, signals: signals
        ) { delta in
            collected += delta
        }
        return collected
    }

    /// 连通性检查：发一个 8-token 小请求，成功返回模型名。
    public func ping() async throws -> String {
        try await pingWith(await settings.current())
    }

    /// 主/备两家现在都在回答链路里，只测主家会把「主家限流、备用其实通」误报成「服务坏了」。
    /// 并发分别测，返回顺序与「主家在前」一致，方便 UI 直接铺。
    public func pingAll() async -> [PingResult] {
        let cfg = await settings.current()
        var configs = [cfg]
        if let fb = await settings.fallback(for: cfg) { configs.append(fb) }

        var results: [PingResult] = []
        await withTaskGroup(of: PingResult.self) { group in
            for c in configs {
                group.addTask { [self] in
                    do {
                        return PingResult(provider: Presets.short(of: c.providerId), ok: true,
                                          detail: try await pingWith(c))
                    } catch let e as LlmError {
                        return PingResult(provider: Presets.short(of: c.providerId), ok: false,
                                          detail: LlmPolicy.pingDetail(e.message))
                    } catch {
                        return PingResult(provider: Presets.short(of: c.providerId), ok: false,
                                          detail: LlmPolicy.pingDetail(describe(error)))
                    }
                }
            }
            for await r in group { results.append(r) }
        }
        return configs.compactMap { c in
            let name = Presets.short(of: c.providerId)
            return results.first { $0.provider == name }
        }
    }

    // MARK: - 内部实现

    private func request(_ cfg: LlmConfig, _ body: Data) -> URLRequest {
        var req = URLRequest(url: URL(string: cfg.endpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer " + cfg.apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = body
        return req
    }

    private func pingWith(_ cfg: LlmConfig) async throws -> String {
        let channel = cfg.channel(hasImage: false)
        let data = try RequestBody.body(
            channel: channel, temperature: 0,
            messages: [Msg("user", "你好")], stream: false,
            maxTokensOverride: 8, disableThinking: cfg.disableThinking
        )
        let (bytes, response) = try await session.bytes(for: request(cfg, data))
        guard let http = response as? HTTPURLResponse else { throw LlmError.empty("无 HTTP 响应") }
        var body = Data()
        for try await byte in bytes { body.append(byte) }
        let text = String(data: body, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else {
            throw LlmError.http(http.statusCode, LlmPolicy.utf16Prefix(text, 120))
        }
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let model = obj["model"] as? String, !model.isEmpty {
            return model
        }
        return channel.model
    }

    /// 先走主供应商，耗尽后若判定为「限流」且尚未吐字，切到备用 Key 再来一轮。
    private func runStream(
        cfg: LlmConfig,
        fallback: LlmConfig?,
        messages: [Msg],
        imagesBase64: [String],
        temperature: Double,
        maxTokensOverride: Int?,
        signals: Signals,
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        let emitted = EmittedFlag()
        do {
            try await drain(
                cfg: cfg, messages: messages, imagesBase64: imagesBase64, temperature: temperature,
                maxTokensOverride: maxTokensOverride, maxAttempts: LlmPolicy.maxRetries,
                signals: signals, emitted: emitted, onDelta: onDelta
            )
        } catch {
            let message = errorMessage(of: error)
            let canSwitch = fallback != nil && !emitted.value && LlmPolicy.isRateLimited(message)
            guard canSwitch, let fallback else { throw error }
            signals.onFallback?(Presets.label(of: fallback.providerId))
            try await drain(
                cfg: fallback, messages: messages, imagesBase64: imagesBase64, temperature: temperature,
                maxTokensOverride: maxTokensOverride, maxAttempts: LlmPolicy.fallbackRetries,
                signals: signals, emitted: emitted, onDelta: onDelta
            )
        }
    }

    /// 单一供应商的重试窗口：成功则返回，次数耗尽则抛。
    private func drain(
        cfg: LlmConfig,
        messages: [Msg],
        imagesBase64: [String],
        temperature: Double,
        maxTokensOverride: Int?,
        maxAttempts: Int,
        signals: Signals,
        emitted: EmittedFlag,
        onDelta: @Sendable (String) async -> Void
    ) async throws {
        let channel = cfg.channel(hasImage: !imagesBase64.isEmpty)
        let bodyData = try RequestBody.body(
            channel: channel, temperature: temperature, messages: messages,
            imagesBase64: imagesBase64, stream: true,
            maxTokensOverride: maxTokensOverride, disableThinking: cfg.disableThinking
        )
        var lastError = ""

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            var done = false
            var needRetry = false
            let attemptStart = Date()

            do {
                let (bytes, response) = try await session.bytes(for: request(cfg, bodyData))
                guard let http = response as? HTTPURLResponse else {
                    throw LlmError.empty("无 HTTP 响应")
                }
                if !(200..<300).contains(http.statusCode) {
                    var body = Data()
                    for try await byte in bytes { body.append(byte) }
                    lastError = LlmError.http(
                        http.statusCode,
                        LlmPolicy.utf16Prefix(String(data: body, encoding: .utf8) ?? "", 120)
                    ).message
                    needRetry = LlmPolicy.retryStatusCodes.contains(http.statusCode) && !emitted.value
                } else {
                    streamLoop: for try await line in bytes.lines {
                        try Task.checkCancellation()
                        // keepalive 会不断重置 socket 读超时，所以「连上了但不出字」必须单独卡
                        if !emitted.value,
                           Date().timeIntervalSince(attemptStart) > Double(LlmPolicy.firstTokenBudgetSeconds) {
                            lastError = LlmError.noFirstToken.message
                            needRetry = true
                            break streamLoop
                        }
                        switch SseParser.handle(line: line) {
                        case .done:
                            done = true
                            break streamLoop
                        case .delta(let text):
                            emitted.value = true
                            await onDelta(text)
                        case .upstreamError(let text):
                            lastError = LlmPolicy.utf16Prefix(text, 160)
                            if LlmPolicy.isBusy(text) && !emitted.value {
                                needRetry = true
                                break streamLoop
                            }
                            throw LlmError.empty("模型返回错误：\(lastError)")
                        case .ignored:
                            continue
                        }
                    }
                    if !done && !needRetry && !emitted.value { needRetry = true }
                }
            } catch let e as LlmError {
                // 「模型返回错误」这类是确定性失败，不重试也不换供应商
                if case .empty(let raw) = e, raw.hasPrefix("模型返回错误") { throw e }
                if emitted.value { throw e }
                lastError = e.message
                needRetry = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if emitted.value { throw error }
                lastError = describe(error)
                needRetry = true
            }

            if done { return }
            if needRetry && attempt < maxAttempts {
                signals.onRetry?(attempt + 1, maxAttempts)
                let seconds = LlmPolicy.backoffSeconds(attempt: attempt)
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                continue
            }
            if needRetry { throw LlmError.busy(lastError) }
            throw LlmError.empty(lastError)
        }
    }

    private func errorMessage(of error: Error) -> String {
        if let e = error as? LlmError { return e.message }
        return describe(error)
    }
}

/// 很多底层错误（如 NSURLError 家族）的 localizedDescription 为空，
/// 只取文案会让「连接失败：null」这类没法排查的东西冒出来，所以统一带上类型名。
func describe(_ error: Error) -> String {
    let ns = error as NSError
    let text = error.localizedDescription
    if !text.isEmpty { return text }
    return "\(ns.domain)\(ns.code)"
}
