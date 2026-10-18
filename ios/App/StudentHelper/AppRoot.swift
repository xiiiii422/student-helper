import SwiftUI
import UIKit
import SHCore

// MARK: - 应用入口

@main
struct StudentHelperApp: App {
    /// 首页快捷操作（长按桌面图标）需要 AppDelegate 接管，SwiftUI 侧只负责把意图转给根视图。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer()
    @Environment(\.colorScheme) private var systemScheme

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.speech)
                .environment(\.hyperPalette, container.themeMode.resolvePalette(
                    systemDark: systemScheme == .dark
                ))
                .tint(container.palette(
                    systemDark: systemScheme == .dark
                ).accent)
                .preferredColorScheme(container.themeMode.colorScheme(systemDark: systemScheme == .dark))
                .onOpenURL { url in container.handle(url: url) }
                .environment(\.quickAction, appDelegate.pendingAction)
                .onChange(of: appDelegate.pendingAction) { action in
                    container.handle(action)
                }
        }
    }
}

/// 长按桌面图标的三个入口。安卓侧对应长按快捷方式，iOS 上这是原生能力，用起来比开 App 再找快一步。
enum QuickAction: String {
    case askByPhoto = "ask-by-photo"
    case essay = "essay"
    case favorites = "favorites"
}

private struct QuickActionKey: EnvironmentKey {
    static let defaultValue: QuickAction? = nil
}

extension EnvironmentValues {
    var quickAction: QuickAction? {
        get { self[QuickActionKey.self] }
        set { self[QuickActionKey.self] = newValue }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// 冷启动时 SwiftUI 视图还没建好，先攒着，等根视图出现再消费。
    var pendingAction: QuickAction?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickAction.askByPhoto.rawValue,
                localizedTitle: "拍照问一题",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "camera")
            ),
            UIApplicationShortcutItem(
                type: QuickAction.essay.rawValue,
                localizedTitle: "生成作文",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil")
            ),
            UIApplicationShortcutItem(
                type: QuickAction.favorites.rawValue,
                localizedTitle: "错题本",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "star")
            ),
        ]
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        pendingAction = QuickAction(rawValue: shortcutItem.type)
        completionHandler(true)
    }
}

// MARK: - 依赖容器

/// 手工依赖注入。安卓用 Hilt，iOS 侧这个 App 只有四五个单例，
/// 引一个 DI 框架不值当，容器一目了然更好维护。
@MainActor
final class AppContainer: ObservableObject {
    let settings: SettingsStore
    let store: AppStore
    let llm: LlmService
    let speech: SpeechService
    /// 主题模式变化要重算 colorScheme，所以它是 @Published
    @Published var themeMode: ThemeMode
    /// CI 截图模式下的开局界面（正常启动时为 nil，走默认）
    let initialTab: BottomTab?
    let initialRoute: Route?

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.store = AppStore(fileURL: AppContainer.databaseURL())
        self.llm = LlmService(settings: settings)
        self.speech = SpeechService()
        self.themeMode = ThemeMode(rawValue: settings.themeMode) ?? .system

        // 截图模式：先把库刷成固定数据再预置开局界面，保证每次 CI 看到的都是同一屏
        if let screen = ScreenshotMode.screen {
            store.clearAll()
            ScreenshotMode.seed(into: store)
            let (tab, route) = AppContainer.landing(for: screen)
            initialTab = tab
            initialRoute = route
        } else {
            initialTab = nil
            initialRoute = nil
        }
    }

    private static func landing(for screen: UITestScreen) -> (BottomTab, Route?) {
        switch screen {
        case .chatMath: return (.math, nil)
        case .chatChinese: return (.chinese, nil)
        case .chatEnglish: return (.english, nil)
        case .chatEmpty: return (.math, nil)
        case .me: return (.me, nil)
        case .settings: return (.me, .settings)
        case .favorites: return (.me, .favorites)
        case .compositionEmpty: return (.composition, nil)
        case .compositionDetail: return (.composition, .compositionDetail(1))
        case .essay: return (.chinese, .essay)
        }
    }

    static func databaseURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("student_helper.json")
    }

    func palette(systemDark: Bool) -> HyperPalette {
        themeMode.resolvePalette(systemDark: systemDark)
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        settings.themeMode = mode.rawValue
    }

    /// 首页快捷操作由根视图消费：告诉它要跳到哪。
    var pendingRoute: QuickAction?
    var pendingRouteObserver = UUID()

    func handle(_ action: QuickAction?) {
        guard let action else { return }
        pendingRoute = action
        pendingRouteObserver = UUID()
    }

    func handle(url: URL) {
        // 预留：以后接 Siri 快捷指令或「文件」App 的导入
        guard url.scheme == "studenthelper" else { return }
        switch url.host {
        case "essay": handle(.essay)
        case "favorites": handle(.favorites)
        default: break
        }
    }
}

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hyperPalette) private var palette
    @State private var selection: BottomTab = .chinese

    var body: some View {
        RootScaffold { router in
            VStack(spacing: 0) {
                tabContent
            }
            .background(palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppBottomBar(selection: $selection)
            }
            .task { applyLanding(router) }
        } destination: { route in
            AnyView(subPage(route))
        }
    }

    /// CI 截图模式：启动后直接落到指定子页面，不靠人工点
    private func applyLanding(_ router: Router) {
        if let tab = container.initialTab { selection = tab }
        if let route = container.initialRoute { router.push(route) }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .chinese:
            chatPage(subject: "chinese", title: "语文")
        case .math:
            chatPage(subject: "math", title: "数学")
        case .english:
            chatPage(subject: "english", title: "英语")
        case .composition:
            CompositionListView(
                vm: CompositionListViewModel(store: container.store)
            )
            .id("composition")
        case .me:
            MeView(vm: MeViewModel(
                llm: container.llm, store: container.store, settings: container.settings
            ))
            .id("me")
        }
    }

    private func chatPage(subject: String, title: String) -> some View {
        ChatView(
            title: title,
            subject: subject,
            tabSelection: $selection
        ) { topic in
            ChatViewModel(
                subject: topic,
                store: container.store,
                llm: container.llm,
                speech: container.speech
            )
        }
        .id(subject)
    }

    @ViewBuilder
    private func subPage(_ route: Route) -> some View {
        switch route {
        case .favorites:
            FavoritesView(vm: FavoritesViewModel(store: container.store))
        case .settings:
            SettingsView(vm: SettingsViewModel(
                settings: container.settings, llm: container.llm, speech: container.speech
            ))
        case .compositionNew:
            CompositionNewView(vm: CompositionNewViewModel(
                store: container.store, llm: container.llm
            ))
        case .compositionDetail(let id):
            CompositionDetailView(id: id, vm: CompositionDetailViewModel(
                id: id, store: container.store
            ))
        case .essay:
            EssayView(vm: EssayViewModel(llm: container.llm, store: container.store))
        }
    }
}

// MARK: - 关于

enum AppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    /// 版本号取自 Info.plist，不写死：写死过一次，改了十几次代码还显示 1.0.0。
    static var aboutText: String {
        """
        版本 \(version)（\(build)）· 自用版

        面向小学六年级的试题讲解与作文批改助手。数据仅存本机，可在「我的」页导出备份。
        讲题与批改直连智谱 GLM 与 DeepSeek，两家互为备用。
        """
    }
}

// MARK: - 备份

enum BackupError: LocalizedError {
    case nothingToExport
    case archiveUnreadable

    var errorDescription: String? {
        switch self {
        case .nothingToExport: return "还没有任何数据可导出"
        case .archiveUnreadable: return "这个文件不是本 App 导出的备份包"
        }
    }
}

/// 备份：数据 JSON + 图片目录打成一个 zip。文件名与安卓 BackupManager 保持一致，
/// 这样两端可以互相恢复对方的备份。
enum BackupService {

    static func export(store: AppStore) throws -> URL {
        let snapshot = store.backupSnapshot
        guard !snapshot.messages.isEmpty || !snapshot.compositions.isEmpty || !snapshot.favorites.isEmpty else {
            throw BackupError.nothingToExport
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try enc.encode(snapshot)

        var entries = [Zip.Entry(name: "data.json", data: json)]
        let images = (try? FileManager.default.contentsOfDirectory(
            at: FileStorage.imagesDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for name in images {
            guard let data = try? Data(contentsOf: name) else { continue }
            entries.append(Zip.Entry(name: "images/" + name.lastPathComponent, data: data))
        }

        let stamp = Timestamp.format(Int(Date().timeIntervalSince1970 * 1000))
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("student-helper-backup-\(stamp).zip")
        try Zip.write(entries).write(to: url)
        return url
    }

    static func importArchive(from url: URL, store: AppStore) throws {
        // 「文件」App 给的是安全作用域资源，必须先 startAccessing 才读得到
        var scoped = false
        if url.isFileURL { scoped = url.startAccessingSecurityScopedResource() }
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw BackupError.archiveUnreadable }
        let entries = try Zip.read(data)
        guard let jsonEntry = entries.first(where: { $0.name == "data.json" }) else {
            throw BackupError.archiveUnreadable
        }
        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: jsonEntry.data)

        for entry in entries where entry.name.hasPrefix("images/") {
            let name = String(entry.name.dropFirst("images/".count))
            guard !name.isEmpty else { continue }
            try entry.data.write(to: FileStorage.imagesDirectory.appendingPathComponent(name))
        }
        store.replaceAll(with: snapshot)
    }
}

// MARK: - 小工具

// Foundation 自带 URL.startAccessingSecurityScopedResource()/stopAccessingSecurityScopedResource()，
// 原代码又声明了一遍（invalid redeclaration），已删除。

extension Optional where Wrapped == URL {
    var asIdentifiableURL: IdentifiableURL? {
        guard let self else { return nil }
        return IdentifiableURL(value: self)
    }
}

struct IdentifiableURL: Identifiable {
    let value: URL
    var id: String { value.path }
}
