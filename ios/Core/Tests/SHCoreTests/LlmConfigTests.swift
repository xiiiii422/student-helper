import XCTest
@testable import SHCore

/// 模型通道选择测试。
///
/// 关键是「视觉模型为空」这个真实场景：自定义服务只填对话模型时，
/// 以前会拿空模型名去请求视觉接口，供应商返回 400 且不在重试列表里，
/// 表现就是拍照问了没反应。
final class LlmConfigTests: XCTestCase {

    private func config(vl: String, chat: String = "chat-model") -> LlmConfig {
        LlmConfig(
            providerId: "custom", baseUrl: "https://example.com/v1", apiKey: "k",
            chatModel: chat, vlModel: vl,
            chatMaxTokens: 4000, vlMaxTokens: 1024, disableThinking: false
        )
    }

    func test有图时用视觉模型() {
        let c = config(vl: "vl-model")
        XCTAssertEqual(c.channel(hasImage: true).model, "vl-model")
        XCTAssertEqual(c.channel(hasImage: true).maxTokens, 1024)
    }

    func test无图时用对话模型() {
        let c = config(vl: "vl-model")
        XCTAssertEqual(c.channel(hasImage: false).model, "chat-model")
        XCTAssertEqual(c.channel(hasImage: false).maxTokens, 4000)
    }

    func test视觉模型为空时回退到对话模型() {
        let c = config(vl: "")
        let ch = c.channel(hasImage: true)
        XCTAssertEqual(ch.model, "chat-model", "不能拿空模型名去请求")
        XCTAssertEqual(ch.maxTokens, 4000)
    }

    func test视觉模型只有空格也视为空() {
        let c = config(vl: "   ")
        XCTAssertEqual(c.channel(hasImage: true).model, "chat-model")
    }

    func test预设两家都有视觉模型() {
        for preset in Presets.all {
            XCTAssertFalse(
                preset.vlModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(preset.id) 缺视觉模型，拍照问询会挂"
            )
        }
    }
}
