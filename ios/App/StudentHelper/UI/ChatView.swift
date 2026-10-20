import SwiftUI
import UIKit
import SHCore

/// 三科共用聊天页，对齐安卓 `ui/shared/ChatScreen.kt`：
/// 大标题、iMessage 气泡、空态例题、失败常驻卡片、追问快捷入口、流式吸底。
struct ChatView: View {
    /// VM 由 AppContainer 持有并注入：切 Tab 不再销毁它，流式回答不会因为切走丢失
    @ObservedObject var vm: ChatViewModel
    let title: String
    @Binding var tabSelection: BottomTab

    @State private var input = ""
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showClearConfirm = false
    @State private var previewUri: String?
    @State private var pendingDelete: Message?

    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router
    /// 订阅朗读状态：以前气泡永远传 spokenChunk=nil，既没有「正在念」高亮，
    /// 菜单也永远显示「朗读这条」而不是「停止」，用户根本停不下来。
    @EnvironmentObject private var speech: SpeechService

    init(
        title: String,
        subject: String,
        tabSelection: Binding<BottomTab>,
        vm: ChatViewModel
    ) {
        self.title = title
        self._tabSelection = tabSelection
        self.vm = vm
        precondition(vm.subject == subject, "ChatView 的 subject 必须与注入的 VM 一致")
    }

    private var accent: Color { SubjectColor.forSubject(vm.subject) }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            InputBarView(
                text: $input,
                enabled: !vm.streaming,
                accent: accent,
                isStreaming: vm.streaming,
                onTakePhoto: { showCamera = true },
                onPickImage: { showLibrary = true },
                onSend: {
                    vm.sendText(input)
                    input = ""
                },
                onStop: { vm.stopStreaming() }
            )
        }
        .background(palette.background)
        .sheet(isPresented: $showCamera) { cameraSheet }
        .sheet(isPresented: $showLibrary) { librarySheet }
        .sheet(item: $vm.pendingOcr) { pending in
            OcrConfirmSheet(pending: pending) { text, mode, grade in
                vm.confirmPendingSend(text: text, mode: mode, gradeMode: grade)
            } onCancel: {
                vm.pendingOcr = nil
            }
        }
        .fullScreenCover(item: Binding<IdentifiableString?>(
            get: { previewUri.asIdentifiable },
            set: { if $0 == nil { previewUri = nil } }
        )) { item in
            PreviewImageView(uri: item.value, onClose: { previewUri = nil })
        }
        .confirmationDialog(
            "清空「\(title)」的全部对话？",
            isPresented: $showClearConfirm, titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) { vm.clearSubject() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清本学科的对话与对应收藏，作文与其它学科不受影响。")
        }
        .alert("删除这条消息？", isPresented: deleteDialogShown) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id { vm.deleteMessage(id: id) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("收藏过这条的话，收藏记录也会一起删除，不可恢复。")
        }
        // vm.error 以前只赋值、没有任何地方展示（图片读取失败会静默），这里补上提示
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("好", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    private var deleteDialogShown: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: 顶部

    private var header: some View {
        IosLargeTitle(
            title: title,
            actions: AnyView(
                HStack(spacing: 12) {
                    // 语文页给「生成作文」入口（之前只有桌面长按图标能进）
                    if vm.subject == "chinese" {
                        IosTextButton(text: "生成作文") { router.push(.essay) }
                    }
                    IosTextButton(text: "清空") { showClearConfirm = true }
                }
            )
        )
    }

    // MARK: 主体

    @ViewBuilder
    private var content: some View {
        if vm.messages.isEmpty && vm.liveAssistantText == nil {
            EmptyChatState(title: title, accent: accent) { example in
                input = example
            }
        } else {
            ZStack(alignment: .top) {
                messageList
                if vm.ocrWorking {
                    Text("识别中，请稍候")
                        .font(HyperType.labelLarge)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(palette.card.opacity(0.94)))
                        .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
                        .padding(.top, 8)
                }
            }
        }
    }

    /// 单条消息的渲染。抽成独立方法是因为参数太多，写在 ForEach 里
    /// 会让 Swift 的类型推导超时（compiler unable to type-check in reasonable time）。
    @ViewBuilder
    private func bubbleRow(_ msg: Message) -> some View {
        let isSpeaking = speech.speakingSource == msg.textContent
        let isRegenerating = msg.id == vm.regenerateTargetId
        BubbleRow(
            message: msg,
            subject: vm.subject,
            isFavorited: vm.favoritedIds.contains(msg.id),
            spokenChunk: isSpeaking ? speech.spokenChunk : nil,
            isSpeakingThis: isSpeaking && speech.isSpeaking,
            liveOverride: isRegenerating ? vm.regenerateDraft : nil,
            streamingHint: isRegenerating ? vm.statusHint : nil,
            speakProgress: isSpeaking ? speech.progress : nil,
            onToggleFavorite: { vm.toggleFavorite(messageId: msg.id) },
            onCopy: { UIPasteboard.general.string = msg.textContent },
            onSpeak: { vm.speak(msg.textContent) },
            onImageClick: msg.imageUri.map { uri in { previewUri = uri } },
            onDelete: { pendingDelete = msg },
            onRegenerate: msg.role == "assistant" ? { vm.regenerate(messageId: msg.id) } : nil
        )
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.messages.enumerated()), id: \.element.id) { index, msg in
                        let showTime = AppStore.shouldShowTimestamp(vm.messages, index: index)
                        if showTime {
                            TimestampRow(text: Timestamp.format(msg.createdAt))
                        }
                        bubbleRow(msg)
                            .id(msg.id)
                    }

                    if let live = vm.liveAssistantText {
                        ChatBubbleView(
                            role: "assistant",
                            text: live,
                            subject: vm.subject,
                            isStreaming: true,
                            statusHint: vm.statusHint
                        )
                        .id("streaming")
                    }

                    // 失败卡只在真的有失败时出现；以前 tail 是 user 就弹，
                    // 删掉失败提问后卡片会一直赖着，点重试还会把更早的好答案重发一遍
                    if vm.sendFailure != nil, !vm.streaming {
                        SendFailureRow(
                            reason: vm.sendFailure ?? "上一次没能回答成功",
                            onRetry: { vm.retryLast() }
                        )
                        .id("failure")
                    }

                    if !vm.streaming, let last = vm.messages.last,
                       last.role == "assistant", !last.textContent.isEmpty {
                        FollowUpRow { question in vm.sendText(question) }
                            .id("followup")
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.liveAssistantText?.count ?? 0) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.regenerateDraft?.count ?? 0) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.messages.count) { _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: AnyHashable
        if vm.liveAssistantText != nil { target = "streaming" }
        else if let regeneratingId = vm.regenerateTargetId { target = AnyHashable(regeneratingId) }
        else if vm.sendFailure != nil { target = "failure" }
        else if let last = vm.messages.last { target = AnyHashable(last.id) }
        else { target = AnyHashable("") }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    // MARK: 弹层

    @ViewBuilder
    private var cameraSheet: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            CameraPicker(
                onCapture: { url in
                    // 必须显式收起 sheet：只靠 UIKit dismiss 时 SwiftUI 绑定可能仍是 true，
                    // 真机上表现为「拍完再点拍照没反应」。
                    showCamera = false
                    if let saved = FileStorage.persist(imageAt: url) {
                        vm.processImage(at: saved)
                    } else {
                        vm.error = "图片保存失败，请重试"
                    }
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        } else {
            UnavailableFeatureRow(text: "这台设备没有可用的相机（模拟器不能拍照，请用真机）。")
        }
    }

    private var librarySheet: some View {
        PhotoLibraryPicker(
            onPick: { url in
                showLibrary = false
                if let saved = FileStorage.persist(imageAt: url) {
                    vm.processImage(at: saved)
                } else {
                    vm.error = "图片保存失败，请重试"
                }
            },
            onCancel: { showLibrary = false },
            onError: { message in
                showLibrary = false
                vm.error = message
            },
            // 聊天页一次只处理一张：processImage 有 ocrWorking 串行保护，选多了会被静默丢弃
            limit: 1
        )
        .ignoresSafeArea()
    }
}

// MARK: - 子视图

private struct TimestampRow: View {
    let text: String
    @Environment(\.hyperPalette) private var palette
    var body: some View {
        Text(text)
            .font(HyperType.footnote)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

/// 一条已定稿消息 + 操作行。
private struct BubbleRow: View {
    let message: Message
    let subject: String
    let isFavorited: Bool
    let spokenChunk: String?
    var isSpeakingThis: Bool = false
    /// 重新生成中的实时草稿；非 nil 时界面显示它而不是库里的旧文本
    var liveOverride: String? = nil
    var streamingHint: String? = nil
    var speakProgress: (Int, Int)? = nil
    let onToggleFavorite: () -> Void
    let onCopy: () -> Void
    let onSpeak: () -> Void
    let onImageClick: (() -> Void)?
    let onDelete: () -> Void
    var onRegenerate: (() -> Void)? = nil

    var body: some View {
        ChatBubbleView(
            role: message.role,
            text: liveOverride ?? message.textContent,
            subject: subject,
            imageUri: message.imageUri,
            isStreaming: liveOverride != nil,
            statusHint: streamingHint,
            isFavorited: isFavorited,
            onToggleFavorite: message.role == "assistant" ? onToggleFavorite : nil,
            onCopy: onCopy,
            onSpeak: onSpeak,
            spokenChunk: spokenChunk,
            isSpeakingThis: isSpeakingThis,
            progress: speakProgress,
            onImageClick: onImageClick,
            onDelete: onDelete,
            onRegenerate: message.role == "assistant" ? onRegenerate : nil
        )
    }
}

/// 发送失败卡片：贴在 AI 气泡该在的位置。
/// 失败不能只靠一闪而过的提示——学生抬头时只剩一个「问了没人回」的空对话。
private struct SendFailureRow: View {
    let reason: String
    let onRetry: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 18))
                .foregroundStyle(palette.error)
            VStack(alignment: .leading, spacing: 4) {
                Text("这条没能回答成功")
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Text(reason)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                Button(action: onRetry) {
                    Text("重试").font(HyperType.labelLarge).foregroundStyle(palette.accent)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 40)
        }
        .padding(14)
        .background(
            palette.error.opacity(palette.isDark ? 0.12 : 0.06),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

/// 追问快捷入口：上一轮回答定稿后出现，横向可滚。
private struct FollowUpRow: View {
    let onAsk: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatExamples.followUps, id: \.self) { question in
                    Button { onAsk(question) } label: {
                        Text(question)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(Color(.secondarySystemBackground))
                            )
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}

/// 空态：与安卓 ChatScreen 的空态同一套文案与层级。
struct EmptyChatState: View {
    let title: String
    let accent: Color
    let onPick: (String) -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 60)
                ZStack {
                    Circle().fill(accent.opacity(0.12)).frame(width: 92, height: 92)
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(accent)
                }
                Text("向「\(title)」提问")
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .padding(.top, 18)
                Text("直接打字，或拍一张题目照片")
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 6)
                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text("可以这样问")
                        .font(HyperType.labelLarge)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.leading, 6)
                    ForEach(ChatExamples.forSubject(subjectKey), id: \.self) { example in
                        Button { onPick(example) } label: {
                            Text(example)
                                .font(HyperType.body)
                                .foregroundStyle(palette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(palette.card)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(palette.divider, lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                Spacer().frame(height: 40)
            }
        }
    }

    private var subjectKey: String {
        if title == "语文" { return "chinese" }
        if title == "英语" { return "english" }
        return "math"
    }
}

struct UnavailableFeatureRow: View {
    let text: String
    var body: some View {
        VStack {
            Text(text).font(HyperType.bodyMedium).padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - 小工具

/// Optional<String> 不能直接 .sheet(item:)，包一层 Identifiable。
extension Optional where Wrapped == String {
    var asIdentifiable: IdentifiableString? {
        guard let self else { return nil }
        return IdentifiableString(value: self)
    }
}

struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
}
