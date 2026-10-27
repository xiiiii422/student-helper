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
                .environmentObject(appDelegate)
                .environment(\.hyperPalette, container.themeMode.resolvePalette(
                    systemDark: systemScheme == .dark
                ))
                .tint(container.palette(
                    systemDark: systemScheme == .dark
                ).accent)
                .preferredColorScheme(container.themeMode.colorScheme(systemScheme == .dark))
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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    /// 冷启动时 SwiftUI 视图还没建好，先攒着，等根视图出现再消费。
    ///
    /// 必须 @Published 且遵循 ObservableObject：以前它是普通 class 的普通属性，
    /// 改了不会通知 SwiftUI，`.onChange(of: appDelegate.pendingAction)` 永远不触发，
    /// 结果桌面长按的三个快捷操作全是摆设。
    @Published var pendingAction: QuickAction?

    /// 学习提醒从通知栏点进来：由本 delegate 转成通知，根容器监听后跳「我的」页。
    /// 必须在 didFinishLaunching 里设为 delegate 且设置时必须已经 assigned——
    /// 否则冷启动被点开的通知收不到。
    var pendingReminderOpen = false

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

        UNUserNotificationCenter.current().delegate = self

        // 已开启的提醒要在启动重排一次：iOS 自签 7 天过期、或用户清过通知后，
        // 系统会清掉所有 pending 通知，不重排就再也不响了。
        // 同时把「坚持天数」+1，文案每天轮换一条，给家长连续坚持的正反馈。
        let settings = SettingsStore()
        if settings.reminderOn {
            settings.reminderDay += 1
            // reschedule 标注 @MainActor（UNUserNotificationCenter 有主线程断言）。
            // didFinishLaunching 本身就在主线程，但编译器无法证明，用 Task 把调用
            // 挪到 @MainActor 上下文，比 assumeIsolated 更稳妥（后者在某些 Swift 版本
            // 对闭包内调用会触发编译器边界限制）。
            Task { @MainActor in
                StudyReminderScheduler.reschedule(settings)
            }
        }

        // 启动清一次角标：提醒带 badge，用户点开 App 后不该还挂着红点。
        // 不在这里清，角标会一直累加（每次提醒 +1），家长看着烦。
        application.applicationIconBadgeNumber = 0

        return true
    }

    // 前台收到通知也展示（默认前台不弹，体验上家长开着 App 时也该看到提醒）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // 用户点通知：转交给调度器，由它发 NotificationCenter 事件。
    // 本地通知冷启动**不**走 didFinishLaunching 的 launchOptions（那是远程推送的通道，
    // 本地通知冷启动同样会回调这里，但在 RootView 建立之前），所以用 pendingReminderOpen
    // 兜底：didReceive 先打标记，RootView 的 .task 消费并跳「我的」；热启动则直接被
    // .onReceive(studyReminderTapped) 捕获，两条路径幂等，不会跳两次。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        StudyReminderScheduler.handleLaunch(from: response)
        pendingReminderOpen = true
        completionHandler()
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

    /// 三科的 ChatViewModel 常驻在这里，而不是每个 Tab 页面自己 @StateObject。
    ///
    /// 以前切 Tab 会销毁 ChatView，连带销毁正在跑流式的 VM：旧 Task 拿着已死的 VM
    /// 继续写库，回到该科时新 VM 的 cleanupStale 又把空占位删掉，回答就静默丢了。
    /// VM 提升到容器后与 App 同生命周期，切走切回都只是换视图，流不受影响。
    ///
    /// 故意不用 @Published：VM 自身是 ObservableObject，视图拿 @ObservedObject 订阅即可；
    /// 在 body 里写 @Published 会触发「view update 期间发布变更」的警告甚至循环。
    private var chatVMCache: [String: ChatViewModel] = [:]

    @MainActor
    func chatVM(for subject: String) -> ChatViewModel {
        if let existing = chatVMCache[subject] { return existing }
        let vm = ChatViewModel(
            subject: subject, store: store, llm: llm, speech: speech
        )
        chatVMCache[subject] = vm
        return vm
    }

    /// 清空所有数据前调用：三科若有正在跑的流，先停掉，否则清完还会被写回几条
    @MainActor
    func stopAllStreams() {
        for vm in chatVMCache.values { vm.stopStreaming() }
    }

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.store = AppStore(fileURL: AppContainer.databaseURL())
        self.llm = LlmService(settings: settings)
        self.speech = SpeechService()
        self.themeMode = ThemeMode(rawValue: settings.themeMode) ?? .system
        // 截图模式可强制主题：CI 里模拟器外观有时不生效，这里保证深色图真能截出来
        if let forced = ScreenshotMode.themeOverride { self.themeMode = forced }

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

        // 清扫孤儿图片：早期版本删消息/清空学科时不删图片文件，靠这一步把存量泄漏收回来。
        //
        // 两个保险：
        // 1. 只有数据库成功读出来才清扫——解码失败时会得到空快照，照着清会把用户的图全删光；
        // 2. 按「文件名」比对而不是绝对路径——导入别的设备/重装后容器路径会变，
        //    按路径比会把所有图都判成孤儿。
        if store.didLoadExistingData {
            let referenced = Set(
                (store.backupSnapshot.messages.compactMap(\.imageUri)
                    + store.backupSnapshot.compositions.flatMap(\.imageUriList))
                    .map { ($0 as NSString).lastPathComponent }
            )
            let removed = FileStorage.sweepOrphans(keeping: referenced)
            if removed > 0 { print("[FileStorage] 清理孤儿图片 \(removed) 张") }
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
        case .selfTest: return (.me, .favorites)
        case .compositionEmpty: return (.composition, nil)
        case .compositionDetail: return (.composition, .compositionDetail(1))
        case .compositionTemplates: return (.composition, .templateList)
        case .compositionTemplateDetail: return (.composition, .templateDetail(101))
        case .compositionMaterials: return (.composition, .materialList)
        case .compositionMaterialDetail: return (.composition, .materialDetail(1001))
        case .poetryLibrary: return (.chinese, .poemList)
        case .poetryDetail: return (.chinese, .poemDetail(2001))
        case .mathReference: return (.math, .formulaList)
        case .mathFormulaDetail: return (.math, .formulaDetail(3001))
        case .englishReference: return (.english, .englishList)
        case .englishEntryDetail: return (.english, .englishDetail(4001))
        case .idiomLibrary: return (.chinese, .idiomList)
        case .idiomDetail: return (.chinese, .idiomDetail(5001))
        case .vocabLibrary: return (.english, .vocabList)
        case .vocabDetail: return (.english, .vocabDetail(6001))
        case .essay: return (.chinese, .essay)
        case .search: return (.me, .search)
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
    ///
    /// @Published + 计数器：同一个快捷操作可能被连按两次（比如已经停在错题本再点一次），
    /// 只存 action 的话值没变、onChange 不触发，界面不动。计数器保证每次都是一次新的触发。
    @Published var pendingRoute: QuickAction?
    @Published var pendingRouteNonce = 0

    /// 桌面快捷操作「拍照问一题」：告诉某一科的聊天页去弹相机。
    /// 用 nonce 而非 Bool，是为了连点两次时第二次也能触发（Bool 值没变就不触发）。
    @Published var photoRequestSubject: String?
    @Published var photoRequestNonce = 0

    func requestPhoto(for subject: String) {
        photoRequestSubject = subject
        photoRequestNonce += 1
    }

    func handle(_ action: QuickAction?) {
        guard let action else { return }
        pendingRoute = action
        pendingRouteNonce += 1
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
    @EnvironmentObject private var appDelegate: AppDelegate
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
            // 桌面长按快捷操作：AppDelegate 攒下意图后由这里消费。
            // 监听 nonce 而不是 action——同一个操作连按两次时 action 值不变，
            // 只监听 action 会导致第二次点了没反应。
            .onChange(of: container.pendingRouteNonce) { _ in
                applyQuickAction(container.pendingRoute, router: router)
            }
            // 学习提醒从通知栏点进来：AppDelegate 的 delegate 把意图转成通知事件，
            // 这里收到后落到「我的」页（提醒文案也建议去复习/看错题本，去我的页最顺）。
            // 「我的」是底部 tab，不是导航栈里的 Route，所以只切 tab + 清空栈即可。
            .onReceive(NotificationCenter.default.publisher(for: .studyReminderTapped)) { _ in
                selection = .me
                router.popToRoot()
            }
            // 冷启动就是被提醒点开的：AppDelegate 标记后这里直接去「我的」页
            .task {
                if appDelegate.pendingReminderOpen {
                    selection = .me
                    router.popToRoot()
                }
            }
        } destination: { route in
            AnyView(subPage(route))
        }
    }

    /// CI 截图模式：启动后直接落到指定子页面，不靠人工点
    private func applyLanding(_ router: Router) {
        if let tab = container.initialTab { selection = tab }
        if let route = container.initialRoute { router.push(route) }
    }

    /// 消费桌面长按的快捷操作。以前这些方法只是改了没人读的变量，点了完全没反应。
    private func applyQuickAction(_ action: QuickAction?, router: Router) {
        guard let action else { return }
        switch action {
        case .askByPhoto:
            selection = .math
            // 回到根再通知该科弹出拍照：直接改 selection 时 VM 已经常驻，
            // 用容器把意图转给对应学科的 VM
            router.popToRoot()
            container.requestPhoto(for: "math")
        case .essay:
            selection = .chinese
            router.popToRoot()
            router.push(.essay)
        case .favorites:
            selection = .me
            router.popToRoot()
            router.push(.favorites)
        }
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
            MeView(vm: {
                let vm = MeViewModel(
                    llm: container.llm, store: container.store, settings: container.settings
                )
                vm.onStopAllStreams = { container.stopAllStreams() }
                return vm
            }())
            .id("me")
        }
    }

    private func chatPage(subject: String, title: String) -> some View {
        ChatView(
            title: title,
            subject: subject,
            tabSelection: $selection,
            vm: container.chatVM(for: subject)
        )
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
        case .templateList:
            CompositionTemplateListView()
        case .templateDetail(let id):
            CompositionTemplateDetailView(
                template: CompositionTemplate.all.first(where: { $0.id == id })
                    ?? CompositionTemplate.all[0]
            )
        case .materialList:
            CompositionMaterialsListView()
        case .materialDetail(let id):
            CompositionMaterialDetailView(
                material: WritingMaterial.all.first(where: { $0.id == id })
                    ?? WritingMaterial.all[0]
            )
        case .poemList:
            PoetryLibraryListView()
        case .poemDetail(let id):
            PoemDetailView(
                poem: Poem.all.first(where: { $0.id == id })
                    ?? Poem.all[0]
            )
        case .formulaList:
            MathReferenceListView()
        case .formulaDetail(let id):
            MathFormulaDetailView(
                formula: MathFormula.all.first(where: { $0.id == id })
                    ?? MathFormula.all[0]
            )
        case .englishList:
            EnglishReferenceListView()
        case .englishDetail(let id):
            EnglishEntryDetailView(
                entry: EnglishEntry.all.first(where: { $0.id == id })
                    ?? EnglishEntry.all[0]
            )
        case .idiomList:
            IdiomLibraryListView()
        case .idiomDetail(let id):
            IdiomDetailView(
                idiom: Idiom.all.first(where: { $0.id == id })
                    ?? Idiom.all[0]
            )
        case .vocabList:
            EnglishVocabListView()
        case .vocabDetail(let id):
            EnglishVocabDetailView(
                group: VocabGroup.all.first(where: { $0.id == id })
                    ?? VocabGroup.all[0]
            )
        case .compositionNewWithTemplate(let title, let outline):
            CompositionNewView(
                vm: CompositionNewViewModel(
                    store: container.store, llm: container.llm
                ),
                prefillTitle: title,
                prefillRequirement: outline
            )
        case .compositionDetail(let id):
            CompositionDetailView(id: id, vm: CompositionDetailViewModel(
                id: id, store: container.store, llm: container.llm
            ))
        case .essay:
            EssayView(vm: EssayViewModel(llm: container.llm, store: container.store))
        case .search:
            SearchView(store: container.store, initialQuery: ScreenshotMode.query ?? "") { subject in
                // 点一条结果：回根再切到对应学科，能接着看完整问答
                if let tab = BottomTab(rawValue: subject) { selection = tab }
            }
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
///
/// 打包/解包要读全部原图并逐条算 CRC，几十张图就是几百 MB 的内存搬运——
/// 以前全在主线程跑，真机上点「导出」界面直接冻住好几秒，所以整体挪到后台。
enum BackupService {

    static func export(store: AppStore) async throws -> URL {
        let snapshot = store.backupSnapshot
        let imagesDir = FileStorage.imagesDirectory
        return try await Task.detached(priority: .userInitiated) {
            guard !snapshot.messages.isEmpty || !snapshot.compositions.isEmpty || !snapshot.favorites.isEmpty else {
                throw BackupError.nothingToExport
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = try enc.encode(snapshot)

            var entries = [Zip.Entry(name: "data.json", data: json)]
            let images = (try? FileManager.default.contentsOfDirectory(
                at: imagesDir, includingPropertiesForKeys: nil
            )) ?? []
            for name in images {
                guard let data = try? Data(contentsOf: name) else { continue }
                entries.append(Zip.Entry(name: "images/" + name.lastPathComponent, data: data))
            }

            let stamp = Timestamp.format(Int(Date().timeIntervalSince1970 * 1000))
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "/", with: "")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("student-helper-backup-\(stamp)-\(UUID().uuidString.prefix(4)).zip")
            try Zip.write(entries).write(to: url)
            return url
        }.value
    }

    static func importArchive(from url: URL, store: AppStore) async throws {
        // 「文件」App 给的是安全作用域资源，必须先 startAccessing 才读得到。
        //
        // 关键：**不能把 URL 直接丢进后台任务里读**。
        // 以前 Data(contentsOf: url) 在 Task.detached 里跑，而 stopAccessing 的 defer
        // 在主线程——异步任务还没读到文件，授权可能就已经被撤销了，
        // 真机上表现为「导入偶尔失败」，时好时坏最难查。
        // 所以这里趁作用域还有效，先把整个文件读进内存，再交给后台解包。
        var scoped = false
        if url.isFileURL { scoped = url.startAccessingSecurityScopedResource() }
        let fileData: Data?
        if scoped {
            fileData = try? Data(contentsOf: url)
            url.stopAccessingSecurityScopedResource()
        } else {
            fileData = try? Data(contentsOf: url)
        }

        let imagesDir = FileStorage.imagesDirectory
        let (snapshot, imageFiles) = try await Task.detached(priority: .userInitiated) {
            guard let data = fileData else { throw BackupError.archiveUnreadable }
            let entries = try Zip.read(data)
            guard let jsonEntry = entries.first(where: { $0.name == "data.json" }) else {
                throw BackupError.archiveUnreadable
            }
            let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: jsonEntry.data)

            var files: [(name: String, data: Data)] = []
            for entry in entries where entry.name.hasPrefix("images/") {
                // 只取文件名：备份包是外部文件，条目名里塞 "../" 就能写到沙盒外面去
                let name = (String(entry.name.dropFirst("images/".count)) as NSString).lastPathComponent
                guard !name.isEmpty, name != ".", name != ".." else { continue }
                files.append((name, entry.data))
            }
            return (snapshot, files)
        }.value

        for file in imageFiles {
            try? file.data.write(to: imagesDir.appendingPathComponent(file.name))
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
