import SwiftUI
import SHCore

/// 英语常用句型 / 语法速查：离线参考资料，放在「英语」页。
/// 与作文模板库 / 好词好句库 / 古诗词库 / 数学公式库同模式——纯静态、不联网、CI 截图走确定性路径。
/// 把小学最常用、最容易写错的句型（there be、一般现在时三单、比较级、can/like doing 等）
/// 集中成随身速查，点「用这条去练」把造句要求带进「新建批改」。

// MARK: - 数据模型

struct EnglishEntry: Identifiable, Hashable {
    let id: Int
    let category: String
    let title: String
    /// 句型 / 结构本体（可直接照着套）。
    let pattern: String
    /// 怎么用、注意点、常错处。
    let note: String

    var prompt: String {
        """
        【句型练笔：\(title)】
        结构：
        \(pattern)

        用法提示：
        \(note)
        """
    }
}

extension EnglishEntry {
    static let all: [EnglishEntry] = [
        // 基础句型
        EnglishEntry(id: 4001, category: "基础句型", title: "There be 某处有某物", pattern: "There is + 单数名词\nThere are + 复数名词", note: "表示「有」，就近原则：be 动词跟最近的名词走。There is a book and two pens. 别写成 There have。"),
        EnglishEntry(id: 4002, category: "基础句型", title: "主系表", pattern: "主语 + be + 形容词/名词", note: "I am happy. She is a student. 第三人称单数用 is，you/we/they 用 are，I 用 am。"),
        EnglishEntry(id: 4003, category: "基础句型", title: "主谓宾", pattern: "主语 + 动词 + 宾语", note: "He likes apples. 注意主语是三单时动词要加 s/es。"),
        EnglishEntry(id: 4004, category: "基础句型", title: "祈使句", pattern: "动词原形开头", note: "Open the door. Don't run. 表示请求、命令，开头用动词原形，否定加 Don't。"),

        // 时态
        EnglishEntry(id: 4101, category: "时态", title: "一般现在时（三单）", pattern: "主语(三单) + 动词 + s/es", note: "he/she/it 作主语，动词加 s/es：go→goes, watch→watches。最易漏，写完先看主语。"),
        EnglishEntry(id: 4102, category: "时态", title: "现在进行时", pattern: "be (am/is/are) + 动词-ing", note: "表示正在做：I am reading. 动词加 -ing，be 动词要跟着主语变。"),
        EnglishEntry(id: 4103, category: "时态", title: "一般过去时", pattern: "主语 + 动词过去式", note: "yesterday/last week 提示用过去时。规则动词加 -ed，不规则要背（go→went, eat→ate）。"),
        EnglishEntry(id: 4104, category: "时态", title: "一般将来时", pattern: "will + 动词原形 / be going to + 动词原形", note: "表示将来。tomorrow/next 提示用。will 不分人称，后面永远用原形。"),

        // 比较
        EnglishEntry(id: 4201, category: "比较", title: "原级 / 比较级 / 最高级", pattern: "as + 原级 + as\n比较级 + than\nthe + 最高级", note: "短词加 -er/-est（tall→taller→tallest），长词前加 more/most。than 前用比较级。"),
        EnglishEntry(id: 4202, category: "比较", title: "选择疑问句", pattern: "Which ... do you like, A or B?", note: "用 or 连接选项，不直接用 yes/no 回答。I like A."),

        // 情态与搭配
        EnglishEntry(id: 4301, category: "情态与搭配", title: "can 能 / 会", pattern: "can + 动词原形", note: "表示能力。后面永远用原形，不分人称：He can swim. 否定 can't，疑问 Can you ...?"),
        EnglishEntry(id: 4302, category: "情态与搭配", title: "like doing / like to do", pattern: "like + 动词-ing", note: "表示长期的爱好用 like doing：I like swimming. 注意 like 后跟 -ing 或名词。"),
        EnglishEntry(id: 4303, category: "情态与搭配", title: "want 想要", pattern: "want to + 动词原形 / want + 名词", note: "I want to go. / I want an apple. want 后接动词必须加 to。"),
        EnglishEntry(id: 4304, category: "情态与搭配", title: "have / has 有", pattern: "I/you/we/they have\nHe/She/It has", note: "「有」作实义动词时三单用 has。和 there be（某处有）区分开。"),

        // 疑问
        EnglishEntry(id: 4401, category: "疑问词", title: "Wh- 问句", pattern: "What/Who/Where/When/Why + 一般疑问句", note: "What 问物，Who 问人，Where 问地点，When 问时间，Why 问原因。句首用疑问词，后面倒装。"),
        EnglishEntry(id: 4402, category: "疑问词", title: "How many / How much", pattern: "How many + 可数复数\nHow much + 不可数", note: "问数量。many 跟可数名词复数（apples），much 跟不可数（water/money）。"),

        // 写作常用
        EnglishEntry(id: 4501, category: "写作常用", title: "首尾句模板", pattern: "开头：I like ... because ...\n结尾：I love ... very much.", note: "写英语小作文最稳的开头结尾。开头说清楚喜欢什么、为什么，结尾点题表态。"),
        EnglishEntry(id: 4502, category: "写作常用", title: "连接词", pattern: "and / but / because / so", note: "and 并列，but 转折，because 原因，so 结果。用它们把简单句连成通顺段落，作文立刻加分。"),
        EnglishEntry(id: 4503, category: "写作常用", title: "描述天气", pattern: "It is + 形容词 (+ today).", note: "It is sunny/rainy/windy. 描述天气用 it 作主语，不是 I am sunny。"),
        EnglishEntry(id: 4504, category: "写作常用", title: "描述能力/爱好", pattern: "I can ... and I like ...", note: "自我介绍/爱好类作文常用：I can sing and I like drawing. 一能一好，结构清楚。"),
    ]
}

// MARK: - 列表

private struct EntryGroup: Identifiable {
    let category: String
    let items: [EnglishEntry]
    var id: String { category }
}

struct EnglishReferenceListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [EntryGroup]

    init() {
        var ordered: [String] = []
        var map: [String: [EnglishEntry]] = [:]
        for e in EnglishEntry.all {
            if map[e.category] == nil { ordered.append(e.category) }
            map[e.category, default: []].append(e)
        }
        groups = ordered.map { EntryGroup(category: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "句型语法",
                actions: AnyView(
                    IosTextButton(text: "去英语问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.category)
                        ForEach(group.items) { e in
                            EntryRow(entry: e) { router.push(.englishDetail(e.id)) }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .background(palette.background)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Hyper.english)
                .frame(width: 3, height: 16)
            Text(title)
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Spacer()
        }
        .padding(.horizontal, 14)
    }
}

private struct EntryRow: View {
    let entry: EnglishEntry
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Text(entry.pattern.replacingOccurrences(of: "\n", with: "  "))
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.category)
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.english)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Hyper.english.opacity(0.12)))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(14)
            .background(HyperRadius.cardShape.fill(palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 详情

struct EnglishEntryDetailView: View {
    let entry: EnglishEntry
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text(entry.category)
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.english)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Hyper.english.opacity(0.12)))
                    Spacer()
                }
                .padding(.horizontal, 14)

                Text(entry.title)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)

                patternBlock
                noteBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "句型练笔：\(entry.title)",
                        outline: entry.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这条去练")
                            .font(HyperType.titleMedium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Hyper.miBlue))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(palette.background)
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var patternBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("结构")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(entry.pattern)
                .font(HyperType.body)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么用 · 常错点")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(entry.note)
                .font(HyperType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }
}
