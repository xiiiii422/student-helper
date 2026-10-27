import SwiftUI
import SHCore

/// 子路由。安卓用 Navigation Compose 的字符串路由，iOS 侧对应一个枚举，
/// 好处是编译期就能挡住拼错的目的地。
enum Route: Hashable {
    case favorites
    case search
    case settings
    case compositionNew
    case compositionDetail(Int)
    case essay
    case templateList
    case templateDetail(Int)
    case materialList
    case materialDetail(Int)
    case poemList
    case poemDetail(Int)
    case formulaList
    case formulaDetail(Int)
    case englishList
    case englishDetail(Int)
    case idiomList
    case idiomDetail(Int)
    case vocabList
    case vocabDetail(Int)
    case confusableList
    case confusableDetail(Int)
    case dialogueList
    case dialogueDetail(Int)
    case problemList
    case problemDetail(Int)
    case polyphoneList
    case polyphoneDetail(Int)
    case compositionNewWithTemplate(title: String, outline: String)
}

/// 导航栈容器。子页面（错题本 / 模型服务设置 / 新建作文 / 作文详情 / 生成作文）
/// 整屏压入并隐藏底栏 —— 与安卓 AppNavHost 只在顶层路由显示 bottomBar 的表现一致。
@MainActor
final class Router: ObservableObject {
    @Published var path: [Route] = []

    func push(_ route: Route) {
        if path.last != route { path.append(route) }
        Haptics.lightTap()
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}

/// 把 Router 注入到整棵视图树，子视图只写 `@EnvironmentObject var router: Router`。
struct RootScaffold<Content: View>: View {
    @StateObject private var router = Router()
    @Environment(\.hyperPalette) private var palette

    private let contentBuilder: (Router) -> Content
    /// 子页面长什么样由 App 根决定，这里只负责压栈与深浅色背景。
    private let destinationBuilder: (Route) -> AnyView

    // 不能写成 `@ViewBuilder var content: (Router) -> Content`：
    // 那是「用一个 ViewBuilder 去构造一个关包」，编译期会把整个闭包当成单个 View。
    // 正确做法是存两个普通闭包，在 body 里调用。
    init(
        @ViewBuilder content: @escaping (Router) -> Content,
        @ViewBuilder destination: @escaping (Route) -> AnyView
    ) {
        self.contentBuilder = content
        self.destinationBuilder = destination
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            contentBuilder(router)
                .navigationDestination(for: Route.self) { route in
                    destinationBuilder(route)
                        .background(palette.background.ignoresSafeArea())
                }
        }
        .environmentObject(router)
        .tint(palette.accent)
    }
}
