import SwiftUI
import SHCore

/// 必背古诗词库：离线参考资料，放在「语文」页。
/// 与作文模板库 / 好词好句库同模式——纯静态、不联网、CI 截图走确定性路径。
/// 古诗是小学「日积月累」的硬通货：学生浏览、背诵，点「用这首诗练笔」
/// 把诗句带进「新建批改」要求栏，练「把古诗化用到作文里」。

// MARK: - 数据模型

struct Poem: Identifiable, Hashable {
    let id: Int
    let title: String
    let dynasty: String
    let author: String
    let lines: [String]
    /// 一句话赏析 / 背诵提示 / 怎么化用进作文。
    let note: String

    /// 拼成预填文字，作为「新建批改」的题目要求：练把古诗写进作文。
    var prompt: String {
        let body = lines.joined(separator: "\n")
        return """
        【古诗练笔：\(title)】
        \(dynasty)·\(author)
        \(body)

        化用提示：
        \(note)
        """
    }
}

extension Poem {
    /// 固定示例库。全部离线，不依赖网络，CI 截图也走同一条确定性路径。
    static let all: [Poem] = [
        Poem(id: 2001, title: "咏鹅", dynasty: "唐", author: "骆宾王",
             lines: ["鹅，鹅，鹅，", "曲项向天歌。", "白毛浮绿水，", "红掌拨清波。"],
             note: "七岁写的诗。写动物抓住颜色（白毛/绿水/红掌）和动作（浮/拨），画面一下就活了。写小动物时可以学这种「颜色+动作」。"),
        Poem(id: 2002, title: "静夜思", dynasty: "唐", author: "李白",
             lines: ["床前明月光，", "疑是地上霜。", "举头望明月，", "低头思故乡。"],
             note: "最能写「想家」的诗。由「看月光」到「想故乡」，动作很小，思念很深。写思念、写夜晚可用。"),
        Poem(id: 2003, title: "春晓", dynasty: "唐", author: "孟浩然",
             lines: ["春眠不觉晓，", "处处闻啼鸟。", "夜来风雨声，", "花落知多少。"],
             note: "写春天从「声音」入手：鸟叫、风雨声。结尾问「花落知多少」，把惜春写得很轻。写春可引用。"),
        Poem(id: 2004, title: "登鹳雀楼", dynasty: "唐", author: "王之涣",
             lines: ["白日依山尽，", "黄河入海流。", "欲穷千里目，", "更上一层楼。"],
             note: "后两句是千古名句：想看得更远，就要再上一层楼。写「努力/进步/志向」时引用最合适。"),
        Poem(id: 2005, title: "悯农", dynasty: "唐", author: "李绅",
             lines: ["锄禾日当午，", "汗滴禾下土。", "谁知盘中餐，", "粒粒皆辛苦。"],
             note: "写农民辛苦、写「爱惜粮食」最常用。前两句写烈日下劳作，后两句点题，对比强烈。"),
        Poem(id: 2006, title: "古朗月行（节选）", dynasty: "唐", author: "李白",
             lines: ["小时不识月，", "呼作白玉盘。", "又疑瑶台镜，", "飞在青云端。"],
             note: "把月亮比作「白玉盘」「瑶台镜」，是写月亮的经典比喻。写夜、写月可化用。"),
        Poem(id: 2007, title: "绝句", dynasty: "唐", author: "杜甫",
             lines: ["两个黄鹂鸣翠柳，", "一行白鹭上青天。", "窗含西岭千秋雪，", "门泊东吴万里船。"],
             note: "四句四个颜色（黄/翠/白/青），像四幅小画。写春天、写景物可以学这种「色彩搭配」。"),
        Poem(id: 2008, title: "江雪", dynasty: "唐", author: "柳宗元",
             lines: ["千山鸟飞绝，", "万径人踪灭。", "孤舟蓑笠翁，", "独钓寒江雪。"],
             note: "用「绝/灭」写雪天的安静，再用一个独自钓鱼的老翁点出孤傲。写冬、写雪、写孤独可用。"),
        Poem(id: 2009, title: "池上", dynasty: "唐", author: "白居易",
             lines: ["小娃撑小艇，", "偷采白莲回。", "不解藏踪迹，", "浮萍一道开。"],
             note: "写小孩偷采莲的天真，最后「浮萍一道开」把藏不住的小秘密写得很可爱。写童年趣事可用。"),
        Poem(id: 2010, title: "小池", dynasty: "宋", author: "杨万里",
             lines: ["泉眼无声惜细流，", "树阴照水爱晴柔。", "小荷才露尖尖角，", "早有蜻蜓立上头。"],
             note: "「小荷才露尖尖角」常用来比喻「刚露头的好苗子」。写初夏、写新生事物可引用。"),
        Poem(id: 2011, title: "晓出净慈寺送林子方", dynasty: "宋", author: "杨万里",
             lines: ["毕竟西湖六月中，", "风光不与四时同。", "接天莲叶无穷碧，", "映日荷花别样红。"],
             note: "写夏荷的名句。「碧」与「红」对照，写出荷塘的壮美。写夏、写西湖可化用。"),
        Poem(id: 2012, title: "村居", dynasty: "清", author: "高鼎",
             lines: ["草长莺飞二月天，", "拂堤杨柳醉春烟。", "儿童散学归来早，", "忙趁东风放纸鸢。"],
             note: "写春天放风筝的快乐，把「杨柳醉春烟」拟人化，很有童趣。写春、写放学时光可用。"),
        Poem(id: 2013, title: "赋得古原草送别（节选）", dynasty: "唐", author: "白居易",
             lines: ["离离原上草，", "一岁一枯荣。", "野火烧不尽，", "春风吹又生。"],
             note: "「野火烧不尽，春风吹又生」写生命力，比喻「打不倒、重新站起来」。写坚强、写希望可引用。"),
        Poem(id: 2014, title: "望庐山瀑布", dynasty: "唐", author: "李白",
             lines: ["日照香炉生紫烟，", "遥看瀑布挂前川。", "飞流直下三千尺，", "疑是银河落九天。"],
             note: "用夸张（三千尺、落九天）写瀑布的气势。写山、写水、写壮观景色可化用。"),
        Poem(id: 2015, title: "九月九日忆山东兄弟", dynasty: "唐", author: "王维",
             lines: ["独在异乡为异客，", "每逢佳节倍思亲。", "遥知兄弟登高处，", "遍插茱萸少一人。"],
             note: "「每逢佳节倍思亲」是写思乡思亲的万能句。写节日、写想家必引。"),
        Poem(id: 2016, title: "游子吟", dynasty: "唐", author: "孟郊",
             lines: ["慈母手中线，", "游子身上衣。", "临行密密缝，", "意恐迟迟归。"],
             note: "写母爱的经典。「密密缝」这个小动作，把妈妈的担心写透了。写妈妈、写亲情可用（也常作素材库名言）。"),
        Poem(id: 2017, title: "忆江南", dynasty: "唐", author: "白居易",
             lines: ["江南好，", "风景旧曾谙。", "日出江花红胜火，", "春来江水绿如蓝。"],
             note: "词的开头。「红胜火」「绿如蓝」用对比写江南的明丽。写江南、写春可化用。"),
        Poem(id: 2018, title: "敕勒歌", dynasty: "北朝", author: "民歌",
             lines: ["敕勒川，阴山下。", "天似穹庐，笼盖四野。", "天苍苍，野茫茫，", "风吹草低见牛羊。"],
             note: "北朝民歌，写草原的辽阔。「天似穹庐」把天比作帐篷，很形象。写草原、写风光可用。"),
        Poem(id: 2019, title: "所见", dynasty: "清", author: "袁枚",
             lines: ["牧童骑黄牛，", "歌声振林樾。", "意欲捕鸣蝉，", "忽然闭口立。"],
             note: "写牧童从「大声唱歌」到「突然闭嘴」想抓蝉，动静之间童趣十足。写童年、写夏天可用。"),
        Poem(id: 2020, title: "小儿垂钓", dynasty: "唐", author: "胡令能",
             lines: ["蓬头稚子学垂纶，", "侧坐莓苔草映身。", "路人借问遥招手，", "怕得鱼惊不应人。"],
             note: "写小孩钓鱼怕惊跑鱼，路人间路只「遥招手」不说话，小心翼翼的样子很生动。写童年趣事可用。"),
    ]
}

// MARK: - 列表

private struct PoemGroup: Identifiable {
    let dynasty: String
    let items: [Poem]
    var id: String { dynasty }
}

struct PoetryLibraryListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [PoemGroup]

    init() {
        var ordered: [String] = []
        var map: [String: [Poem]] = [:]
        for p in Poem.all {
            if map[p.dynasty] == nil { ordered.append(p.dynasty) }
            map[p.dynasty, default: []].append(p)
        }
        groups = ordered.map { PoemGroup(dynasty: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "必背古诗词",
                actions: AnyView(
                    IosTextButton(text: "去语文问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.dynasty)
                        ForEach(group.items) { p in
                            PoemRow(poem: p) { router.push(.poemDetail(p.id)) }
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

private struct PoemRow: View {
    let poem: Poem
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(poem.title)
                        .font(HyperType.titleMedium)
                        .foregroundStyle(palette.text)
                    Text("\(poem.dynasty)·\(poem.author)")
                        .font(HyperType.footnote)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                Text(poem.lines.prefix(2).joined(separator: ""))
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("古诗")
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

struct PoemDetailView: View {
    let poem: Poem
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .center, spacing: 6) {
                    Text(poem.title)
                        .font(HyperType.title2)
                        .foregroundStyle(palette.text)
                    Text("\(poem.dynasty)·\(poem.author)")
                        .font(HyperType.bodyMedium)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                poemBlock

                noteBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "用古诗练笔：\(poem.title)",
                        outline: poem.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这首诗练笔")
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
        .navigationTitle(poem.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var poemBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(poem.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("赏析 · 怎么化用")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(poem.note)
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
