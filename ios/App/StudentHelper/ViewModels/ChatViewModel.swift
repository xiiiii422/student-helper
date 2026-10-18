import Foundation
import SwiftUI
import UIKit
import SHCore

/// 三科聊天页的状态容器，行为逐条对齐安卓 `ui/shared/ChatViewModel.kt`
/// + `data/repository/ChatRepository.kt`。
@MainActor
final class ChatViewModel: ObservableObject {

    let subject: String

    @Published private(set) var messages: [Message] = []
    @Published private(set) var streaming = false
    /// 流式期间的气泡文本；null 表示当前没有进行中的回答。
    @Published private(set) var liveAssistantText: String? = nil
    /// 等待期状态提示（“模型服务繁忙，正在重试 2/2”）。只有三个跳动的点会被当成卡死。
    @Published private(set) var statusHint: String? = nil
    /// 发送失败常驻对话流：snackbar 几秒就消失，学生抬头时已经看不到了。
    @Published private(set) var sendFailure: String? = nil
    @Published private(set) var favoritedIds: Set<Int> = []
    @Published private(set) var ocrWorking = false
    @Published var pendingOcr: PendingOcr? = nil
    @Published var error: String? = nil

    private let store: AppStore
    private let llm: LlmService
    private let speech: SpeechService
    private var streamTask: Task<Void, Never>?

    /// Room 落盘最小间隔，与安卓 FLUSH_INTERVAL_MS 同值：流式期间不每字写盘。
    private static let flushIntervalNanos: UInt64 = 300_000_000

    init(subject: String, store: AppStore, llm: LlmService, speech: SpeechService) {
        self.subject = subject
        self.store = store
        self.llm = llm
        self.speech = speech
        // 先清理上次进程被杀遗留的流式占位，再订阅历史
        store.cleanupStale(subject: subject)
        reload()
    }

    func reload() {
        messages = store.messages(subject: subject)
        favoritedIds = Set(store.favorites(subject: subject).map(\.messageId))
    }

    // MARK: - 发送

    func sendText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        launchSend(userText: text, imageUri: nil, imageBase64: nil, ocrConfidence: nil)
    }

    func retryLast() {
        guard !streaming else { return }
        // 删掉最后一次提问之后的 AI 残句，用原提问重新生成
        let history = store.messages(subject: subject)
        guard let lastUserIdx = history.lastIndex(where: { $0.role == "user" }) else { return }
        let doomed = history[(lastUserIdx + 1)...].filter { $0.role == "assistant" }
        for m in doomed { store.deleteMessage(id: m.id) }
        let lastUser = history[lastUserIdx]
        let imageBase64 = lastUser.imageUri.flatMap { ImageCodec.base64FromFile(path: $0) }
        launchSend(
            userText: lastUser.textContent,
            imageUri: lastUser.imageUri,
            imageBase64: imageBase64,
            ocrConfidence: lastUser.ocrConfidence,
            skipUserInsert: true
        )
    }

    /// 统一发送入口：插用户消息 → 占位气泡 → 收流（节流落盘）→ finally 定稿。
    private func launchSend(
        userText: String,
        imageUri: String?,
        imageBase64: String?,
        ocrConfidence: Double?,
        skipUserInsert: Bool = false
    ) {
        guard !streaming else { return }
        streaming = true
        liveAssistantText = ""
        sendFailure = nil
        statusHint = nil
        speech.stop()

        if !skipUserInsert {
            store.insert(
                Message(
                    subject: subject, role: "user", textContent: userText,
                    imageUri: imageUri, ocrConfidence: ocrConfidence
                )
            )
        }
        reload()

        // 历史窗口：最近 16 条，去掉刚插入的这条提问（与安卓 sendAndStream 一致）
        let recent = store.recentMessages(subject: subject, limit: 16)
        let history = recent.dropLast().map { Msg($0.role, $0.textContent) }
        let images = [imageBase64].compactMap { $0 }
        let placeholder = store.insert(
            Message(subject: subject, role: "assistant", textContent: "", isStreaming: true)
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            var accumulated = ""
            var lastFlush = UInt64(0)
            var failure: String?

            let signals = LlmService.Signals(
                onRetry: { attempt, max in
                    Task { @MainActor [weak self] in
                        self?.statusHint = "模型服务繁忙，正在重试（\(attempt)/\(max)）"
                    }
                },
                onFallback: { label in
                    Task { @MainActor [weak self] in
                        self?.statusHint = "当前供应商限流，已切换到\(label)"
                    }
                }
            )

            do {
                // LlmService 是 actor：取流这一步就要 await，拿到流之后再逐条遍历
                let stream = await self.llm.chatStream(
                    subject: self.subject, userText: userText,
                    history: history, imagesBase64: images, signals: signals
                )
                for try await delta in stream {
                    accumulated += delta
                    self.liveAssistantText = accumulated
                    if self.statusHint != nil { self.statusHint = nil }
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now - lastFlush >= Self.flushIntervalNanos {
                        lastFlush = now
                        self.store.update(Self.finalized(placeholder, text: accumulated, streaming: true))
                    }
                }
            } catch is CancellationError {
                // 用户主动停止：保留已生成的部分
            } catch {
                failure = LlmPolicy.friendlyError(
                    (error as? LlmError)?.message ?? error.localizedDescription
                )
            }

            // finally：一个字都没有就把占位删掉，别留僵尸气泡
            if accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.store.deleteMessage(id: placeholder.id)
            } else {
                self.store.update(Self.finalized(placeholder, text: accumulated, streaming: false))
            }
            self.streaming = false
            self.liveAssistantText = nil
            self.statusHint = nil
            self.sendFailure = failure
            self.reload()
            Haptics.success()
            if failure == nil, self.speech.autoSpeak { self.speech.speak(accumulated) }
        }
    }

    private static func finalized(_ base: Message, text: String, streaming: Bool) -> Message {
        var m = base
        m.textContent = text
        m.isStreaming = streaming
        return m
    }

    func stopStreaming() {
        streamTask?.cancel()
    }

    // MARK: - 其它动作

    func deleteMessage(id: Int) {
        store.deleteMessage(id: id)
        reload()
    }

    func clearSubject() {
        speech.stop()
        store.clearSubject(subject)
        reload()
    }

    func toggleFavorite(messageId: Int) {
        if store.toggleFavorite(messageId: messageId) == nil {
            error = "这条消息已经不在历史里了"
        }
        reload()
    }

    func speak(_ text: String) { speech.speak(text) }
    func stopSpeaking() { speech.stop() }

    func consumeError() { error = nil }

    // MARK: - 图片提问

    /// 处理一张已保存到本地的图片：压缩 → OCR → 弹出确认，与安卓 processImageFile 同流程。
    func processImage(at url: URL) {
        guard !ocrWorking else { return }
        ocrWorking = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.ocrWorking = false }
            guard let image = UIImage(contentsOfFile: url.path) else {
                self.error = "图片读取失败，请重拍一张"
                return
            }
            let compressed = ImageCodec.compress(image)
            guard let base64 = ImageCodec.base64(from: compressed) else {
                self.error = "图片编码失败"
                return
            }
            let recognized = await OcrService.recognize(image: compressed)
            // 分学科决策（规则在 SHCore.OcrRouter，与安卓同一套）：
            // 数学几乎总要带图——本地认不出分式/根号，且手写数字错一位整题就讲歪；
            // 语文/英语的多行长题也要带图；只有干净的高置信度短文本才走纯文字。
            let decided = OcrRouter.decide(
                text: recognized.text,
                confidence: recognized.confidence,
                subject: self.subject
            )
            self.pendingOcr = PendingOcr(
                imageUri: url.path,
                text: recognized.text,
                confidence: recognized.confidence,
                suggestedMode: SendMode(decided),
                imageBase64: base64
            )
        }
    }

    /// 确认发送（来自 OCR 对话框）：只发文字时不带图，省视觉通道的额度。
    func confirmPendingSend(text: String, mode: SendMode) {
        guard let pending = pendingOcr else { return }
        pendingOcr = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 「只看图」模式下识别文字常常是空的，得补一句人话，否则等于发了条空白提问
        let prompt = (mode == .imageOnly && trimmed.isEmpty) ? "请帮我看看图片里的这道题" : text
        launchSend(
            userText: prompt,
            imageUri: pending.imageUri,
            imageBase64: mode == .textOnly ? nil : pending.imageBase64,
            ocrConfidence: mode == .imageOnly ? nil : pending.confidence
        )
    }
}

/// 拍照/手写后、发送前的待确认状态。
struct PendingOcr: Identifiable {
    /// 一次只会有一个待确认图片，用原图路径当 id 足够
    var id: String { imageUri }
    let imageUri: String
    let text: String
    let confidence: Double
    let suggestedMode: SendMode
    let imageBase64: String
}

enum SendMode: Hashable {
    /// 只用识别出的文字提问（便宜、快）
    case textOnly
    /// 文字 + 原图一起发，交给视觉通道（题目是图片排版时更准）
    case textAndImage
    /// 识别结果不可信，只发图让模型自己看
    case imageOnly

    init(_ mode: OcrMode) {
        switch mode {
        case .textOnly: self = .textOnly
        case .textAndImage: self = .textAndImage
        case .imageOnly: self = .imageOnly
        }
    }

    var label: String {
        switch self {
        case .textOnly: return "只用识别出的文字"
        case .textAndImage: return "文字连同原图一起问"
        case .imageOnly: return "只发图片，让老师自己看"
        }
    }
}

/// 空态里的「可以这样问」，与安卓 examplesFor 逐条一致。
enum ChatExamples {
    static func forSubject(_ subject: String) -> [String] {
        switch subject {
        case "chinese":
            return [
                "“春风又绿江南岸”里的“绿”字好在哪里？",
                "修改病句：他大约估计这件事是他做的。",
                "《少年闰土》表达了作者怎样的感情？",
            ]
        case "english":
            return [
                "He ___ (go) to school every day. 应该填什么？",
                "on time 和 in time 有什么区别？",
                "用 there is / there are 各造一个句子",
            ]
        default:
            return [
                "3/4 + 1/8 = ?",
                "一个圆的半径是 3cm，面积是多少？",
                "一件衣服打八折后是 120 元，原价多少钱？",
            ]
        }
    }

    static let followUps = ["再讲一遍", "换个方法讲", "直接告诉我答案", "再出一道同类题"]
}
