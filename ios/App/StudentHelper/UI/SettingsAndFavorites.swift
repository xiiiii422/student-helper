import SwiftUI
import UIKit
import SHCore

/// 模型服务设置，对齐安卓 `ui/me/SettingsScreen.kt`：
/// 供应商预设 + 接口地址 / Key / 两个模型名 + 保存 / 连接测试 + 底部说明。
struct SettingsView: View {
    @StateObject var vm: SettingsViewModel
    @Environment(\.hyperPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("供应商预设").font(HyperType.title2).foregroundStyle(palette.text)

                HStack(spacing: 10) {
                    ForEach(Presets.all, id: \.id) { preset in
                        ThemeChip(
                            label: preset.label,
                            selected: vm.form.providerId == preset.id
                        ) { vm.apply(preset) }
                    }
                    Spacer()
                }

                Text("切换预设后自动填入对应接口地址与模型名；Key 使用本机已存的值，也可在下方修改。")
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)

                VStack(spacing: 10) {
                    field("接口地址（Base URL）", text: $vm.form.baseUrl, keyboard: .URL)
                    secureField("API Key", text: $vm.form.apiKey, hasStored: vm.hasStoredKey)
                    field("文本模型（讲题/批改）", text: $vm.form.chatModel, placeholder: "glm-4.7-flash")
                    field("视觉模型（拍照识题）", text: $vm.form.vlModel, placeholder: "glm-4v-flash")
                }

                HStack(spacing: 10) {
                    Button { vm.save() } label: {
                        Text("保存")
                            .font(HyperType.titleMedium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Hyper.miBlue))
                    }
                    Button { vm.ping() } label: {
                        Text(vm.pinging ? "测试中…" : "连接测试")
                            .font(HyperType.titleMedium)
                            .foregroundStyle(Hyper.miBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().stroke(Hyper.miBlue, lineWidth: 1))
                    }
                    .disabled(vm.pinging)
                }
                .buttonStyle(.plain)

                if !vm.pingResults.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(vm.pingResults, id: \.provider) { result in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(result.ok ? Hyper.statusOk : palette.error)
                                    .frame(width: 8, height: 8)
                                Text("\(result.provider)：\(result.detail)")
                                    .font(HyperType.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }

                Text("说明：App 直连大模型服务，无需电脑。Key 存在本机钥匙串（不随 iCloud 备份迁移），请勿公开分发本应用。")
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textTertiary)

                speechSection
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle("模型服务设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: messageBinding) {
            Button("好", role: .cancel) { vm.message = nil }
        } message: {
            Text(vm.message ?? "")
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { vm.message != nil }, set: { if !$0 { vm.message = nil } })
    }

    /// iOS 特色：朗读语速与音色在这里调，安卓没有这一段。
    private var speechSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("朗读").font(HyperType.titleMedium).foregroundStyle(palette.text)
            Toggle("答完自动朗读", isOn: $vm.autoSpeak)
                .tint(Hyper.miBlue)
                .font(HyperType.bodyMedium)
            VStack(alignment: .leading, spacing: 2) {
                Text("语速 \(String(format: "%.2f", Double(vm.rate)))")
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textSecondary)
                Slider(value: $vm.rate, in: 0.3...0.6)
                    .tint(Hyper.composition)
            }
            Picker("音色", selection: $vm.voiceIdentifier) {
                Text("自动（选最自然的）").tag(String?.none)
                ForEach(SettingsViewModel.voiceOptions, id: \.identifier) { voice in
                    Text(voice.displayName + "（\(voice.language)）")
                        .tag(String?.some(voice.identifier))
                }
            }
            .font(HyperType.bodyMedium)
        }
        .padding(14)
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    private func field(
        _ label: String, text: Binding<String>,
        placeholder: String = "", keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(HyperType.footnote).foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: text)
                .font(HyperType.bodyMedium)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill))
        }
    }

    private func secureField(_ label: String, text: Binding<String>, hasStored: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(HyperType.footnote).foregroundStyle(palette.textSecondary)
            SecureField(hasStored ? "已保存（留空表示不修改）" : "未设置", text: text)
                .font(HyperType.bodyMedium)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill))
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    struct Form {
        var providerId: String
        var baseUrl: String
        var apiKey: String
        var chatModel: String
        var vlModel: String
    }

    @Published var form: Form
    @Published var pingResults: [PingResult] = []
    @Published var pinging = false
    @Published var message: String?

    // 朗读设置直接读写 SpeechService 的持久化属性。
    // didSet 立刻写回：否则这些只是 ViewModel 里的副本，改完设置页看着变了、
    // 实际朗读仍用旧参数（SpeechService 的 didSet 才会落 UserDefaults）。
    @Published var autoSpeak: Bool {
        didSet { if speech.autoSpeak != autoSpeak { speech.autoSpeak = autoSpeak } }
    }
    @Published var rate: Float {
        didSet { if speech.rate != rate { speech.rate = rate } }
    }
    @Published var voiceIdentifier: String? {
        didSet { if speech.preferredVoice != voiceIdentifier { speech.preferredVoice = voiceIdentifier } }
    }

    /// 当前供应商在本机钥匙串里是否已有 Key（决定输入框提示语）。
    var hasStoredKey: Bool { !settings.apiKey(for: form.providerId).isEmpty }

    private let settings: SettingsStore
    private let llm: LlmService
    private let speech: SpeechService

    init(settings: SettingsStore, llm: LlmService, speech: SpeechService) {
        self.settings = settings
        self.llm = llm
        self.speech = speech
        // 表单直接读 SettingsStore 的同步属性；Key 不回显，留空代表「不改」
        let preset = Presets.preset(of: settings.providerId)
        _form = Published(initialValue: Form(
            providerId: settings.providerId,
            baseUrl: settings.customBaseUrl ?? preset.baseUrl,
            apiKey: "",
            chatModel: settings.customChatModel ?? preset.chatModel,
            vlModel: settings.customVlModel ?? preset.vlModel
        ))
        _autoSpeak = Published(initialValue: speech.autoSpeak)
        _rate = Published(initialValue: speech.rate)
        _voiceIdentifier = Published(initialValue: speech.preferredVoice)
    }

    /// 音色选项要跨 actor 取，标成 nonisolated 避开主线程隔离报错
    nonisolated static var voiceOptions: [AVSpeechVoiceInfo] {
        SpeechService.availableVoices().map {
            AVSpeechVoiceInfo(identifier: $0.identifier, language: $0.language, displayName: $0.name)
        }
    }

    func apply(_ preset: ProviderPreset) {
        form.providerId = preset.id
        form.baseUrl = preset.baseUrl
        form.chatModel = preset.chatModel
        form.vlModel = preset.vlModel
    }

    func save() {
        if form.apiKey.isEmpty {
            // Key 留空表示不改，避免一次保存把已存的 Key 抹掉
            message = "未修改 Key"
        } else {
            settings.setApiKey(form.apiKey, for: form.providerId)
        }
        if form.providerId == "custom" {
            settings.setCustom(
                baseUrl: form.baseUrl, chatModel: form.chatModel,
                vlModel: form.vlModel, apiKey: form.apiKey.isEmpty ? nil : form.apiKey
            )
        } else if let preset = Presets.all.first(where: { $0.id == form.providerId }) {
            settings.applyPreset(preset)
        }
        Haptics.success()
        message = "已保存"
    }

    func ping() {
        guard !pinging else { return }
        pinging = true
        Task { [weak self] in
            guard let self else { return }
            let results = await self.llm.pingAll()
            self.pingResults = results
            self.pinging = false
        }
    }
}

struct AVSpeechVoiceInfo {
    let identifier: String
    let language: String
    let displayName: String
}

// MARK: - 错题本

struct FavoritesView: View {
    @StateObject var vm: FavoritesViewModel
    @Environment(\.hyperPalette) private var palette
    @State private var filter: String?
    @State private var expanded: Set<Int> = []

    var body: some View {
        Group {
            if vm.selfTest {
                selfTestScreen
            } else {
                listScreen
            }
        }
        .background(palette.background)
        .navigationTitle("错题本")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding<IdentifiableURL?>(
            get: { vm.exportUrl.asIdentifiableURL },
            set: { if $0 == nil { vm.exportUrl = nil } }
        )) { item in
            ShareSheet(items: [item.value])
        }
        .alert("提示", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("好", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }

    // MARK: 自测模式

    /// 整屏自测：只出题目，答案先挡住，学生心里答完再对照自评。
    private var selfTestScreen: some View {
        VStack(spacing: 0) {
            HStack {
                Text("第 \(vm.sessionProgress.done + 1)/\(vm.sessionProgress.total) 题")
                    .font(HyperType.labelLarge)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button { vm.exitSelfTest() } label: {
                    Text("退出自测").font(HyperType.bodyMedium).foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if let row = vm.currentTest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 6) {
                            Circle().fill(SubjectColor.forSubject(row.favorite.subject))
                                .frame(width: 7, height: 7)
                            Text(SubjectLabel.of(row.favorite.subject))
                                .font(HyperType.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Text(row.question)
                            .font(HyperType.title2)
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)

                        answerBlock(row)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                selfTestActionBar
            } else {
                // 本轮过完
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Hyper.english)
                    Text("这一轮练完了")
                        .font(HyperType.title2)
                        .foregroundStyle(palette.text)
                    let remaining = vm.remainingAfterRound
                    Text(remaining == 0
                        ? "所有错题都已掌握，休息一下。"
                        : "还有 \(remaining) 题没掌握，可以再练一轮。")
                        .font(HyperType.bodyMedium)
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 12) {
                        if remaining > 0 {
                            Button { vm.restartRound() } label: {
                                Text("再来一轮")
                                    .font(HyperType.titleMedium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24).padding(.vertical, 11)
                                    .background(Capsule().fill(Hyper.miBlue))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { vm.exitSelfTest() } label: {
                            Text("返回列表")
                                .font(HyperType.titleMedium)
                                .foregroundStyle(palette.text)
                                .padding(.horizontal, 24).padding(.vertical, 11)
                                .background(Capsule().stroke(palette.divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func answerBlock(_ row: FavoriteRow) -> some View {
        if vm.answerRevealed {
            VStack(alignment: .leading, spacing: 6) {
                Text("参考答案").font(HyperType.labelLarge).foregroundStyle(palette.textSecondary)
                MathText(content: row.answer, color: palette.text)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HyperRadius.smallShape.fill(palette.fill))
        } else {
            Button { vm.answerRevealed = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text("我答完了，看参考答案")
                }
                .font(HyperType.labelLarge)
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(HyperRadius.smallShape.fill(palette.card))
            }
            .buttonStyle(.plain)
        }
    }

    private var selfTestActionBar: some View {
        VStack(spacing: 8) {
            if vm.answerRevealed {
                HStack(spacing: 12) {
                    Button { vm.mark(mastered: false) } label: {
                        Label("再看看", systemImage: "arrow.counterclockwise")
                            .font(HyperType.titleMedium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().fill(Hyper.miOrange))
                    }
                    .buttonStyle(.plain)
                    Button { vm.mark(mastered: true) } label: {
                        Label("已掌握", systemImage: "checkmark")
                            .font(HyperType.titleMedium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Capsule().fill(Hyper.english))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button { vm.skipCurrent() } label: {
                    Text("这题跳过").font(HyperType.bodyMedium).foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: 列表模式

    private var listScreen: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !vm.rows.isEmpty {
                    masteryHeader
                }
                HStack(spacing: 8) {
                    chip("全部", selected: filter == nil) { filter = nil }
                    ForEach(["chinese", "math", "english"], id: \.self) { subject in
                        chip(SubjectLabel.of(subject), selected: filter == subject) { filter = subject }
                    }
                    Spacer()
                    if !vm.rows(filter: filter).isEmpty {
                        Button {
                            vm.exportText(filter: filter)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15))
                                .foregroundStyle(Hyper.miBlue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("导出错题")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                let rows = vm.rows(filter: filter)
                if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(rows, id: \.favorite.id) { row in
                        favoriteCard(row)
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    /// 顶部掌握概览 + 进入自测入口：让「自测」这个功能一眼就能看到、点到。
    private var masteryHeader: some View {
        let c = vm.counts
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("掌握情况").font(HyperType.labelLarge).foregroundStyle(palette.textSecondary)
                HStack(spacing: 8) {
                    Text("已掌握 \(c.mastered)")
                        .font(HyperType.bodyMedium).foregroundStyle(Hyper.english)
                    Text("待复习 \(c.again)")
                        .font(HyperType.bodyMedium).foregroundStyle(Hyper.miOrange)
                    Text("未测 \(c.untested)")
                        .font(HyperType.bodyMedium).foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            Button { vm.beginSelfTest() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.circle.fill")
                    Text("自测").font(HyperType.labelLarge)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(Hyper.miBlue))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    /// 空态说清「怎么进来」，否则学生只会站在这里问错题本有什么用。
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "star")
                .font(.system(size: 34))
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, 4)
            Text("还没有收藏的错题")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text("在讲题回答下面点一下星星，就能收进这里")
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(HyperType.labelLarge)
                .foregroundStyle(selected ? palette.accent : palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? palette.accent.opacity(0.12) : palette.card))
                .overlay(Capsule().stroke(selected ? Color.clear : palette.divider, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func favoriteCard(_ row: FavoriteRow) -> some View {
        let accent = SubjectColor.forSubject(row.favorite.subject)
        let open = expanded.contains(row.favorite.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(accent)
                    .frame(width: 3, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.question)
                        .font(HyperType.titleMedium)
                        .foregroundStyle(palette.text)
                        .lineLimit(open ? nil : 2)
                    Text(SubjectLabel.of(row.favorite.subject) + " · " + Timestamp.format(row.favorite.createdAt))
                        .font(HyperType.footnote)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                Button { vm.remove(row.favorite) } label: {
                    Image(systemName: "star.slash")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消收藏")
            }
            if open {
                MathText(content: row.answer, color: palette.text)
                    .padding(.leading, 13)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if open { expanded.remove(row.favorite.id) } else { expanded.insert(row.favorite.id) }
        }
    }
}

struct FavoriteRow {
    let favorite: Favorite
    let question: String
    let answer: String
}

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published private(set) var rows: [FavoriteRow] = []
    /// 自测模式开关
    @Published private(set) var selfTest = false
    /// 当前这题的答案是否已揭开
    @Published var answerRevealed = false
    private let store: AppStore

    /// 本轮自测锁定的题目 id（按「先未测、后待复习」排）。
    /// 必须进来时锁一份：答一题就会改 reviewState，而队列是按 reviewState 算的，
    /// 直接拿下标往前推进会跳题；全标「再看看」时甚至会卡在同一题死循环。
    private var sessionQueue: [Int] = []
    /// 本轮已经过手的 id（不管判会还是判不会，本轮都不再重复出同一题）
    private var passed: Set<Int> = []

    init(store: AppStore) {
        self.store = store
        reload()
    }

    func reload() {
        rows = store.favoritedRows(subject: nil).map { pair in
            // 收藏的是答案那条，题目在它前一条
            let all = store.messages(subject: pair.message.subject)
            let question = all.last(where: { $0.role == "user" && $0.createdAt <= pair.message.createdAt })?.textContent
                ?? pair.message.textContent
            return FavoriteRow(favorite: pair.favorite, question: question, answer: pair.message.textContent)
        }
    }

    func rows(filter: String?) -> [FavoriteRow] {
        guard let filter else { return rows }
        return rows.filter { $0.favorite.subject == filter }
    }

    func remove(_ favorite: Favorite) {
        store.toggleFavorite(messageId: favorite.messageId)
        passed.remove(favorite.id)
        sessionQueue.removeAll { $0 == favorite.id }
        reload()
    }

    // MARK: 自测模式

    var counts: (mastered: Int, again: Int, untested: Int) {
        store.reviewCounts(subject: nil)
    }

    /// 待测队列：未测的在前（先做新题），再轮到判过「再看看」的；已掌握的毕业出队。
    private var pendingQueue: [FavoriteRow] {
        let open = rows.filter { $0.favorite.reviewState != "mastered" }
        return open.filter { $0.favorite.reviewState == nil }
            + open.filter { $0.favorite.reviewState == "again" }
    }

    var currentTest: FavoriteRow? {
        guard selfTest else { return nil }
        for id in sessionQueue where !passed.contains(id) {
            if let row = rows.first(where: { $0.favorite.id == id }) { return row }
        }
        return nil
    }

    /// 本轮进度：总共几题、已经过手几题
    var sessionProgress: (done: Int, total: Int) {
        (sessionQueue.filter { passed.contains($0) }.count, sessionQueue.count)
    }

    /// 队列排空后还剩多少没掌握的（判过「再看看」的会被再来一轮捞回来）
    var remainingAfterRound: Int {
        pendingQueue.count
    }

    func beginSelfTest() {
        sessionQueue = pendingQueue.map(\.favorite.id)
        passed = []
        answerRevealed = false
        selfTest = true
    }

    func exitSelfTest() {
        selfTest = false
        answerRevealed = false
    }

    /// 再来一轮：只练本轮判过「再看看」的（它们 reviewState 仍是 again，仍在待测队列里）
    func restartRound() {
        sessionQueue = pendingQueue.map(\.favorite.id)
        passed = []
        answerRevealed = false
    }

    func mark(mastered: Bool) {
        guard let row = currentTest else { return }
        store.setReviewed(messageId: row.favorite.messageId, mastered: mastered)
        passed.insert(row.favorite.id)
        answerRevealed = false
        reload()
        Haptics.lightTap()
    }

    /// 直接放弃这一题（不改状态，下一轮还会遇到）
    func skipCurrent() {
        guard let row = currentTest else { return }
        passed.insert(row.favorite.id)
        answerRevealed = false
    }

    // MARK: 导出

    @Published var exportUrl: URL?
    @Published var error: String?

    /// 把当前筛选下的错题导出成 txt，走系统分享面板（可存「文件」、发微信、打印）
    func exportText(filter: String?) {
        let rows = rows(filter: filter)
        guard !rows.isEmpty else {
            error = "当前没有可导出的错题"
            return
        }
        let items = rows.map {
            FavoritesExport.Item(
                subject: $0.favorite.subject,
                question: $0.question,
                answer: $0.answer,
                createdAt: $0.favorite.createdAt
            )
        }
        let text = FavoritesExport.render(items: items)
        let name = "错题本-\(Timestamp.format(Int(Date().timeIntervalSince1970 * 1000)).replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "")).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportUrl = url
            Haptics.success()
        } catch {
            self.error = "导出失败：\(error.localizedDescription)"
        }
    }
}

enum SubjectLabel {
    static func of(_ apiValue: String) -> String {
        switch apiValue {
        case "chinese": return "语文"
        case "english": return "英语"
        case "composition": return "作文"
        case "me": return "我的"
        default: return "数学"
        }
    }
}
