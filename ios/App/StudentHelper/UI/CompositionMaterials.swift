import SwiftUI
import SHCore

/// 好词好句 / 写作素材库：与作文模板库互补的离线参考资料。
/// 模板库给「结构框架」，素材库给「可以直接化用进作文的句子与用法」——
/// 比如一个精彩开头、一个比喻句、一句名言。学生浏览后点「用素材去写」，
/// 把句子与用法提示带进「新建批改」的要求栏，照着练笔即可。
/// 同样完全离线、不依赖网络，CI 截图走确定性路径。

// MARK: - 数据模型

struct WritingMaterial: Identifiable, Hashable {
    let id: Int
    let category: String
    let title: String
    let phrase: String
    let usage: String

    /// 拼成一段预填文字，作为「新建批改」的题目要求，引导学生把这句素材用进作文。
    var prompt: String {
        """
        【写作素材：\(title)】
        可化用的句子：
        \(phrase)

        怎么用：
        \(usage)
        """
    }
}

extension WritingMaterial {
    /// 固定示例库。全部离线，不依赖网络，CI 截图也走同一条确定性路径。
    static let all: [WritingMaterial] = [
        // 精彩开头
        WritingMaterial(id: 1001, category: "精彩开头", title: "比喻式开头", phrase: "书是人类进步的阶梯，而我的妈妈，就是那扶着我一级一级往上走的双手。", usage: "用「把 A 比作 B」开头，先点明要写的人或物，再自然带出情感。适合写人、写书、写习惯。"),
        WritingMaterial(id: 1002, category: "精彩开头", title: "设问式开头", phrase: "什么是幸福？对六岁的我来说，幸福就是外婆灶台上那碗冒着热气的红糖水。", usage: "用「什么是……？」自问自答，先把读者问住，再给出只属于你的答案。适合写亲情、写感受。"),
        WritingMaterial(id: 1003, category: "精彩开头", title: "写景入题", phrase: "春风一吹，校园里的樱花就醒了，粉粉白白落了一地，我们的春游也就在这时候开始了。", usage: "先用一句景物把场景立起来，再顺手引出要写的事。适合写事、写活动。"),
        WritingMaterial(id: 1004, category: "精彩开头", title: "直抒胸臆", phrase: "那件事过去很久了，可只要一闭眼，当时的羞愧就又红着脸站在我面前。", usage: "一上来就说出感受，制造悬念，让读者想知道「那件事」到底是什么。适合写事、写感悟。"),

        // 韵味结尾
        WritingMaterial(id: 1101, category: "韵味结尾", title: "点题升华", phrase: "原来，成长不是一下子长高，而是学会在摔倒后，自己拍拍灰站起来。", usage: "结尾把一件小事往上提一层，点出它教会你的道理。适合写事、写成长。"),
        WritingMaterial(id: 1102, category: "韵味结尾", title: "呼应开头", phrase: "如今我早已比妈妈高了，可那双扶我上阶梯的手，我一辈子都忘不了。", usage: "结尾回到开头写过的人和物，首尾扣住，文章更完整。适合写人。"),
        WritingMaterial(id: 1103, category: "韵味结尾", title: "留白余味", phrase: "雪还在下，脚印一小串一小串地延伸向远方，像一串没说完的话。", usage: "不把话说满，用一处景物收尾，让读者自己回味。适合写景、写事。"),
        WritingMaterial(id: 1104, category: "韵味结尾", title: "名言收束", phrase: "正如高尔基所说：「书籍是人类进步的阶梯。」这一年，我确确实实踩着它往上走了几级。", usage: "用一句名言替你总结，既显积累，又让结尾有分量。适合写读书、写收获。"),

        // 写景
        WritingMaterial(id: 1201, category: "写景", title: "写春天", phrase: "小草悄悄从土里探出头，嫩得仿佛能掐出水来；柳枝随风摇摆，像姑娘长长的辫子。", usage: "写春用「探、冒、摇」这类动词，再加一个比喻，画面就活了。适合写季节、写公园。"),
        WritingMaterial(id: 1202, category: "写景", title: "写夏天", phrase: "蝉在树上扯着嗓子喊热，池塘里的荷花却静静开着，粉瓣上停着一只蜻蜓，一动不动。", usage: "用「动中有静」的对比写夏：热闹的蝉声衬出荷花的安静。适合写夏日、写池塘。"),
        WritingMaterial(id: 1203, category: "写景", title: "写秋天", phrase: "秋风一掠，银杏叶像一把把小扇子，扇走了夏天的燥，扇来了满地金黄。", usage: "写秋抓住「颜色 + 动作」，把风写成会扇扇子的手。适合写秋天、写落叶。"),
        WritingMaterial(id: 1204, category: "写景", title: "写冬天", phrase: "雪花像撒落的盐，又像空中开出的白花，悄悄地给屋顶盖上一层厚厚的棉被。", usage: "写冬用叠词和比喻（盐、白花、棉被），写出雪的轻与厚。适合写雪、写冬日。"),

        // 写人
        WritingMaterial(id: 1301, category: "写人", title: "写外貌抓特点", phrase: "爷爷的脸上刻着一道道深深的皱纹，像风吹过湖面留下的波纹，可那双眼睛笑起来，还是亮亮的。", usage: "外貌别从头写到脚，只写最特别的一两处，再让眼睛「亮」起来，人物就精神了。适合写长辈。"),
        WritingMaterial(id: 1302, category: "写人", title: "用动作写性格", phrase: "妈妈端起碗，先吹了吹，再轻轻递到我手里，自己却端起那碗凉了的。", usage: "不写「妈妈很爱我」，改用一连串小动作把爱写出来，更打动人。适合写亲人。"),
        WritingMaterial(id: 1303, category: "写人", title: "写神态", phrase: "他低着头，手指不停地绞着衣角，脸涨得通红，半天憋出一句「对不起」。", usage: "用「绞衣角、脸涨红」写紧张或羞愧，比直接说「他很紧张」更有画面。适合写同学、写小事。"),

        // 写物
        WritingMaterial(id: 1401, category: "写物", title: "写小动物", phrase: "小猫那双绿莹莹的眼睛，夜里像两盏小灯笼；它一高兴，尾巴就翘成一根问号。", usage: "写动物抓眼神和尾巴这类「会说话」的部位，再配个比喻，活灵活现。适合写猫、狗、兔。"),
        WritingMaterial(id: 1402, category: "写物", title: "写植物", phrase: "仙人掌浑身是刺，却能在最干的地方开出一朵嫩黄的花，倔强得让人心疼。", usage: "写植物可写它「不好看却坚强」的反差，托出品格。适合写盆栽、写梅花。"),
        WritingMaterial(id: 1403, category: "写物", title: "写心爱之物", phrase: "这只旧文具盒的边角磨得发白，可每次打开，都像打开一段小小的童年。", usage: "写物要写出「情」：旧没关系，重要的是它陪你走过的日子。适合写玩具、写礼物。"),

        // 修辞手法
        WritingMaterial(id: 1501, category: "修辞手法", title: "比喻", phrase: "时间像海绵里的水，只要愿挤，总还是有的。", usage: "比喻要找「大家都懂」的相似点，把抽象（时间）写具体。适合写感悟、写道理。"),
        WritingMaterial(id: 1502, category: "修辞手法", title: "拟人", phrase: "夜空中的星星调皮地眨着眼睛，悄悄把我的心事记在了本子上。", usage: "把物当人写（眨眼睛、记心事），文章立刻有了童趣。适合写夜、写想象。"),
        WritingMaterial(id: 1503, category: "修辞手法", title: "排比", phrase: "书是饥饿时的面包，是寒冷时的炭火，是迷路时的那盏灯。", usage: "用三个结构相近的句子铺排，语气更有力、更整齐。适合写读书、写感恩。"),
        WritingMaterial(id: 1504, category: "修辞手法", title: "夸张", phrase: "我紧张得心都快从嗓子眼跳出来，连空气都凝固了。", usage: "适度夸张把感受放大，让读者瞬间体会到你的心情。适合写紧张、写激动。"),

        // 心理与情感
        WritingMaterial(id: 1601, category: "心理情感", title: "写期待", phrase: "那一晚，我翻来覆去怎么也睡不着，心像揣了只小兔子，咚咚地跳个不停。", usage: "用「小兔子乱跳」写期待或紧张，把看不见的心情写听见。适合写等待、写考前。"),
        WritingMaterial(id: 1602, category: "心理情感", title: "写愧疚", phrase: "看着她 silently 转身的背影，我的鼻子一酸，那句「对不起」卡在喉咙里，怎么也吐不出来。", usage: "写愧疚写「想说却说不出口」的瞬间，比直接道歉更揪心。适合写误会、写犯错。"),
        WritingMaterial(id: 1603, category: "心理情感", title: "写喜悦", phrase: "听见名字的那一刻，我差点跳起来，阳光仿佛一下子洒进了整个教室。", usage: "喜悦要写「身体反应 + 环境跟着亮」，快乐才传染得开。适合写获奖、写好消息。"),

        // 名言俗语积累
        WritingMaterial(id: 1701, category: "名言俗语", title: "勤奋", phrase: "业精于勤，荒于嬉。——韩愈", usage: "写「努力学习」「不怕吃苦」时引用，给文章添一份分量。可接着写：我也要把这句话贴在书桌前。"),
        WritingMaterial(id: 1702, category: "名言俗语", title: "读书", phrase: "读书破万卷，下笔如有神。——杜甫", usage: "写读书好处、写自己爱看书时引用，自然引出「多读才能写好」。"),
        WritingMaterial(id: 1703, category: "名言俗语", title: "坚持", phrase: "世上无难事，只怕有心人。", usage: "写学本领、克服困难的结尾引用，点明「坚持就能成功」。"),
        WritingMaterial(id: 1704, category: "名言俗语", title: "团结", phrase: "人心齐，泰山移。", usage: "写一次合作、一次集体活动时用，说明「大家一起努力力量大」。"),
        WritingMaterial(id: 1705, category: "名言俗语", title: "母爱", phrase: "谁言寸草心，报得三春晖。——孟郊", usage: "写妈妈、写亲情结尾引用，把对母爱的感激轻轻收住。"),
    ]
}

// MARK: - 列表

private struct MaterialGroup: Identifiable {
    let category: String
    let items: [WritingMaterial]
    var id: String { category }
}

struct CompositionMaterialsListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [MaterialGroup]

    init() {
        var ordered: [String] = []
        var map: [String: [WritingMaterial]] = [:]
        for m in WritingMaterial.all {
            if map[m.category] == nil { ordered.append(m.category) }
            map[m.category, default: []].append(m)
        }
        groups = ordered.map { MaterialGroup(category: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "好词好句",
                actions: AnyView(
                    IosTextButton(text: "新建批改") { router.push(.compositionNew) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.category)
                        ForEach(group.items) { m in
                            MaterialRow(material: m) { router.push(.materialDetail(m.id)) }
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
                .fill(Hyper.composition)
                .frame(width: 3, height: 16)
            Text(title)
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Spacer()
        }
        .padding(.horizontal, 14)
    }
}

private struct MaterialRow: View {
    let material: WritingMaterial
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(material.title)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Text(material.phrase)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(material.category)
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.composition)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Hyper.composition.opacity(0.12)))
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

struct CompositionMaterialDetailView: View {
    let material: WritingMaterial
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text(material.category)
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.composition)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Hyper.composition.opacity(0.12)))
                    Spacer()
                }
                .padding(.horizontal, 14)

                phraseBlock
                usageBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "用素材练笔：\(material.title)",
                        outline: material.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用素材去写")
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
        .navigationTitle(material.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var phraseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("好词好句")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(material.phrase)
                .font(HyperType.body)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }

    private var usageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么用")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(material.usage)
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
