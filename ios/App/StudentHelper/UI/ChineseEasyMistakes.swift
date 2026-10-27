import SwiftUI
import SHCore

/// 易错字辨析库：离线参考资料，放在「语文」页。
/// 与成语、古诗词库互补——这个专治「写错字」：形近字、音近字、用法易混（的/地/得、在/再…）。
/// 小学最普遍的扣分点就是错别字，每条给「辨析 + 口诀/例子」，点「用这组字去写」把辨析带进「新建批改」。

// MARK: - 数据模型

struct ConfusableGroup: Identifiable {
    let id: Int
    let category: String
    /// 容易混的字（与各自含义成对）。
    let chars: [(c: String, meaning: String)]
    /// 辨析：怎么区分。
    let distinction: String
    /// 一句好记的口诀或例子。
    let tip: String

    var prompt: String {
        let list = chars.map { "\($0.c)（\($0.meaning)）" }.joined(separator: "、")
        return """
        【易错字辨析：\(category)】
        这一组：\(list)
        辨析：\(distinction)
        口诀/例子：\(tip)
        """
    }
}

extension ConfusableGroup {
    static let all: [ConfusableGroup] = [
        ConfusableGroup(id: 7001, category: "形近字", chars: [
            ("已", "已经（半开）"), ("己", "自己（全开）"), ("巳", "巳时/全闭"),
        ], distinction: "看封口：已字半开（竖弯钩不封口），己字全开（竖弯钩敞开），巳字全闭（封口）。",
           tip: "口诀：已半封，己全封，巳字封死莫搞混。例：我已经（已）写完，这是我自己（己）的事。"),
        ConfusableGroup(id: 7002, category: "用法区分", chars: [
            ("的", "后面跟名词"), ("地", "后面跟动作"), ("得", "后面跟补充"),
        ], distinction: "的+名词（美丽的花）；地+动词（高兴地笑）；得+补语（跑得快）。",
           tip: "口诀：名词前面白勺的，动词前面土也地，形容词后双人得。"),
        ConfusableGroup(id: 7003, category: "用法区分", chars: [
            ("在", "存在/地点/正在"), ("再", "又一次/重复"),
        ], distinction: "在表示位置或正在进行（在家、在看书）；再表示重复或将来（再见、再写一遍）。",
           tip: "例：我在（在）教室，明天再（再）来。"),
        ConfusableGroup(id: 7004, category: "形近字", chars: [
            ("他", "指男人/人"), ("她", "指女人"), ("它", "指事物/动物"),
        ], distinction: "亻他指人（男），女她指女性，宀它指事物或动物。",
           tip: "例：他（他）来了，她（她）笑了，它（它）是一只猫。"),
        ConfusableGroup(id: 7005, category: "用法区分", chars: [
            ("做", "具体动作"), ("作", "抽象/书面"),
        ], distinction: "做多跟具体动作（做饭、做手工）；作多跟抽象或书面词（作业、工作、作文）。",
           tip: "例：我在做（做）作业，这篇作文（作）写得好。"),
        ConfusableGroup(id: 7006, category: "形近/音近", chars: [
            ("向", "方向/朝着"), ("像", "相似/好像"), ("象", "动物/形状"),
        ], distinction: "向指方向（向前）；像指相似（像苹果）；象指大象或形象（气象）。",
           tip: "例：向（向）前走，月亮像（像）小船，大像（象）很可爱。"),
        ConfusableGroup(id: 7007, category: "形近字", chars: [
            ("坐", "动作：坐下"), ("座", "名词：座位"),
        ], distinction: "坐是动作（坐下、坐车）；座是名词（座位、一座山）。",
           tip: "例：请坐（坐）下，这是我的座（座）位。"),
        ConfusableGroup(id: 7008, category: "形近/音近", chars: [
            ("进", "向内移动"), ("近", "距离短"),
        ], distinction: "进指从外到里（进门、进步）；近指距离或时间短（附近、最近）。",
           tip: "例：走进入（进）教室，学校很近（近）。"),
        ConfusableGroup(id: 7009, category: "形近字", chars: [
            ("晴", "日旁：天气晴"), ("睛", "目旁：眼睛"), ("清", "水旁：清澈"), ("情", "心旁：感情"),
        ], distinction: "日旁晴（晴天），目旁睛（眼睛），水旁清（清水），心旁情（心情）。",
           tip: "口诀：日晴目睛水清心情。例：晴（晴）天，眼睛（睛）亮，水很清（清），好心晴（情）。"),
        ConfusableGroup(id: 7010, category: "音近字", chars: [
            ("以", "用/因为/以后"), ("已", "已经"),
        ], distinction: "以表凭借或时间（以前、所以）；已表完成（已经、已往）。",
           tip: "例：以（以）后我要努力，作业已（已）经写完。"),
        ConfusableGroup(id: 7011, category: "形近字", chars: [
            ("休", "休息（人靠木）"), ("体", "身体（人本身）"),
        ], distinction: "休=人靠树（休息）；体=人本（身体、体育）。",
           tip: "例：星期天休（休）息，身体（体）要锻炼。"),
        ConfusableGroup(id: 7012, category: "形近字", chars: [
            ("未", "还没（未来）"), ("末", "结尾（末尾）"),
        ], distinction: "未上横短（未来、未知）；末上横长（末尾、周末）。",
           tip: "口诀：未来未短，末尾末长。例：未（未）来，周末（末）去玩。"),
    ]
}

// MARK: - 列表

struct ConfusableListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let sections: [(cat: String, items: [ConfusableGroup])]

    init() {
        var ordered: [String] = []
        var map: [String: [ConfusableGroup]] = [:]
        for g in ConfusableGroup.all {
            if map[g.category] == nil { ordered.append(g.category) }
            map[g.category, default: []].append(g)
        }
        sections = ordered.map { ($0, map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "易错字辨析",
                actions: AnyView(
                    IosTextButton(text: "去语文问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(0..<sections.count, id: \.self) { idx in
                        let sec = sections[idx]
                        sectionHeader(sec.cat)
                        ForEach(sec.items) { g in
                            ConfusableRow(group: g) { router.push(.confusableDetail(g.id)) }
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
                .fill(Hyper.chinese)
                .frame(width: 3, height: 16)
            Text(title)
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Spacer()
        }
        .padding(.horizontal, 14)
    }
}

private struct ConfusableRow: View {
    let group: ConfusableGroup
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(group.chars, id: \.c) { ch in
                        Text(ch.c)
                            .font(HyperType.titleMedium)
                            .foregroundStyle(palette.text)
                        if ch.c != group.chars.last?.c {
                            Text("/")
                                .font(HyperType.bodyMedium)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                }
                Text(group.distinction)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(group.category)
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.chinese)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Hyper.chinese.opacity(0.12)))
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

struct ConfusableDetailView: View {
    let group: ConfusableGroup
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(group.chars, id: \.c) { ch in
                        Text(ch.c)
                            .font(HyperType.title2)
                            .foregroundStyle(palette.text)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                charsBlock
                distinctionBlock
                tipBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "易错字练写：\(group.category)",
                        outline: group.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这组字去写")
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
            .padding(.bottom, 24)
        }
        .background(palette.background)
        .navigationTitle("易错字")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var charsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这几个字")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.chars, id: \.c) { ch in
                    HStack(spacing: 6) {
                        Text(ch.c)
                            .font(HyperType.titleMedium)
                            .foregroundStyle(palette.text)
                        Text(ch.meaning)
                            .font(HyperType.bodyMedium)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }

    private var distinctionBlock: some View {
        block(title: "怎么区分", text: group.distinction)
    }
    private var tipBlock: some View {
        block(title: "口诀 / 例子", text: group.tip)
    }

    private func block(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(text)
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
