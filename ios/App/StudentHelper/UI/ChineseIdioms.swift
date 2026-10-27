import SwiftUI
import SHCore

/// 成语解释库：离线参考资料，放在「语文」页。
/// 与作文模板库 / 好词好句库 / 古诗词库同模式——纯静态、不联网、CI 截图走确定性路径。
/// 成语是小学语文的硬骨头：不光要会写，还要懂意思和出处。每条给「释义 + 小故事 + 造句」，
/// 点「用这个成语去写」把成语带进「新建批改」要求栏，练把成语用进作文里。

// MARK: - 数据模型

struct Idiom: Identifiable, Hashable {
    let id: Int
    let category: String
    let word: String
    let pinyin: String
    /// 释义：字面 + 比喻义。
    let meaning: String
    /// 出处 / 小故事，帮学生记得住。
    let story: String
    /// 怎么造句、怎么化用进作文。
    let usage: String

    var prompt: String {
        """
        【成语练笔：\(word)】
        释义：\(meaning)
        小故事：\(story)
        怎么用：\(usage)
        """
    }
}

extension Idiom {
    /// 固定示例库。全部离线，不依赖网络，CI 截图也走同一条确定性路径。
    static let all: [Idiom] = [
        // 寓言成语
        Idiom(id: 5001, category: "寓言成语", word: "画蛇添足", pinyin: "huà shé tiān zú",
              meaning: "画蛇时给蛇添上脚。比喻做了多余的事，反而把事情弄糟。",
              story: "楚国人比赛画蛇，一人先画完，见别人没画完，就给蛇添脚，结果反而输了。",
              usage: "写「多此一举反而坏事」时用：本来已经够好了，再改反而画蛇添足。"),
        Idiom(id: 5002, category: "寓言成语", word: "守株待兔", pinyin: "shǒu zhū dài tù",
              meaning: "守着树桩等兔子撞上来。比喻不主动努力，存侥幸心理，指望不劳而获。",
              story: "农夫见一只兔撞死在树桩上，便天天守着等下一只，地也不种了。",
              usage: "写「不能靠运气」时用：学习要踏实，不能守株待兔。"),
        Idiom(id: 5003, category: "寓言成语", word: "亡羊补牢", pinyin: "wáng yáng bǔ láo",
              meaning: "羊丢了再修羊圈。比喻出了问题及时补救，还不算晚。",
              story: "养羊人丢了羊才修圈，邻居说晚了吗，他说现在修还不晚，后来果然没再丢。",
              usage: "写「知错就改」时用：犯了错马上改，亡羊补牢为时不晚。"),
        Idiom(id: 5004, category: "寓言成语", word: "掩耳盗铃", pinyin: "yǎn ěr dào líng",
              meaning: "捂住自己的耳朵去偷铃铛。比喻自己骗自己，以为别人也不知道。",
              story: "小偷怕铃响被人听见，捂住自己耳朵去偷，却忘了别人照样能听见。",
              usage: "写「自欺欺人」时用：掩盖错误就像掩耳盗铃，骗不了别人。"),
        Idiom(id: 5005, category: "寓言成语", word: "井底之蛙", pinyin: "jǐng dǐ zhī wā",
              meaning: "井底的青蛙以为天只有井口大。比喻见识短浅的人。",
              story: "青蛙在井底，以为天就那么大，海龟告诉它大海的广阔，它才知道自己渺小。",
              usage: "写「要开阔眼界」时用：不能做井底之蛙，要多读书多看世界。"),
        Idiom(id: 5006, category: "寓言成语", word: "狐假虎威", pinyin: "hú jiǎ hǔ wēi",
              meaning: "狐狸借老虎的威风吓唬别的动物。比喻倚仗别人的势力欺压人。",
              story: "狐狸跟在老虎身后走，百兽见了都跑，其实是怕老虎，不是怕狐狸。",
              usage: "写「借势欺人」时用：真正厉害的是背后的人，别狐假虎威。"),
        Idiom(id: 5007, category: "寓言成语", word: "滥竽充数", pinyin: "làn yú chōng shù",
              meaning: "不会吹竽的人混在乐队里充数。比喻没有真本事，混在里面凑数。",
              story: "齐宣王爱听合奏，南郭先生不会吹也混进去；后来要独奏，他只好逃走。",
              usage: "写「要有真才实学」时用：靠蒙混不行，滥竽充数迟早露馅。"),
        Idiom(id: 5008, category: "寓言成语", word: "揠苗助长", pinyin: "yà miáo zhù zhǎng",
              meaning: "把禾苗拔高帮它长。比喻违反规律、急于求成，反而坏事。",
              story: "宋人嫌禾苗长得慢，一棵棵拔高，结果禾苗全枯死了。",
              usage: "写「不能急于求成」时用：学习要循序渐进，别揠苗助长。"),

        // 历史成语
        Idiom(id: 5101, category: "历史成语", word: "负荆请罪", pinyin: "fù jīng qǐng zuì",
              meaning: "背着荆条上门请罪。表示主动向人认错赔礼，形容诚恳认错。",
              story: "廉颇不服蔺相如，后来明白他为国家大局忍让，就光着上身背荆条去请罪。",
              usage: "写「勇于认错」时用：做错事要像廉颇一样负荆请罪。"),
        Idiom(id: 5102, category: "历史成语", word: "卧薪尝胆", pinyin: "wò xīn cháng dǎn",
              meaning: "睡柴草、尝苦胆。形容人刻苦自励、发愤图强。",
              story: "越王勾践被吴国打败，卧在柴草上、每天尝苦胆提醒自己，终于复仇兴国。",
              usage: "写「刻苦自强」时用：想成功就要卧薪尝胆的毅力。"),
        Idiom(id: 5103, category: "历史成语", word: "三顾茅庐", pinyin: "sān gù máo lú",
              meaning: "三次到草庐拜访。比喻真心诚意，一再邀请有本事的人。",
              story: "刘备三次上门请诸葛亮出山，诚意打动了他，留下「三顾茅庐」的佳话。",
              usage: "写「求贤若渴、真诚」时用：老师三顾茅庐般耐心辅导我。"),
        Idiom(id: 5104, category: "历史成语", word: "四面楚歌", pinyin: "sì miàn chǔ gē",
              meaning: "四面都是楚人的歌声。比喻四面受敌、孤立无援。",
              story: "项羽被刘邦围在垓下，夜里听见四面唱楚歌，以为楚国尽失，心情绝望。",
              usage: "写「处境艰难」时用：考试前没复习，像四面楚歌。"),
        Idiom(id: 5105, category: "历史成语", word: "完璧归赵", pinyin: "wán bì guī zhào",
              meaning: "把和氏璧完好地送回赵国。比喻把原物完好无损地归还本人。",
              story: "蔺相如出使秦国，机智护住和氏璧，最终完好带回赵国。",
              usage: "写「物归原主」时用：借的东西要完璧归赵。"),

        // 描写人物
        Idiom(id: 5201, category: "描写人物", word: "一丝不苟", pinyin: "yī sī bù gǒu",
              meaning: "连最细的地方也不马虎。形容做事认真、极负责。",
              story: "出自清代小说，形容人办事连一丝一毫都不随便。",
              usage: "写「认真」的人时用：他写作业一丝不苟，字迹工整。"),
        Idiom(id: 5202, category: "描写人物", word: "聚精会神", pinyin: "jù jīng huì shén",
              meaning: "集中精神，专心致志。",
              story: "原指君臣聚集精神，后用来形容注意力高度集中。",
              usage: "写「专注」时用：同学们聚精会神地听老师讲课。"),
        Idiom(id: 5203, category: "描写人物", word: "兴高采烈", pinyin: "xìng gāo cǎi liè",
              meaning: "兴致高，精神足。形容非常高兴的样子。",
              story: "出自南朝文论，原指文章神采飞扬，今多形容人高兴。",
              usage: "写「开心」时用：我们兴高采烈地去春游。"),
        Idiom(id: 5204, category: "描写人物", word: "眉开眼笑", pinyin: "méi kāi yǎn xiào",
              meaning: "眉头舒展，眼带笑意。形容高兴愉快的神情。",
              story: "民间常用语，形容人遇到喜事时满脸笑容。",
              usage: "写「笑得很开心」时用：妈妈眉开眼笑地接过奖状。"),

        // 描写景物
        Idiom(id: 5301, category: "描写景物", word: "山清水秀", pinyin: "shān qīng shuǐ xiù",
              meaning: "山明水秀，风景优美。",
              story: "常用于描绘江南一带清丽的自然风光。",
              usage: "写「风景美」时用：我的家乡山清水秀，是个好地方。"),
        Idiom(id: 5302, category: "描写景物", word: "鸟语花香", pinyin: "niǎo yǔ huā xiāng",
              meaning: "鸟叫得好听，花开得芬芳。形容春天的美好景象。",
              story: "常见于描写春景的语句，营造生机盎然的画面。",
              usage: "写「春天」时用：公园里鸟语花香，令人心旷神怡。"),
        Idiom(id: 5303, category: "描写景物", word: "风和日丽", pinyin: "fēng hé rì lì",
              meaning: "微风柔和，阳光明丽。形容天气晴好宜人。",
              story: "多用于出游、踏青的好天气描写。",
              usage: "写「好天气」时用：风和日丽的一天，我们去爬山。"),

        // 学习态度
        Idiom(id: 5401, category: "学习态度", word: "勤能补拙", pinyin: "qín néng bǔ zhuō",
              meaning: "勤奋能够弥补笨拙。强调只要肯下功夫，就能赶上别人。",
              story: "古人劝学常用语，鼓励天资平平的人靠努力成功。",
              usage: "写「努力重要」时用：我相信勤能补拙，每天多练一点。"),
        Idiom(id: 5402, category: "学习态度", word: "笨鸟先飞", pinyin: "bèn niǎo xiān fēi",
              meaning: "笨的鸟先飞起来。比喻能力差的人，做事比别人先动手、更努力。",
              story: "关汉卿自谦之语，后成为鼓励人提前努力的俗语。",
              usage: "写「提前准备」时用：我笨鸟先飞，每天早起背单词。"),
        Idiom(id: 5403, category: "学习态度", word: "温故知新", pinyin: "wēn gù zhī xīn",
              meaning: "温习旧知识，得到新理解。指复习能让人有新收获。",
              story: "出自《论语》，孔子说「温故而知新，可以为师矣」。",
              usage: "写「复习重要」时用：每天复习，才能温故知新。"),
    ]
}

// MARK: - 列表

private struct IdiomGroup: Identifiable {
    let category: String
    let items: [Idiom]
    var id: String { category }
}

struct IdiomLibraryListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [IdiomGroup]

    init() {
        var ordered: [String] = []
        var map: [String: [Idiom]] = [:]
        for i in Idiom.all {
            if map[i.category] == nil { ordered.append(i.category) }
            map[i.category, default: []].append(i)
        }
        groups = ordered.map { IdiomGroup(category: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "成语解释",
                actions: AnyView(
                    IosTextButton(text: "去语文问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.category)
                        ForEach(group.items) { i in
                            IdiomRow(idiom: i) { router.push(.idiomDetail(i.id)) }
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

private struct IdiomRow: View {
    let idiom: Idiom
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(idiom.word)
                        .font(HyperType.titleMedium)
                        .foregroundStyle(palette.text)
                    Text(idiom.pinyin)
                        .font(HyperType.footnote)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                Text(idiom.meaning)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(idiom.category)
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

struct IdiomDetailView: View {
    let idiom: Idiom
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .center, spacing: 6) {
                    Text(idiom.word)
                        .font(HyperType.title2)
                        .foregroundStyle(palette.text)
                    Text(idiom.pinyin)
                        .font(HyperType.bodyMedium)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                meaningBlock
                storyBlock
                usageBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "成语练笔：\(idiom.word)",
                        outline: idiom.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这个成语去写")
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
        .navigationTitle(idiom.word)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var meaningBlock: some View {
        block(title: "释义", text: idiom.meaning)
    }
    private var storyBlock: some View {
        block(title: "小故事 / 出处", text: idiom.story)
    }
    private var usageBlock: some View {
        block(title: "怎么用 · 造句", text: idiom.usage)
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
