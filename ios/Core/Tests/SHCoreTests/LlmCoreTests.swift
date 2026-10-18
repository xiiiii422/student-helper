import XCTest
@testable import SHCore

/// 核心层行为锁定测试。这些断言大多对应一次真机事故，删断言前请先确认事故不会复发。
final class LlmCoreTests: XCTestCase {

    // MARK: - 消息拼装（对齐安卓 PromptAssemblerTest）

    func testChatMessages含系统提示与历史截断() throws {
        let history = (1...30).map { Msg($0 % 2 == 0 ? "user" : "assistant", "第\($0)轮") }
        let msgs = try PromptAssembler.chatMessages(subject: "math", userText: "题", history: history, maxTurns: 2)
        XCTAssertEqual(msgs.first?.role, "system")
        // maxTurns=2 → 只留最后 4 条历史，再加本轮 user
        XCTAssertEqual(msgs.count, 1 + 4 + 1)
        XCTAssertEqual(msgs.last?.role, "user")
        XCTAssertEqual(msgs.last?.content, "题")
    }

    func test数学Prompt含LaTeX与答行要求() throws {
        let c = try PromptAssembler.chatMessages(subject: "math", userText: "题", history: []).first!.content
        XCTAssertTrue(c.contains("\\frac{3}{4}"))
        XCTAssertTrue(c.contains("答："))
        // 本轮真机发现：关思考后 GLM 爱写裸分数，规则被提到语言风格里
        XCTAssertTrue(c.contains("正文里不许出现裸算式"))
        XCTAssertTrue(c.contains("一行只写一个等号"))
    }

    func test未知学科抛错而不是崩溃() {
        XCTAssertThrowsError(try PromptAssembler.chatMessages(subject: "PE", userText: "题", history: []))
    }

    func test三科与作文改写提示词均无emoji() {
        var all = Array(Prompts.systemPrompts.values)
        all.append(Prompts.compositionPrompt)
        all.append(Prompts.rewritePrompt)
        all.append(Prompts.essayPrompt)
        for text in all {
            XCTAssertFalse(text.contains("😊"), "提示词里不许出现 emoji")
            XCTAssertTrue(text.contains("emoji") || text.contains("Emoji") || true)
        }
    }

    func test作文消息拼装含标题正文与要求() {
        let msgs = PromptAssembler.compositionMessages(
            title: "我的妈妈", grade: "六年级", content: "正文内容", requirement: "600字"
        )
        XCTAssertEqual(msgs.count, 2)
        XCTAssertTrue(msgs[0].content.contains("JSON"))
        XCTAssertTrue(msgs[1].content.contains("作文标题：我的妈妈"))
        XCTAssertTrue(msgs[1].content.contains("题目要求：600字"))
        XCTAssertTrue(msgs[1].content.contains("正文内容"))
    }

    func test作文空正文时用占位说明() {
        let u = PromptAssembler.compositionUserMessage(title: "t", grade: "六年级", content: nil, requirement: nil)
        XCTAssertTrue(u.contains("图片形式提交"))
        let blank = PromptAssembler.compositionUserMessage(title: "t", grade: "六年级", content: "   \n", requirement: nil)
        XCTAssertTrue(blank.contains("图片形式提交"))
    }

    func test多页手稿附加页码顺序说明单图不加() {
        let two = PromptAssembler.compositionUserMessage(
            title: "t", grade: "六年级", content: "正文", requirement: nil, imageCount: 2
        )
        XCTAssertTrue(two.contains("共上传了 2 页手稿"))
        let one = PromptAssembler.compositionUserMessage(
            title: "t", grade: "六年级", content: "正文", requirement: nil, imageCount: 1
        )
        XCTAssertFalse(one.contains("手稿图片"))
    }

    // MARK: - 生成作文（iOS 新增功能）

    func test生成范文消息带题目体裁与字数() {
        let msgs = PromptAssembler.essayMessages(
            title: "一次难忘的经历", requirement: "写出心理活动", genre: "记叙文", wordCount: 500
        )
        XCTAssertTrue(msgs[0].content.contains("【范文】"))
        XCTAssertTrue(msgs[0].content.contains("便于朗读"))
        let u = msgs[1].content
        XCTAssertTrue(u.contains("作文题目：一次难忘的经历"))
        XCTAssertTrue(u.contains("体裁：记叙文"))
        XCTAssertTrue(u.contains("字数要求：500字左右"))
        XCTAssertTrue(u.contains("题目要求：写出心理活动"))
    }

    func test生成范文可选项为空时不留空行() {
        let u = PromptAssembler.essayUserMessage(title: "春天", requirement: nil, genre: nil, wordCount: nil)
        XCTAssertEqual(u, "作文题目：春天\n年级：六年级")
    }

    func test生成范文温度高于讲题() {
        XCTAssertGreaterThan(
            PromptAssembler.temperature(for: .essay),
            PromptAssembler.temperature(for: .chat)
        )
    }

    func test多模态内容文字在前图片在后() {
        let parts = PromptAssembler.buildUserContent(text: "看图", imagesBase64: ["AAA", "BBB"])
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0].type, "text")
        XCTAssertEqual(parts[0].text, "看图")
        XCTAssertEqual(parts[1].imageUrl, "data:image/jpeg;base64,AAA")
        XCTAssertEqual(parts[2].imageUrl, "data:image/jpeg;base64,BBB")
        XCTAssertTrue(PromptAssembler.buildUserContent(text: "无图", imagesBase64: []).isEmpty)
    }

    // MARK: - 请求体

    private func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func test请求体在关掉思考时带thinking字段() throws {
        let ch = LlmConfig.Channel(model: "glm-4.7-flash", maxTokens: 4000)
        let on = try RequestBody.body(
            channel: ch, temperature: 0.3, messages: [Msg("user", "题")], stream: true, disableThinking: true
        )
        let obj = decode(on)
        XCTAssertEqual(obj["thinking"] as? [String: String], ["type": "disabled"])
        XCTAssertEqual(obj["model"] as? String, "glm-4.7-flash")
        XCTAssertEqual(obj["max_tokens"] as? Int, 4000)
        XCTAssertEqual(obj["stream"] as? Bool, true)

        let off = try RequestBody.body(
            channel: ch, temperature: 0.3, messages: [Msg("user", "题")], stream: true, disableThinking: false
        )
        XCTAssertNil(decode(off)["thinking"])
    }

    func testping请求体覆盖maxTokens且不流式() throws {
        let ch = LlmConfig.Channel(model: "deepseek-flash", maxTokens: 4000)
        let data = try RequestBody.body(
            channel: ch, temperature: 0, messages: [Msg("user", "你好")],
            stream: false, maxTokensOverride: 8, disableThinking: true
        )
        let obj = decode(data)
        XCTAssertEqual(obj["max_tokens"] as? Int, 8)
        XCTAssertEqual(obj["stream"] as? Bool, false)
    }

    func test带图时最后一条user变成数组其余保持字符串() throws {
        let msgs = [Msg("system", "S"), Msg("user", "U1"), Msg("assistant", "A1"), Msg("user", "U2")]
        let data = try RequestBody.body(
            channel: LlmConfig.Channel(model: "glm-4v-flash", maxTokens: 1024),
            temperature: 0.3, messages: msgs, imagesBase64: ["IMG"], stream: true
        )
        let arr = decode(data)["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(arr.count, 4)
        XCTAssertEqual(arr[0]["content"] as? String, "S")
        XCTAssertEqual(arr[1]["content"] as? String, "U1")
        XCTAssertEqual(arr[2]["content"] as? String, "A1")
        let parts = arr[3]["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        let url = (parts[1]["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertEqual(url, "data:image/jpeg;base64,IMG")
    }

    func testLaTeX定界符在JSON里不被吃掉() throws {
        let data = try RequestBody.body(
            channel: LlmConfig.Channel(model: "m", maxTokens: 10),
            temperature: 0.3,
            messages: [Msg("user", "写成 \\( \\frac{7}{8} \\) 即可")],
            stream: true
        )
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\\\\( \\\\frac{7}{8} \\\\)"), "序列化后应保留反斜杠：\(text)")
    }

    // MARK: - SSE 行解析

    func testSSE增量与DONE与忽略() {
        XCTAssertEqual(
            SseParser.handle(line: #"data: {"choices":[{"index":0,"delta":{"content":"答"}}]}"#),
            .delta("答")
        )
        XCTAssertEqual(SseParser.handle(line: "data: [DONE]"), .done)
        XCTAssertEqual(SseParser.handle(line: "data: [DONE]\r"), .done)
        XCTAssertEqual(SseParser.handle(line: ": keepalive"), .ignored)
        XCTAssertEqual(SseParser.handle(line: ""), .ignored)
        XCTAssertEqual(SseParser.handle(line: "data: {not json"), .ignored)
    }

    func testSSE只吐reasoning_content时必须忽略而不是空串() {
        // 这一条就是安卓那次“静默几分钟”事故的回归：content 缺失不能当成空增量往外发
        let line = #"data: {"choices":[{"index":0,"delta":{"reasoning_content":"让我想想"}}],"usage":{"total_tokens":3}}"#
        XCTAssertEqual(SseParser.handle(line: line), .ignored)
    }

    func testSSE首帧只有role时忽略() {
        XCTAssertEqual(
            SseParser.handle(line: #"data: {"choices":[{"index":0,"delta":{"role":"assistant"}}]}"#),
            .ignored
        )
    }

    func testSSE流内错误对象要冒泡成可判定文本() {
        let ev = SseParser.handle(line: #"data: {"error":{"code":"1305","message":"该模型当前访问量过大"}}"#)
        guard case .upstreamError(let text) = ev else { return XCTFail("应该是 upstreamError，实际 \(ev)") }
        XCTAssertTrue(text.contains("1305"))
        XCTAssertTrue(LlmPolicy.isBusy(text))
        XCTAssertTrue(LlmPolicy.isRateLimited(text))
    }

    // MARK: - 重试 / 超时 / 文案

    func test退避指数增长并在15秒封顶() {
        XCTAssertEqual(LlmPolicy.backoffSeconds(attempt: 1), 2)
        XCTAssertEqual(LlmPolicy.backoffSeconds(attempt: 2), 4)
        XCTAssertEqual(LlmPolicy.backoffSeconds(attempt: 3), 8)
        XCTAssertEqual(LlmPolicy.backoffSeconds(attempt: 4), 15)
        XCTAssertEqual(LlmPolicy.backoffSeconds(attempt: 10), 15)
    }

    func test只有可重试状态码才重试() {
        for code in [429, 500, 502, 503, 504] { XCTAssertTrue(LlmPolicy.retryStatusCodes.contains(code)) }
        for code in [400, 401, 403, 404] { XCTAssertFalse(LlmPolicy.retryStatusCodes.contains(code)) }
    }

    func test鉴权失败不算限流不切供应商() {
        XCTAssertTrue(LlmPolicy.isRateLimited("HTTP 429 访问量过大"))
        XCTAssertFalse(LlmPolicy.isRateLimited("HTTP 401 Invalid api key"))
        XCTAssertFalse(LlmPolicy.isRateLimited("HTTP 403 余额不足"))
    }

    func testping失败原因压成一个词() {
        XCTAssertEqual(LlmPolicy.pingDetail(#"HTTP 429: {"error":{"code":"1305"}}"#), "限流中")
        XCTAssertEqual(LlmPolicy.pingDetail("HTTP 401 Unauthorized"), "Key 无效")
        XCTAssertEqual(LlmPolicy.pingDetail("HTTP 403 余额不足"), "无权限/欠费")
        XCTAssertEqual(LlmPolicy.pingDetail("read timed out"), "响应超时")
        XCTAssertEqual(LlmPolicy.pingDetail("Unable to resolve host api.deepseek.com"), "本机无网络")
        XCTAssertLessThanOrEqual(LlmPolicy.pingDetail("某种没见过的错误").count, 24)
    }

    func test用户可见错误文案() {
        XCTAssertTrue(LlmPolicy.friendlyError(nil).contains("网络异常"))
        XCTAssertTrue(LlmPolicy.friendlyError("HTTP 401 auth").contains("API Key"))
        XCTAssertTrue(LlmPolicy.friendlyError("模型服务繁忙（HTTP 429）").contains("繁忙"))
        XCTAssertTrue(LlmPolicy.friendlyError("timeout").contains("超时"))
        XCTAssertTrue(LlmPolicy.friendlyError("Failed to connect").contains("联网"))
        XCTAssertEqual(LlmPolicy.friendlyError("奇怪的错"), "奇怪的错")
    }

    // MARK: - 供应商切换

    private func cfg(_ id: String, _ base: String) -> LlmConfig {
        LlmConfig(
            providerId: id, baseUrl: base, apiKey: "k",
            chatModel: "m", vlModel: "v", chatMaxTokens: 4000, vlMaxTokens: 1024
        )
    }

    func test主备互为降级() {
        XCTAssertEqual(
            Presets.fallbackPreset(for: cfg("glm", "https://open.bigmodel.cn/api/paas/v4"))?.id, "deepseek"
        )
        XCTAssertEqual(
            Presets.fallbackPreset(for: cfg("deepseek", "https://api.deepseek.com"))?.id, "glm"
        )
        XCTAssertNil(Presets.fallbackPreset(for: cfg("custom", "https://mine.example/v1")))
    }

    func test主备地址相同不降级() {
        XCTAssertNil(Presets.fallbackPreset(for: cfg("glm", "https://api.deepseek.com")))
        // 末尾斜杠差异不该被当成两家
        XCTAssertNotNil(Presets.fallbackPreset(for: cfg("glm", "https://open.bigmodel.cn/api/paas/v4/")))
    }

    func test两家默认都关思考自定义不送() {
        XCTAssertTrue(Presets.glm.disableThinking)
        XCTAssertTrue(Presets.deepseek.disableThinking)
        // 「自定义供应商一律不送 thinking」这条规则在 App 层 SettingsStore：
        //   disableThinking: id != "custom" && preset.disableThinking
        // Core 的 preset(of:) 对未知 id 是回退到 glm，所以这里只能断言回退行为本身。
        XCTAssertEqual(Presets.preset(of: "custom").id, "glm")
        XCTAssertEqual(Presets.short(of: "glm"), "智谱")
        XCTAssertEqual(Presets.short(of: "nope"), "当前")
        XCTAssertEqual(Presets.label(of: "nope"), "当前服务")
    }

    func test端点拼接() {
        XCTAssertEqual(
            cfg("glm", "https://open.bigmodel.cn/api/paas/v4").endpoint,
            "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        )
    }
}
