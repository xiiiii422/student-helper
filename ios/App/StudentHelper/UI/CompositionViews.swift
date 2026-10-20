import SwiftUI
import UIKit
import SHCore

/// 作文列表 + 新建 + 详情，对齐安卓 `ui/composition/*`。
/// 详情页是批改结果的唯一出口，所以解析失败时必须能退回「显示原文」而不是白屏。

// MARK: - 列表

struct CompositionListView: View {
    @StateObject var vm: CompositionListViewModel
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router
    @State private var pendingDelete: Composition?

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "作文",
                actions: AnyView(
                    HStack(spacing: 12) {
                        // 「生成作文」以前只有桌面长按图标才能进，App 里找不到入口
                        IosTextButton(text: "生成作文") { router.push(.essay) }
                        IosTextButton(text: "新建批改") { router.push(.compositionNew) }
                    }
                )
            )
            if vm.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.items) { item in
                            CompositionCardRow(item: item) { router.push(.compositionDetail(item.id)) }
                                .contextMenu {
                                    Button("删除", role: .destructive) { pendingDelete = item }
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(palette.background)
        .overlay(alignment: .bottomTrailing) { addButton }
        .alert("删除这篇作文？", isPresented: deleteBinding) {
            Button("删除", role: .destructive) {
                if let target = pendingDelete { vm.delete(target) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("「\(pendingDelete?.title ?? "")」的批改记录与图片将一并删除，不可恢复。")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Hyper.composition.opacity(0.14)).frame(width: 92, height: 92)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 32))
                    .foregroundStyle(Hyper.composition)
            }
            Text("还没有作文")
                .font(HyperType.title2)
                .foregroundStyle(palette.text)
                .padding(.top, 18)
            Text("把作文发上来，老师会给分数、优点和改进建议")
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 32)
            Button { router.push(.compositionNew) } label: {
                Text("写一篇作文")
                    .font(HyperType.titleMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Hyper.miBlue))
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var addButton: some View {
        Button { router.push(.compositionNew) } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Hyper.miBlue))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 22)
    }
}

private struct CompositionCardRow: View {
    let item: Composition
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                if let first = item.imageUriList.first, let image = LocalImage.load(first) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "未命名作文" : item.title)
                        .font(HyperType.titleMedium)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(summary)
                        .font(HyperType.bodyMedium)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                    Text(Timestamp.format(item.createdAt))
                        .font(HyperType.footnote)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().fill(ScoreColor.forScore(item.score)).frame(width: 44, height: 44)
                    Text("\(item.score)")
                        .font(HyperType.scoreNumber)
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .background(HyperRadius.cardShape.fill(palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        if let feedback = FeedbackParser.parse(item.aiFeedback), !feedback.summary.isEmpty {
            return feedback.summary
        }
        return item.content.isEmpty ? "点击查看批改" : String(item.content.prefix(40))
    }
}

// MARK: - 新建

@MainActor
final class CompositionNewViewModel: ObservableObject {
    @Published var title = ""
    @Published var requirement = ""
    @Published var content = ""
    @Published var imageFiles: [URL] = []
    @Published var submitting = false
    @Published var ocrWorking = false
    @Published var error: String?

    private let store: AppStore
    private let llm: LlmService

    init(store: AppStore, llm: LlmService) {
        self.store = store
        self.llm = llm
    }

    var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageFiles.isEmpty
    }

    func addImage(_ url: URL) {
        guard imageFiles.count < 4 else {
            error = "最多 4 张照片"
            return
        }
        imageFiles.append(url)
        ocrWorking = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.ocrWorking = false }
            guard let raw = UIImage(contentsOfFile: url.path) else {
                self.error = "图片读取失败"
                return
            }
            let compressed = ImageCodec.compress(raw)
            let result = await OcrService.recognize(image: compressed)
            self.appendText(result.text)
        }
    }

    private func appendText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        content = content.isEmpty ? text : content + "\n" + text
    }

    func removeImage(at index: Int) {
        guard imageFiles.indices.contains(index) else { return }
        imageFiles.remove(at: index)
    }

    /// 提交批改，返回新记录 id；失败返回 nil 并留下可读的 error。
    func submit() async -> Int? {
        guard !submitting, canSubmit else { return nil }
        submitting = true
        error = nil
        defer { submitting = false }

        let images = imageFiles.compactMap { url -> String? in
            guard let raw = UIImage(contentsOfFile: url.path) else { return nil }
            return ImageCodec.base64(from: ImageCodec.compress(raw))
        }
        let urisJson = "[" + imageFiles.map { "\"\($0.path)\"" }.joined(separator: ",") + "]"
        do {
            let raw = try await llm.complete(
                systemPrompt: Prompts.compositionPrompt,
                userText: PromptAssembler.compositionUserMessage(
                    title: title.isEmpty ? "未命名作文" : title,
                    grade: "六年级",
                    content: content.isEmpty ? nil : content,
                    requirement: requirement.isEmpty ? nil : requirement,
                    imageCount: images.count
                ),
                imagesBase64: images,
                temperature: PromptAssembler.temperature(for: .composition)
            )
            let feedback = FeedbackParser.parse(raw)
            let saved = store.insert(
                Composition(
                    title: title.isEmpty ? "未命名作文" : title,
                    content: content,
                    imageUris: urisJson,
                    aiFeedback: raw,
                    score: feedback?.totalScore ?? 0
                )
            )
            return saved.id
        } catch {
            self.error = LlmPolicy.friendlyError(
                (error as? LlmError)?.message ?? error.localizedDescription
            )
            return nil
        }
    }
}

struct CompositionNewView: View {
    @StateObject var vm: CompositionNewViewModel
    @Environment(\.hyperPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: Router
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                field("作文标题（可选）", text: $vm.title, lines: 1)
                field("作文题目要求（可选）", text: $vm.requirement, lines: 2)

                Text("作文照片（最多4张）")
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    tonalButton("拍照", icon: "camera") { showCamera = true }
                    tonalButton("相册", icon: "photo.on.rectangle") { showLibrary = true }
                    Spacer()
                }
                if vm.ocrWorking {
                    Text("识别中…（可先编辑已识别内容）")
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.composition)
                }
                if !vm.imageFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(vm.imageFiles.enumerated()), id: \.offset) { index, url in
                                thumb(url, index: index)
                            }
                        }
                    }
                }

                field("作文正文（识别后可修改，或直接输入）", text: $vm.content, lines: 8, tall: true)

                Button {
                    Task {
                        if let id = await vm.submit() {
                            router.pop()
                            router.push(.compositionDetail(id))
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if vm.submitting {
                            ProgressView().tint(.white)
                        }
                        Text(vm.submitting ? "批改中…" : "开始批改")
                            .font(HyperType.titleMedium)
                    }
                    // 禁用态用灰底深灰字（同作文页），浅蓝底白字在浅色背景下看不清
                    .foregroundStyle(vm.canSubmit && !vm.submitting ? Color.white : palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(vm.canSubmit && !vm.submitting ? Hyper.miBlue : palette.divider))
                }
                .buttonStyle(.plain)
                // 正文和照片都空时不给点：以前看着能点，点下去只弹一句「请先输入」
                .disabled(!vm.canSubmit || vm.submitting)
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle("新建作文")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            // 无相机设备（或被「屏幕使用时间」限制）时强设 .camera 会抛异常，这里兜一层
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                CameraPicker(
                    onCapture: { url in
                        showCamera = false
                        if let saved = FileStorage.persist(imageAt: url) {
                            vm.addImage(saved)
                        } else {
                            vm.error = "图片保存失败，请重试"
                        }
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            } else {
                UnavailableFeatureRow(text: "这台设备没有可用的相机。")
            }
        }
        .sheet(isPresented: $showLibrary) {
            PhotoLibraryPicker(
                onPick: { url in showLibrary = false; if let saved = FileStorage.persist(imageAt: url) { vm.addImage(saved) } },
                onCancel: { showLibrary = false },
                onError: { message in
                    showLibrary = false
                    vm.error = message
                }
            )
            .ignoresSafeArea()
        }
        .alert("批改失败", isPresented: errorBinding) {
            Button("好", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } })
    }

    private func field(_ label: String, text: Binding<String>, lines: Int, tall: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(HyperType.footnote)
                .foregroundStyle(palette.textSecondary)
            TextField("", text: text, axis: .vertical)
                .font(HyperType.body)
                .lineLimit(tall ? 8...16 : lines...(lines + 2))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.divider, lineWidth: 0.6)
                )
        }
    }

    private func tonalButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15))
                Text(label).font(HyperType.labelLarge)
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(palette.fill))
        }
        .buttonStyle(.plain)
    }

    private func thumb(_ url: URL, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = LocalImage.load(url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            Button { vm.removeImage(at: index) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, palette.error)
            }
            .padding(4)
        }
    }
}

// MARK: - 详情

struct CompositionDetailView: View {
    let id: Int
    @StateObject var vm: CompositionDetailViewModel
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let composition = vm.composition {
                    header(composition)
                    if let feedback = vm.feedback {
                        FeedbackDetailView(feedback: feedback)
                        actions
                    } else {
                        // 解析失败也要让学生看到老师回了什么，不能白屏
                        rawFallback(composition.aiFeedback)
                        actions
                    }
                } else {
                    Text("这篇作文已经不在了")
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle(vm.composition?.title ?? "批改详情")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("好", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    /// 批改完还能做两件事：让老师重批一次，或带着这篇作文去语文页追问。
    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                vm.reGrade()
            } label: {
                HStack(spacing: 6) {
                    if vm.submitting {
                        ProgressView().tint(palette.accent)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(vm.submitting ? "重批中…" : "重新批改")
                        .font(HyperType.bodyMedium)
                }
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().stroke(palette.accent, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(vm.submitting)

            Button {
                // 带着作文去语文页追问，学生能接着问「这段怎么改」
                router.popToRoot()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                    Text("去问老师")
                        .font(HyperType.bodyMedium)
                }
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(palette.fill))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func header(_ composition: Composition) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(ScoreColor.forScore(composition.score))
                    .frame(width: 66, height: 66)
                VStack(spacing: 0) {
                    Text("\(composition.score)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("分")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(composition.title.isEmpty ? "未命名作文" : composition.title)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                Text(Timestamp.format(composition.createdAt))
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
        }
    }

    private func rawFallback(_ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批改结果格式异常，下面是原始回复")
                .font(HyperType.labelLarge)
                .foregroundStyle(Hyper.composition)
            Text(raw)
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.text)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(HyperRadius.cardShape.fill(palette.card))
    }
}

@MainActor
final class CompositionDetailViewModel: ObservableObject {
    @Published var composition: Composition?
    @Published var submitting = false
    @Published var error: String?
    private let store: AppStore
    private let llm: LlmService

    init(id: Int, store: AppStore, llm: LlmService) {
        self.store = store
        self.llm = llm
        self.composition = store.composition(id: id)
    }

    var feedback: CompositionFeedback? {
        composition.flatMap { FeedbackParser.parse($0.aiFeedback) }
    }

    /// 重新批改：同一篇作文再让老师评一次（换个角度/模型可能给不同建议）
    func reGrade() {
        guard !submitting, let current = composition else { return }
        submitting = true
        error = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.submitting = false }
            do {
                let raw = try await self.llm.complete(
                    systemPrompt: Prompts.compositionPrompt,
                    userText: PromptAssembler.compositionUserMessage(
                        title: current.title,
                        grade: "六年级",
                        content: current.content,
                        requirement: nil,
                        imageCount: current.imageUriList.count
                    ),
                    imagesBase64: [],
                    temperature: PromptAssembler.temperature(for: .composition)
                )
                var updated = current
                updated.aiFeedback = raw
                if let parsed = FeedbackParser.parse(raw) {
                    updated.score = parsed.totalScore
                }
                self.store.update(updated)
                self.composition = updated
                Haptics.success()
            } catch {
                self.error = LlmPolicy.friendlyError(
                    (error as? LlmError)?.message ?? error.localizedDescription
                )
                Haptics.warning()
            }
        }
    }
}

@MainActor
final class CompositionListViewModel: ObservableObject {
    @Published var items: [Composition] = []
    private let store: AppStore

    init(store: AppStore) {
        self.store = store
        reload()
        store.onChange = { [weak self] in self?.reload() }
    }

    func reload() { items = store.compositions() }

    func delete(_ item: Composition) {
        // store 返回被删作文的图片路径，统一走 FileStorage 的安全删除（只删沙盒 images 目录）
        for uri in store.deleteComposition(item) { FileStorage.delete(path: uri) }
        reload()
    }
}
