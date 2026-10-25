import SwiftUI
import SHCore

/// 作文模板库：完全离线、与网络批改无关的参考资料。
/// 六年级学生写作前可浏览「结构框架 + 参考片段」，点「用模板去写」直接把框架带入「新建批改」的要求栏。
/// 区别于「生成作文」（联网调用大模型），这里是固定、可反复看的写作支架，适合没网或想先打草稿的场景。

// MARK: - 数据模型

struct CompositionTemplate: Identifiable, Hashable {
    let id: Int
    let title: String
    let category: String
    let summary: String
    let structure: [TemplateSection]
    let tips: [String]
    let sample: String

    var tags: [String] { [category] }

    /// 把框架拼成一段文字，作为「新建批改」的题目要求预填，学生照着填空即可。
    var outline: String {
        var s = "【\(title)】写作框架：\n"
        for (i, sec) in structure.enumerated() {
            s += "\(number(i))\(sec.title)：\n"
            for p in sec.points { s += "  · \(p)\n" }
        }
        if !tips.isEmpty {
            s += "小提示：\n"
            for t in tips { s += "  · \(t)\n" }
        }
        return s
    }

    private func number(_ i: Int) -> String {
        ["一、", "二、", "三、", "四、", "五、"][i % 5]
    }
}

struct TemplateSection: Hashable {
    let title: String
    let points: [String]
}

extension CompositionTemplate {
    /// 固定示例库。全部离线，不依赖网络，CI 截图也走同一条确定性路径。
    static let all: [CompositionTemplate] = [
        CompositionTemplate(
            id: 101,
            title: "我的家人",
            category: "写人",
            summary: "抓住一个家人的外貌特点和一件小事，写出他/她的样子。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "一句话点明要写谁（如妈妈、爷爷）。",
                    "用一句印象词说出他/她给你的整体感觉。",
                ]),
                TemplateSection(title: "中间", points: [
                    "选一件具体的小事（做饭、陪你写作业、接你放学）。",
                    "用动作和语言写出特点，别只说‘他很爱我’。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "写出你对家人的感情，或他/她对你的影响。",
                ]),
            ],
            tips: [
                "不要从头到脚罗列外貌，只写最特别的一两点。",
                "用一件真实的小事代替空泛的夸奖。",
            ],
            sample: "我的妈妈有一双总也闲不住的手。清晨，这双手在厨房里变出热腾腾的早餐；夜晚，这双手又轻轻替我掖好被角。看着那双有些粗糙的手，我心里暖暖的。"
        ),
        CompositionTemplate(
            id: 102,
            title: "一个印象深刻的人",
            category: "写人",
            summary: "写一个陌生人或不常见面的人，突出他/她身上的某种品质。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "在什么时间、什么地点遇到了这个人。",
                ]),
                TemplateSection(title: "中间", points: [
                    "通过他/她做的事、说的话，写出令你印象深的品质（诚实、热心）。",
                    "可以写一个小小的波折，让人物更真实。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "这件事给你留下了什么想法或改变。",
                ]),
            ],
            tips: [
                "选一件能体现品质的事，而不是泛泛说他好。",
                "写写周围人的反应，衬托更有力。",
            ],
            sample: "暴雨天，校门口的保安叔叔把伞塞给我，自己淋着雨指挥交通。那一刻，他湿透的背影让我明白了什么叫‘认真负责’。"
        ),
        CompositionTemplate(
            id: 201,
            title: "一件难忘的事",
            category: "写事",
            summary: "按事情发展顺序，写清起因、经过、结果，写出真实感受。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "一句话引出这件事，点明时间和地点。",
                ]),
                TemplateSection(title: "中间", points: [
                    "把经过写具体：先发生什么、再发生什么，加上自己的心情。",
                    "把‘最紧张/最开心’的一刻写细，别平均用力。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "这件事让你明白了什么，或至今难忘的原因。",
                ]),
            ],
            tips: [
                "适当写写心里想法，文章更有温度。",
                "用‘突然、终于、没想到’等词制造小起伏。",
            ],
            sample: "第一次独自坐公交去奶奶家，我在站台心跳得飞快。当车厢门合上的那一刻，我攥紧月票对自己说：‘我能行。’下车见到奶奶，我骄傲极了。"
        ),
        CompositionTemplate(
            id: 202,
            title: "一次____活动",
            category: "写事",
            summary: "写一次比赛、旅行或集体活动，写出过程和收获。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "活动是什么、你为什么参加。",
                ]),
                TemplateSection(title: "中间", points: [
                    "按时间写准备、进行、高潮（冲过终点、登顶）。",
                    "写现场的声音、画面和你当时的心情。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "活动带给你的收获或一个道理。",
                ]),
            ],
            tips: [
                "用‘先……接着……最后……’把过程串顺。",
                "写一句当时的口号或加油声，现场感更强。",
            ],
            sample: "运动会接力赛，我接过棒那一刻，耳边全是‘加油’。脚像生了风，风在耳边呼呼响。冲线后我们抱在一起——原来团结真的能让人变快。"
        ),
        CompositionTemplate(
            id: 301,
            title: "美丽的____",
            category: "写景",
            summary: "按一定顺序观察一处景物，写出它的样子和你的喜爱。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "要写哪里的景色，整体给你什么感觉。",
                ]),
                TemplateSection(title: "中间", points: [
                    "按方位或时间顺序（远到近、早到晚）写出颜色、形状、声音。",
                    "调动五官：看颜色、听声音、闻气味。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "写出你对这处景色的感情。",
                ]),
            ],
            tips: [
                "用比喻把景物写活，如‘湖面像撒了一把碎银’。",
                "别堆形容词，写出一样最打动你的景物就够。",
            ],
            sample: "傍晚的公园，夕阳把河水染成橘红色。柳枝垂在水面，像姑娘在梳头。几只归鸟掠过，留下一串清脆的鸣叫。我舍不得离开这安静的画。"
        ),
        CompositionTemplate(
            id: 302,
            title: "四季中的____",
            category: "写景",
            summary: "写某个季节的特点，或一个地方在四季里的变化。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "你写的是哪个季节（或哪个地方）。",
                ]),
                TemplateSection(title: "中间", points: [
                    "写出这个季节特有的景物、天气和活动（春雨、蝉鸣、落叶、雪花）。",
                    "写写人在季节里的活动，更有生活味。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "你最喜欢它的哪一点。",
                ]),
            ],
            tips: [
                "抓住季节‘独有’的景物，别写成放之四海皆准的话。",
                "用一个季节里的小发现开头更亲切。",
            ],
            sample: "秋天是丰收的季节。稻田翻着金浪，苹果羞红了脸。大人们忙着收割，我们在田埂上捡稻穗，空气里都是阳光和泥土的香味。"
        ),
        CompositionTemplate(
            id: 401,
            title: "我爱____（动物/植物/物品）",
            category: "写物",
            summary: "介绍一样你熟悉的东西，写出它的样子和你的感情。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "要写的是什么，你为什么喜欢它。",
                ]),
                TemplateSection(title: "中间", points: [
                    "写出它的外形、习性/用途，选一两个有趣的细节。",
                    "写物也要写‘事’，如和小狗的一次玩耍。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "它给你带来了什么快乐或启发。",
                ]),
            ],
            tips: [
                "用‘先整体后部分’介绍外形更清楚。",
                "写写它调皮或可爱的瞬间，文章更生动。",
            ],
            sample: "我家的小猫雪球，浑身白毛像一团棉花。它最爱追自己的尾巴，转着转着就摔个跟头，逗得全家哈哈大笑。有它在，家里从不冷清。"
        ),
        CompositionTemplate(
            id: 501,
            title: "假如我____",
            category: "想象",
            summary: "展开合理想象，写一个虚构但有趣的故事。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "假如你变成了什么、拥有了什么能力。",
                ]),
                TemplateSection(title: "中间", points: [
                    "你用这个能力做了哪几件有意思（或有意义）的事。",
                    "让故事有个小转折，别平铺直叙。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "想象结束，回到现实或写出愿望。",
                ]),
            ],
            tips: [
                "想象要‘有根’，从现实出发再夸张。",
                "想象也要有感情，不只是炫技。",
            ],
            sample: "假如我有一双翅膀，我要飞到山顶看日出，把第一缕阳光送给生病的同学。飞过田野时，我听见麦苗在风里悄悄长大。"
        ),
        CompositionTemplate(
            id: 502,
            title: "二十年后的家乡",
            category: "想象",
            summary: "畅想家乡未来的变化，表达对家乡的爱。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "你坐上‘时光机’回到二十年后的家乡。",
                ]),
                TemplateSection(title: "中间", points: [
                    "写环境、交通、学校或家的变化，选两三个画面。",
                    "别忘了写人的变化，让想象有温度。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "你希望这些变化成真的心情。",
                ]),
            ],
            tips: [
                "变化要‘合理先进’，如空中绿道、智能书包。",
                "对比现在和将来，差别更明显。",
            ],
            sample: "二十年后的家乡，河更清了，空中绿道连着每栋楼。我小时候的母校装上了太阳能屋顶，孩子们在花园里上课。家乡，真的越来越好。"
        ),
        CompositionTemplate(
            id: 601,
            title: "给____的一封信",
            category: "应用文",
            summary: "用书信格式，向亲友或远方的人说说心里话。",
            structure: [
                TemplateSection(title: "称呼与问候", points: [
                    "顶格写‘亲爱的××’，换行空两格问好。",
                ]),
                TemplateSection(title: "正文", points: [
                    "写一件你最想告诉对方的事，或表达感谢/思念。",
                    "语气像当面说话，自然真诚。",
                ]),
                TemplateSection(title: "祝福与落款", points: [
                    "写‘祝……’，右下角写名字和日期。",
                ]),
            ],
            tips: [
                "书信有固定格式，称呼、祝语、落款别漏。",
                "写一件具体小事，比‘我很想你’更动人。",
            ],
            sample: "亲爱的爸爸：您在外地工作辛苦了。上次您视频里教我修自行车，我终于学会了。等我学会骑远一点，就能帮妈妈去买菜啦。您要注意身体！"
        ),
        CompositionTemplate(
            id: 602,
            title: "读后感/观后感",
            category: "应用文",
            summary: "读完一本书或看完一部影片，写出你的收获。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "读了什么、总体感觉怎样。",
                ]),
                TemplateSection(title: "中间", points: [
                    "选一个最打动你的情节或人物，结合自己谈体会。",
                    "‘感’比‘述’重要，少抄内容多写想法。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "这本书/影片让你明白了什么。",
                ]),
            ],
            tips: [
                "联系自己的生活，文章更真实。",
                "用‘不由得想到’把书和自身体验连起来。",
            ],
            sample: "读完《小王子》，我最记得那句‘真正重要的东西，用眼睛是看不见的’。想到妈妈每天默默为我做的事，我才懂得，爱藏在看不见的细节里。"
        ),
        CompositionTemplate(
            id: 701,
            title: "谈谈____（一种事物或一个道理）",
            category: "说明/议论",
            summary: "清楚地介绍一种事物，或说明一个简单的道理。",
            structure: [
                TemplateSection(title: "开头", points: [
                    "你要介绍/说明的是什么。",
                ]),
                TemplateSection(title: "中间", points: [
                    "分几点写清特点、原因或做法。",
                    "道理要配上小例子，别只喊口号。",
                ]),
                TemplateSection(title: "结尾", points: [
                    "总结你的看法，发出一个小倡议。",
                ]),
            ],
            tips: [
                "一条一条说清楚，用‘首先、其次、最后’。",
                "举一个自己经历的小例子，更有说服力。",
            ],
            sample: "为什么说‘失败是成功之母’？首先，失败能告诉我们哪条路走不通；其次，从错误里能学到经验；最后，坚持改正就会离成功更近。每一次摔跤，都是在学习走路。"
        ),
    ]
}

// MARK: - 列表

private struct TemplateGroup: Identifiable {
    let category: String
    let items: [CompositionTemplate]
    var id: String { category }
}

struct CompositionTemplateListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [TemplateGroup]

    init() {
        var ordered: [String] = []
        var map: [String: [CompositionTemplate]] = [:]
        for t in CompositionTemplate.all {
            if map[t.category] == nil { ordered.append(t.category) }
            map[t.category, default: []].append(t)
        }
        groups = ordered.map { TemplateGroup(category: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "作文模板库",
                actions: AnyView(
                    IosTextButton(text: "新建批改") { router.push(.compositionNew) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.category)
                        ForEach(group.items) { t in
                            TemplateRow(template: t) { router.push(.templateDetail(t.id)) }
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

private struct TemplateRow: View {
    let template: CompositionTemplate
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(template.title)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Text(template.summary)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(template.category)
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

struct CompositionTemplateDetailView: View {
    let template: CompositionTemplate
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(template.title)
                    .font(HyperType.largeTitle)
                    .foregroundStyle(palette.text)
                Text(template.summary)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)

                ForEach(template.structure, id: \.title) { section in
                    structureBlock(section)
                }

                if !template.tips.isEmpty {
                    tipBlock
                }

                sampleBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: template.title, outline: template.outline
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                        Text("用这个模板去写作文")
                            .font(HyperType.titleMedium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Hyper.miBlue))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle("模板详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func structureBlock(_ section: TemplateSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            ForEach(section.points, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .foregroundStyle(Hyper.composition)
                    Text(point)
                        .font(HyperType.bodyMedium)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    private var tipBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("小提示")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            ForEach(template.tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 13))
                        .foregroundStyle(Hyper.miOrange)
                    Text(tip)
                        .font(HyperType.bodyMedium)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    private var sampleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("参考范文片段")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(template.sample)
                .font(HyperType.body)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
    }
}
