import SwiftUI
import UIKit

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

    private let llm: LlmService
    private let store: AppStore
    private let settings: SettingsStore

    init(llm: LlmService, store: AppStore, settings: SettingsStore) {
        self.llm = llm
        self.store = store
        self.settings = settings
        self.themeMode = ThemeMode(rawValue: settings.themeMode) ?? .system
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
    func exportBackup() {
        do {
            let url = try BackupService.export(store: store)
            exportUrl = url
            Haptics.success()
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    func importBackup(from url: URL) {
        do {
            try BackupService.importArchive(from: url, store: store)
            importDone = true
            message = "导入完成，重启后生效"
            Haptics.success()
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    func clearAll() {
        store.clearAll()
        FileStorage.deleteAllImages()
        message = "已清空全部数据"
    }
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
                themeSection
                listCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(palette.background)
        .overlay(alignment: .bottom) { toast }
        .sheet(isPresented: $showImporter) {
            DocumentImporter { url in vm.importBackup(from: url) }
        }
        .sheet(item: $vm.exportUrl.asIdentifiableURL) { item in
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(HyperRadius.cardShape.fill(palette.card))
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

    private var listCard: some View {
        VStack(spacing: 0) {
            MeRow(title: "错题本", icon: "tray.and.arrow.down.fill", tint: Hyper.miBlue) {
                router.push(.favorites)
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

private struct ThemeChip: View {
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
