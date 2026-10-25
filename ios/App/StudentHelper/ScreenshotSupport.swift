import Foundation
import SHCore

/// 云构建截图用的「确定性界面」入口。
///
/// 没有 Mac 的情况下，我唯一的眼睛就是 CI 里那台无头 iPhone 14 模拟器。
/// 要它截出有价值的图，必须满足两件事：
/// 1. 不依赖网络 —— 免费档随时 429，一挂就什么都截不到
/// 2. 不依赖手点 —— 启动参数直达目标界面，并预置一份固定数据
///
/// 用法：`xcrun simctl launch <UDID> com.example.studenthelper -uiTestScreen chatMath`
enum UITestScreen: String {
    case chatMath
    case chatChinese
    case chatEnglish
    case me
    case settings
    case favorites
    case compositionEmpty
    case compositionDetail
    case essay
    /// 搜题历史页
    case search
    /// 错题本自测出题页
    case selfTest
    /// 空对话页（「可以这样问」那一屏）
    case chatEmpty
    /// 作文模板库列表（离线参考资料，验证分类与条目排版）
    case compositionTemplates
    /// 作文模板库详情（框架 + 参考片段 + 「用模板去写」）
    case compositionTemplateDetail
}

enum ScreenshotMode {

    /// 启动参数 `-uiTestScreen <rawValue>`，或环境变量 UI_TEST_SCREEN
    static var screen: UITestScreen? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-uiTestScreen"), index + 1 < args.count {
            return UITestScreen(rawValue: args[index + 1])
        }
        if let value = ProcessInfo.processInfo.environment["UI_TEST_SCREEN"] {
            return UITestScreen(rawValue: value)
        }
        return nil
    }

    static var isActive: Bool { screen != nil }

    /// 错题本截图是否直接进自测出题页（否则永远只能截到列表态，出题卡无法验证）
    static var autoSelfTest: Bool { screen == .selfTest }

    /// 截图时预填的搜索关键词（`-uiTestQuery 圆`），让搜索页能截出结果态而不是空态
    static var query: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uiTestQuery"), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    /// 截图时强制主题。模拟器的 `simctl ui appearance dark` 在 CI 上不稳定
    /// （App 仍会拿到 light 的 colorScheme），所以直接从启动参数注入，保证深色可复现。
    static var themeOverride: ThemeMode? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uiTestTheme"), index + 1 < args.count else {
            return nil
        }
        return args[index + 1] == "dark" ? .dark : .light
    }

    // MARK: 预置数据

    /// 一条数学答案，故意覆盖最容易出问题的排版位置：
    /// 公式后紧跟句号、括号套公式、连等式、行尾标点。
    /// 这些正是安卓真机上出过事故、修完之后必须一直不复发的那些。
    static let mathAnswer = """
    【答案】
    第1题：答：\\( 28.26 \\) 平方厘米（\\( \\pi \\) 取 \\( 3.14 \\)）。
    第2题：答：\\( \\frac{5}{6} \\)。

    【题目在考什么】
    第1题考圆的面积公式。
    第2题考异分母分数加法。

    【常见错误】
    第1题的易错点：把半径当成直径，算成 \\( 3.14 \\times 6 \\times 6 \\)。还有漏写单位“平方厘米”。
    第2题的易错点：分母直接相加，写成 \\( \\frac{2}{5} \\)。

    【解题思路】
    第1步：找已知，半径 \\( r = 3 \\) cm。
    第2步：写公式，\\( S = \\pi r^2 \\)。
    第3步：代入算，\\( S = 3.14 \\times 3 \\times 3 \\)。
    第4步：\\( S = 28.26 \\) 平方厘米。

    【知识点小课堂】
    把圆分成很多小扇形，一正一反拼起来，近似一个长方形。长是圆周长的一半，也就是 \\( \\pi r \\)；宽是半径 \\( r \\)。所以面积是 \\( \\pi r \\times r = \\pi r^2 \\)。

    【改错建议与同类练习】
    建议：做圆面积题时，先把题里的“半径”或“直径”圈出来，看清给的是哪一个。
    练习1：一个圆的直径是 \\( 10 \\) cm，面积是多少？
    做完后再来核对答案。
    """

    static let chineseAnswer = """
    【答案】
    “绿”字用得好：它把春风写成了能看见的东西，江南岸一下子变绿了。

    【讲一讲】
    这句诗出自王安石的《泊船瓜洲》。
    “绿”本来是表示颜色的字，这里当动词用，是“吹绿了”的意思。
    换成“到”“过”“满”，都只是说风来了；用“绿”，眼前就有了颜色。

    【易错提醒】
    只答“用词生动”是不够的，要说清生动在哪里。

    【方法与练习】
    口诀：炼字先换词，一比见高低。
    练习：“红杏枝头春意闹”的“闹”字好在哪里？（答：把花开得繁茂写成了热闹的场面，有声音感。）
    """

    static let englishAnswer = """
    【答案】
    goes

    【题目在考什么】
    一般现在时，第三人称单数。
    分数读法示例：\\( \\frac{1}{2} \\) 读作 a half。

    【常见错误】
    He go to school. 漏了 s。

    【解题思路】
    第1步：every day 说明是经常发生的事，用一般现在时。
    第2步：主语 He 是第三人称单数，动词要加 s。
    第3步：go 变 goes。

    【知识点小课堂】
    口诀：我 you 我们你们用原形，他她它后面动词加 s。
    比较级记忆：短词加 -er，长词前加 more。

    【改错建议与同类练习】
    建议：写完先看主语是谁，再决定动词加不加 s。
    练习：She ___ (watch) TV on Sundays.
    做完后再来核对答案。
    """

    /// 往库里灌一份固定数据。每次 CI 构建看到的都是同一屏，截图才能用来对比。
    static func seed(into store: AppStore) {
        guard let screen else { return }
        let base = 1_700_000_000_000
        // 统计卡看的是「最近 7 天」，固定 2023 年的时间戳会让柱状图永远是空的。
        // 这里给「我的」页单独用相对今天的日期，才能截到真实的柱状图与连续天数。
        let today = Calendar.current.startOfDay(for: Date())
        func daysAgo(_ n: Int, hour: Int = 10) -> Int {
            let d = Calendar.current.date(byAdding: .day, value: -n, to: today)!
            let withHour = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
            return Int(withHour.timeIntervalSince1970 * 1000)
        }

        switch screen {
        case .chatMath:
            store.insert(Message(subject: "math", role: "user", textContent: "一个圆的半径是 3cm，面积是多少？1/2+1/3 呢？", createdAt: base))
            store.insert(Message(subject: "math", role: "assistant", textContent: mathAnswer, createdAt: base + 60_000))
        case .chatChinese:
            store.insert(Message(subject: "chinese", role: "user", textContent: "“春风又绿江南岸”里的“绿”字好在哪里？", createdAt: base))
            store.insert(Message(subject: "chinese", role: "assistant", textContent: chineseAnswer, createdAt: base + 60_000))
        case .chatEnglish:
            store.insert(Message(subject: "english", role: "user", textContent: "He ___ (go) to school every day. 应该填什么？", createdAt: base))
            store.insert(Message(subject: "english", role: "assistant", textContent: englishAnswer, createdAt: base + 60_000))
        case .chatEmpty:
            break
        case .me, .settings:
            // 用相对今天的数据，统计卡的「最近 7 天」和「连续天数」才截得出真实效果
            store.insert(Message(subject: "math", role: "user", textContent: "3/4 + 1/8 = ?", createdAt: daysAgo(0, hour: 9)))
            store.insert(Message(subject: "math", role: "assistant", textContent: "【答案】\n答：\\( \\frac{7}{8} \\)。", createdAt: daysAgo(0, hour: 9) + 60_000))
            store.insert(Message(subject: "math", role: "user", textContent: "一个圆的半径是 3cm，面积是多少？", createdAt: daysAgo(1, hour: 16)))
            store.insert(Message(subject: "math", role: "assistant", textContent: "【答案】\n答：28.26 平方厘米。", createdAt: daysAgo(1, hour: 16) + 60_000))
            store.insert(Message(subject: "chinese", role: "user", textContent: "“春风又绿江南岸”里的“绿”字好在哪里？", createdAt: daysAgo(2, hour: 20)))
            store.insert(Message(subject: "chinese", role: "assistant", textContent: "【答案】\n把春风写成了能看见的东西。", createdAt: daysAgo(2, hour: 20) + 60_000))
            store.insert(Message(subject: "english", role: "user", textContent: "He ___ (go) to school every day.", createdAt: daysAgo(4, hour: 19)))
            store.insert(Message(subject: "english", role: "assistant", textContent: "【答案】\ngoes", createdAt: daysAgo(4, hour: 19) + 60_000))
            // 让「我的」页截出提醒区块的「开启态」（含时间行），方便视觉核对排版。
            // 直接写 settings，不走 UI 授权流程，避免在 CI 模拟器上弹授权框卡住。
            SettingsStore().reminderOn = true
            SettingsStore().reminderHour = 19
            SettingsStore().reminderMinute = 30
        case .favorites, .selfTest:
            let q = store.insert(Message(subject: "math", role: "user", textContent: "一件衣服打八折后是 120 元，原价多少钱？", createdAt: base))
            let a = store.insert(Message(
                subject: "math", role: "assistant",
                textContent: "【答案】\n答：150 元。\n\n【讲一讲】\n八折就是 \\( \\frac{80}{100} \\)，原价乘它等于 120，所以原价是 \\( 120 \\div 0.8 = 150 \\) 元。",
                createdAt: base + 60_000
            ))
            _ = q
            store.toggleFavorite(messageId: a.id)
            // 再埋两条，让顶部「掌握概览」三类数字都非零，截图才看得出这个区块
            let a2 = store.insert(Message(
                subject: "chinese", role: "assistant",
                textContent: "【答案】\n把春风写成了能看见的东西。",
                createdAt: base + 180_000
            ))
            store.insert(Message(subject: "chinese", role: "user", textContent: "“春风又绿江南岸”的“绿”好在哪？", createdAt: base + 120_000))
            store.toggleFavorite(messageId: a2.id)
            store.setReviewed(messageId: a2.id, mastered: true)
            let a3 = store.insert(Message(
                subject: "english", role: "assistant",
                textContent: "【答案】\nwent",
                createdAt: base + 300_000
            ))
            store.insert(Message(subject: "english", role: "user", textContent: "He ___ (go) yesterday.", createdAt: base + 240_000))
            store.toggleFavorite(messageId: a3.id)
            store.setReviewed(messageId: a3.id, mastered: false)
        case .compositionEmpty:
            break
        case .compositionTemplates, .compositionTemplateDetail:
            // 模板库是离线静态数据（CompositionTemplate.all），无需预置，直接截真实内容
            break
        case .compositionDetail:
            store.insert(Composition(
                id: 1,
                title: "我的妈妈",
                content: "我的妈妈每天很早起床。她的头发有点卷，笑起来眼角弯弯的。",
                imageUris: "[]",
                aiFeedback: """
                {"总分":88,"分项":{"内容":23,"结构":22,"语言":22,"书写":21},
                 "总评":"写得真实，细节还可以再多一点。",
                 "优点":[{"位置":"第1段","内容":"笑起来眼角弯弯的","为什么好":"抓住了外貌特征"}],
                 "问题":[{"位置":"第1段","类型":"内容单薄","原句":"我的妈妈每天很早起床。","问题说明":"只说了做什么，没说怎么样","修改建议":"妈妈轻手轻脚地起床，怕把我吵醒。"}],
                 "改进建议":["给妈妈加一个动作","结尾呼应开头","加一句心理活动"],
                 "好句升级":[{"原句":"我的妈妈每天很早起床。","改写":"天还没亮，妈妈就轻手轻脚地起了床。","为什么更好":"有了画面"}],
                 "同类范文片段":"厨房的灯总是比我的闹钟醒得早。"}
                """,
                score: 88,
                createdAt: base
            ))
        case .essay:
            break
        case .search:
            // 搜索页要有可搜的内容：三科各埋一条，关键词「圆」能命中两条
            store.insert(Message(subject: "math", role: "user", textContent: "一个圆的半径是 3cm，面积是多少？", createdAt: daysAgo(0, hour: 9)))
            store.insert(Message(subject: "math", role: "assistant", textContent: "【答案】答：28.26 平方厘米。", createdAt: daysAgo(0, hour: 9) + 60_000))
            store.insert(Message(subject: "chinese", role: "user", textContent: "《圆的一周》这篇课文讲了什么？", createdAt: daysAgo(1, hour: 15)))
            store.insert(Message(subject: "chinese", role: "assistant", textContent: "【答案】讲了作者观察圆月的感受。", createdAt: daysAgo(1, hour: 15) + 60_000))
            store.insert(Message(subject: "english", role: "user", textContent: "circle 是什么意思？", createdAt: daysAgo(2, hour: 18)))
        }
    }
}
