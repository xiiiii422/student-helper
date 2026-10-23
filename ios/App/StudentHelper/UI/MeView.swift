import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SHCore

/// 「我的」页状态：连接测试的并发结果与进行中标志。
@MainActor
final class MeViewModel: ObservableObject {
    @Published var themeMode: ThemeMode
    @Published var pinging = false
    /// 上一次连接测试的结果，常驻在「连接测试」行右侧；提示条几秒就没，看不出当前状态。
    @Published var pingResults: [PingResult] = []
    @Published var message: String?
    @Published var exportUrl: URL?
    @Published var importDone = false
    /// 选好备份文件后先挂起，等用户确认「会覆盖现有数据」再真正导入
    @Published var pendingImportUrl: URL?
    /// 备份打包/解包进行中（后台跑，按钮显示进度并防重复点）
    @Published var backupWorking = false

    private let llm: LlmService
    private let store: AppStore
    private let settings: SettingsStore

    /// 设置页用到的底层设置（提醒字段直接代理到它）
    var settingsStore: SettingsStore { settings }

    var reminderOn: Bool {
        get { settings.reminderOn }
        set { settings.reminderOn = newValue }
    }
    var reminderHour: Int {
        get { settings.reminderHour }
        set { settings.reminderHour = newValue }
    }
    var reminderMinute: Int {
        get { settings.reminderMinute }
        set { settings.reminderMinute = newValue }
    }
    var reminderDay: Int {
        get { settings.reminderDay }
        set { settings.reminderDay = newValue }
    }

    init(llm: LlmService, store: AppStore, settings: SettingsStore) {
        self.llm = llm
        self.store = store
        self.settings = settings
        self.themeMode = ThemeMode(rawValue: settings.themeMode) ?? .system
        refreshStorage()
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        settings.themeMode = mode.rawValue
    }

    func ping() {
        guard !pinging else { return }
        pinging = true
        Task { [weak self] in
            guard let self else { return }
            let results = await self.llm.pingAll()
            self.pingResults = results
            self.pinging = false
            // 一家都测不通时不能只说「失败」：本机断网和供应商限流是两件完全不同的事
            self.message = results.isEmpty
                ? "没有可测试的供应商，请先到「模型服务设置」填 Key"
                : results.map { result in
                    result.ok
                        ? "\(result.provider) 已连接（\(result.detail)）"
                        : "\(result.provider) 失败：\(result.detail)"
                }.joined(separator: "；")
        }
    }

    // MARK: 备份

    /// 导出：数据 JSON + 图片目录打成一个 zip，用系统分享面板存到「文件」或发给自己。
    /// 打包在后台跑（图多时主线程会冻好几秒），期间按钮显示进行中防重复点。
    func exportBackup() {
        guard !backupWorking else { return }
        backupWorking = true
        message = "正在打包备份…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await BackupService.export(store: self.store)
                self.exportUrl = url
                self.message = nil
                Haptics.success()
            } catch {
                self.message = "导出失败：\(error.localizedDescription)"
                Haptics.warning()
            }
            self.backupWorking = false
        }
    }

    func importBackup(from url: URL) {
        // 导入是整体替换，先把文件挂起，由界面上确认后再动手——否则误点一下就没了
        pendingImportUrl = url
    }

    func confirmImport() {
        guard let url = pendingImportUrl, !backupWorking else { return }
        pendingImportUrl = nil
        backupWorking = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.backupWorking = false }
            do {
                try await BackupService.importArchive(from: url, store: self.store)
                self.importDone = true
                // 导入后 onChange 会立刻刷新界面，不需要重启
                self.message = "导入完成，已用备份数据替换本机内容"
                self.refreshStorage()
                Haptics.success()
            } catch {
                self.message = "导入失败：\(error.localizedDescription)"
                Haptics.warning()
            }
        }
    }

    /// 「我的」顶部的存储概览。以前是 body 里现算的计算属性——每次重绘都要扫一遍目录
    /// 并逐文件 stat，改成初始化/导入后刷新一次。
    @Published var storageText = ""
    /// 学习统计：问了多少题、哪科最多、连续几天。数字全部来自 SHCore.StudyStats。
    @Published var stats = StudyStats.Summary()

    func refreshStorage() {
        let snap = store.backupSnapshot
        let files = (try? FileManager.default.contentsOfDirectory(
            at: FileStorage.imagesDirectory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let bytes = files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        storageText = "消息 \(snap.messages.count) 条 · 作文 \(snap.compositions.count) 篇 · "
            + "图片 \(files.count) 张（\(String(format: "%.1f", Double(bytes) / 1024 / 1024)) MB）"
        stats = StudyStats.summarize(messages: snap.messages)
    }

    func clearAll() {
        // 先停掉三科正在跑的流，否则清完还会被写回几条
        onStopAllStreams?()
        store.clearAll()
        FileStorage.deleteAllImages()
        refreshStorage()
        message = "已清空全部数据"
    }

    /// 由根容器注入：清空数据前停掉所有学科的流式任务
    var onStopAllStreams: (() -> Void)?
}

/// 「我的」页，逐条对齐安卓 `ui/me/MeScreen.kt`：
/// 顶部应用卡、外观三分段、错题本 / 模型服务设置 / 连接测试 / 导出 / 导入 / 清空 / 关于。
struct MeView: View {
    @StateObject var vm: MeViewModel
    @EnvironmentObject private var router: Router
    @State private var showAbout = false
    @State private var showClearConfirm = false
    @State private var showImporter = false
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                appCard
                statsCard
                themeSection
                reminderSection
                listCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            // 底栏是 safeAreaInset，系统已经让出空间，这里只需一点呼吸位。
            // 之前加 90pt 是误判——反而把内容顶得过高。
            .padding(.bottom, 24)
        }
        .background(palette.background)
        .overlay(alignment: .bottom) { toast }
        .sheet(isPresented: $showImporter) {
            DocumentImporter { url in vm.importBackup(from: url) }
        }
        .sheet(item: Binding<IdentifiableURL?>(
            get: { vm.exportUrl.asIdentifiableURL },
            set: { if $0 == nil { vm.exportUrl = nil } }
        )) { item in
            ShareSheet(items: [item.value])
        }
        .alert("学习小助手", isPresented: $showAbout) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(AppInfo.aboutText)
        }
        .alert("确认清空？", isPresented: $showClearConfirm) {
            Button("确认清空", role: .destructive) { vm.clearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有消息、作文、错题与图片，且不可恢复。建议先导出备份。")
        }
        .alert("导入会覆盖当前数据", isPresented: Binding(
            get: { vm.pendingImportUrl != nil },
            set: { if !$0 { vm.pendingImportUrl = nil } }
        )) {
            Button("覆盖导入", role: .destructive) { vm.confirmImport() }
            Button("取消", role: .cancel) { vm.pendingImportUrl = nil }
        } message: {
            Text("导入会用备份里的数据整体替换本机现有的消息、作文和错题，不可撤销。建议先导出一次当前数据。")
        }
    }

    // MARK: 分组

    private var appCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("学习小助手")
                .font(HyperType.title2)
                .foregroundStyle(palette.text)
            Text("自用版 · 数据仅存本机")
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.textSecondary)
            Text(vm.storageText)
                .font(HyperType.footnote)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    /// 学习统计卡：提问总数、最常问的学科、连续天数，外加最近 7 天的小柱状图。
    /// 家长一眼能看出孩子这周到底用没用、哪科问得多。
    private var statsCard: some View {
        let stats = vm.stats
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("学习统计")
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Spacer()
                if stats.streakDays > 0 {
                    Label("连续 \(stats.streakDays) 天", systemImage: "flame.fill")
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.miOrange)
                }
            }

            HStack(spacing: 0) {
                statCell(value: "\(stats.totalQuestions)", label: "提问")
                statCell(value: "\(stats.activeDays)", label: "打卡天数")
                statCell(
                    value: stats.topSubject.map { SubjectLabel.of($0) } ?? "—",
                    label: "问得最多"
                )
            }

            // 最近 7 天柱状图：高度按最大值归一，全 0 时给一条平线而不是空框
            VStack(alignment: .leading, spacing: 4) {
                let peak = max(stats.last7Days.map(\.questions).max() ?? 0, 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(stats.last7Days.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 3) {
                            // 0 值给 6pt 的浅灰短条，而不是 4pt——太矮会看不见，
                            // 让人以为整块没渲染出来
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.questions > 0 ? Hyper.miBlue : palette.divider)
                                .frame(
                                    width: 18,
                                    height: day.questions > 0
                                        ? max(10, 44 * CGFloat(day.questions) / CGFloat(peak))
                                        : 6
                                )
                            Text(String(day.day.suffix(2)))
                                .font(.system(size: 9))
                                .foregroundStyle(day.questions > 0 ? palette.textSecondary : palette.textTertiary)
                        }
                    }
                    Spacer()
                }
                Text("最近 7 天每天提问数")
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(HyperType.title2)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(HyperType.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("外观")
                .font(HyperType.labelLarge)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 6)
            HStack(spacing: 10) {
                ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                    ThemeChip(
                        label: mode.label,
                        selected: vm.themeMode == mode
                    ) { vm.setTheme(mode) }
                }
                Spacer()
            }
            .padding(14)
            .background(HyperRadius.cardShape.fill(palette.card))
        }
    }

    /// 学习提醒：每天定时弹一条本地通知，落到「我的」页。
    /// 默认关——涉及系统通知授权，不能一上来就弹把家长吓一跳。
    @State private var showTimePicker = false
    @State private var reminderAuthorized = false

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("学习提醒")
                .font(HyperType.labelLarge)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 6)

            VStack(spacing: 0) {
                Toggle(isOn: reminderBinding) {
                    Label {
                        Text("每日学习提醒")
                            .font(HyperType.titleMedium)
                            .foregroundStyle(palette.text)
                    } icon: {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(Hyper.miOrange)
                    }
                }
                .tint(palette.accent)

                if vm.reminderOn {
                    divider
                    Button {
                        showTimePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(Hyper.miBlue)
                            Text("提醒时间")
                                .font(HyperType.titleMedium)
                                .foregroundStyle(palette.text)
                            Spacer()
                            Text(String(format: "%02d:%02d", vm.reminderHour, vm.reminderMinute))
                                .font(HyperType.titleMedium)
                                .foregroundStyle(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showTimePicker) {
                        NavigationStack {
                            DatePicker(
                                "提醒时间",
                                selection: reminderTimeBinding,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .navigationTitle("提醒时间")
                            .navigationBarTitleDisplayMode(.inline)
                            .navigationBarItems(trailing: Button("完成") { showTimePicker = false })
                        }
                        .presentationDetents([.medium])
                    }
                }
            }
            .padding(14)
            .background(HyperRadius.cardShape.fill(palette.card))

            if vm.reminderOn, !reminderAuthorized {
                Text("若收不到提醒，请到系统「设置 → 通知 → 学习小助手」开启通知权限。")
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.leading, 6)
            }
        }
        .task { refreshAuthStatus() }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { vm.reminderOn },
            set: { newValue in
                if newValue {
                    // 开提醒要先拿授权：被拒就别硬开，回到关，并提示去系统设置
                    StudyReminderScheduler.requestAuthorization { granted in
                        Task { @MainActor in
                            if granted {
                                vm.reminderOn = true
                                vm.reminderDay = 1
                                reminderAuthorized = true
                                StudyReminderScheduler.reschedule(vm.settingsStore)
                            } else {
                                vm.reminderOn = false
                                reminderAuthorized = false
                            }
                        }
                    }
                } else {
                    vm.reminderOn = false
                    StudyReminderScheduler.reschedule(vm.settingsStore)
                }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = vm.reminderHour
                c.minute = vm.reminderMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                vm.reminderHour = c.hour ?? 19
                vm.reminderMinute = c.minute ?? 30
                StudyReminderScheduler.reschedule(vm.settingsStore)
            }
        )
    }

    private func refreshAuthStatus() {
        StudyReminderScheduler.authorizationStatus { status in
            Task { @MainActor in
                reminderAuthorized = (status == .authorized || status == .provisional)
            }
        }
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            MeRow(title: "错题本", icon: "tray.and.arrow.down.fill", tint: Hyper.miBlue) {
                router.push(.favorites)
            }
            divider
            MeRow(title: "搜题历史", icon: "magnifyingglass", tint: Hyper.miBlue) {
                router.push(.search)
            }
            divider
            MeRow(title: "模型服务设置", icon: "slider.horizontal.3", tint: Hyper.miBlue) {
                router.push(.settings)
            }
            divider
            MeRow(
                title: "连接测试", icon: "wifi", tint: Hyper.english,
                trailing: AnyView(PingStatus(pinging: vm.pinging, results: vm.pingResults))
            ) { vm.ping() }
            divider
            MeRow(title: "导出数据（zip）", icon: "arrow.up.doc", tint: Hyper.miOrange) {
                vm.exportBackup()
            }
            divider
            MeRow(title: "导入数据（zip）", icon: "arrow.down.doc", tint: Hyper.miOrange) {
                showImporter = true
            }
            divider
            MeRow(title: "清空所有数据", icon: "trash", tint: palette.error, danger: true) {
                showClearConfirm = true
            }
            divider
            MeRow(title: "关于", icon: "info.circle", tint: palette.textSecondary) {
                showAbout = true
            }
        }
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    private var divider: some View {
        Divider().padding(.leading, 62).opacity(0.6)
    }

    @ViewBuilder
    private var toast: some View {
        if let message = vm.message {
            Text(message)
                .font(HyperType.bodyMedium)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color(hex: 0x2B2F36).opacity(0.95)))
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation { vm.message = nil }
                }
        }
    }
}

// MARK: - 行组件

struct ThemeChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(HyperType.labelLarge)
                .foregroundStyle(selected ? palette.accent : palette.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(selected ? palette.accent.opacity(0.12) : Color.clear)
                )
                .overlay(Capsule().stroke(selected ? Color.clear : palette.divider, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

private struct MeRow: View {
    let title: String
    let icon: String
    let tint: Color
    var trailing: AnyView?
    var danger = false
    let action: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconBadge
                Text(title)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(danger ? palette.error : palette.text)
                Spacer()
                if let trailing {
                    trailing
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
        }
    }
}

/// 可跳转的行已经统一成 MeRow + router.push，这里不再单独定义一套行组件。

/// 「连接测试」行尾状态：没测过给个箭头，测中转圈，测完每家一个绿/红点。
/// 不拿箭头给一个不会跳转的动作用——那是「还有下一页」的意思。
struct PingStatus: View {
    let pinging: Bool
    let results: [PingResult]
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        if pinging {
            ProgressView()
                .scaleEffect(0.75)
                .frame(width: 16, height: 16)
        } else if results.isEmpty {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.textTertiary)
        } else {
            HStack(spacing: 10) {
                ForEach(results, id: \.provider) { result in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(result.ok ? Hyper.statusOk : palette.error)
                            .frame(width: 7, height: 7)
                        Text(result.provider)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - 系统能力桥接

/// 系统分享面板：导出 zip 直接落到「文件」App / AirDrop / 微信。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 「文件」App 选一个 zip 回来导入。
struct DocumentImporter: View {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false
    @State private var picked: URL?

    var body: some View {
        Group { EmptyView() }
            .fileImporter(
                isPresented: $shown,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                defer { dismiss() }
                guard case .success(let urls) = result, let url = urls.first else { return }
                onPick(url)
            }
            .onAppear { shown = true }
    }
}

enum NavPath { case none }
