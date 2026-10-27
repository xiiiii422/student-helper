import SwiftUI
import SHCore

/// 数学公式 / 单位换算速查：离线参考资料，放在「数学」页。
/// 与作文模板库 / 好词好句库 / 古诗词库同模式——纯静态、不联网、CI 截图走确定性路径。
/// 把小学最常用、最容易记混的图形公式、单位换算、运算律集中成一本随身速查，
/// 学生考前翻一翻，点「用这条去练」把题目带进「新建批改」要求栏。

// MARK: - 数据模型

struct MathFormula: Identifiable, Hashable {
    let id: Int
    let category: String
    let title: String
    /// 公式本体（可直接抄进作业/试卷的那串式子）。
    let formula: String
    /// 什么时候用、怎么套、易错点。
    let note: String

    /// 拼成预填文字，作为「新建批改」的题目要求：练这条公式的套用。
    var prompt: String {
        """
        【公式练笔：\(title)】
        公式：
        \(formula)

        用法提示：
        \(note)
        """
    }
}

extension MathFormula {
    /// 固定示例库。全部离线，不依赖网络，CI 截图也走同一条确定性路径。
    static let all: [MathFormula] = [
        // 图形 · 周长与面积
        MathFormula(id: 3001, category: "图形公式", title: "长方形", formula: "周长 = (长 + 宽) × 2\n面积 = 长 × 宽", note: "已知长和宽求围栏用周长，求铺地用面积。别把「周长」和「面积」混着算，单位也不同（周长用长度单位，面积用平方单位）。"),
        MathFormula(id: 3002, category: "图形公式", title: "正方形", formula: "周长 = 边长 × 4\n面积 = 边长 × 边长", note: "四条边都相等，所以周长直接乘 4。面积是边长自己乘自己，不是乘 4。"),
        MathFormula(id: 3003, category: "图形公式", title: "平行四边形", formula: "面积 = 底 × 高", note: "高是「垂直」的那段，不是斜边的长。沿高剪开能拼成长方形，所以等于底×高。"),
        MathFormula(id: 3004, category: "图形公式", title: "三角形", formula: "面积 = 底 × 高 ÷ 2", note: "两个完全一样的三角形能拼成一个平行四边形，所以是「底×高」再除以 2。除以 2 最容易被忘。"),
        MathFormula(id: 3005, category: "图形公式", title: "梯形", formula: "面积 = (上底 + 下底) × 高 ÷ 2", note: "上下底不一样长，先加起来除以 2 求平均底，再乘高。"),
        MathFormula(id: 3006, category: "图形公式", title: "圆", formula: "周长 = πd = 2πr\n面积 = πr²", note: "π 一般取 3.14。周长用直径或半径都行；面积里 r 要平方，别写成 2πr。"),

        // 图形 · 立体
        MathFormula(id: 3101, category: "立体图形", title: "长方体", formula: "表面积 = (长×宽 + 长×高 + 宽×高) × 2\n体积 = 长 × 宽 × 高", note: "表面积是「三组对面」各算一次再×2。体积是长宽高连乘，单位是立方（如 cm³）。"),
        MathFormula(id: 3102, category: "立体图形", title: "正方体", formula: "表面积 = 棱长 × 棱长 × 6\n体积 = 棱长 × 棱长 × 棱长", note: "6 个面全等，所以表面积棱长²×6；体积是棱长连乘三次（棱长³）。"),
        MathFormula(id: 3103, category: "立体图形", title: "圆柱", formula: "侧面积 = 底面周长 × 高\n表面积 = 侧面积 + 2×底面积\n体积 = 底面积 × 高", note: "侧面展开是个长方形（长=底面周长，宽=高）。无盖时表面积少算一个底。"),
        MathFormula(id: 3104, category: "立体图形", title: "圆锥", formula: "体积 = ⅓ × 底面积 × 高", note: "等底等高的圆柱体积的三分之一。前面一定有 ⅓，漏掉就错成圆柱了。"),

        // 单位换算
        MathFormula(id: 3201, category: "单位换算", title: "长度", formula: "1 千米 = 1000 米\n1 米 = 10 分米 = 100 厘米\n1 厘米 = 10 毫米", note: "大化小乘进率，小化大除以进率。长度相邻进率大多是 10，只有千米→米是 1000。"),
        MathFormula(id: 3202, category: "单位换算", title: "面积", formula: "1 平方千米 = 100 公顷\n1 公顷 = 10000 平方米\n1 平方米 = 100 平方分米", note: "面积进率是「长度进率的平方」：米→分米进率 10，平方米→平方分米就是 100。公顷和平方米的 10000 最易错。"),
        MathFormula(id: 3203, category: "单位换算", title: "质量", formula: "1 吨 = 1000 千克\n1 千克 = 1000 克", note: "称重用。填单位时先想「这个东西大概多重」，再决定吨/千克/克。"),
        MathFormula(id: 3204, category: "单位换算", title: "时间", formula: "1 时 = 60 分\n1 分 = 60 秒\n1 日 = 24 时", note: "时间进率是 60 和 24，不是 10 或 100。算经过时间用「结束 − 开始」。"),
        MathFormula(id: 3205, category: "单位换算", title: "体积 / 容积", formula: "1 立方米 = 1000 立方分米\n1 升 = 1 立方分米\n1 毫升 = 1 立方厘米", note: "体积与容积可以互换：升↔立方分米，毫升↔立方厘米。大瓶饮料用升，小药水用毫升。"),

        // 运算律
        MathFormula(id: 3301, category: "运算律", title: "加法交换律", formula: "a + b = b + a", note: "两个数相加，交换位置和不变。简便计算里常用来凑整。"),
        MathFormula(id: 3302, category: "运算律", title: "加法结合律", formula: "(a + b) + c = a + (b + c)", note: "先把前两个或后两个相加，和不变。配合交换律做「凑整十整百」。"),
        MathFormula(id: 3303, category: "运算律", title: "乘法交换律", formula: "a × b = b × a", note: "两数相乘，交换位置积不变。"),
        MathFormula(id: 3304, category: "运算律", title: "乘法结合律", formula: "(a × b) × c = a × (b × c)", note: "先把前两个或后两个相乘，积不变。25×4=100、125×8=1000 是黄金搭档。"),
        MathFormula(id: 3305, category: "运算律", title: "乘法分配律", formula: "a × (b + c) = a×b + a×c", note: "最容易考也最容易错：括号外的数要「分别」乘进去。逆向用（合并）也叫提取公因数。"),

        // 常用数据
        MathFormula(id: 3401, category: "常用数据", title: "π 与相关", formula: "π ≈ 3.14\n2π ≈ 6.28\n3π ≈ 9.42", note: "圆和圆柱圆锥题几乎都要用 π，建议背到 5π 以上，考试不慌。"),
        MathFormula(id: 3402, category: "常用数据", title: "平方数", formula: "11²=121  12²=144  13²=169\n15²=225  20²=400  25²=625", note: "这些平方数在简便计算和因式分解里常出现，背熟能提速。"),
        MathFormula(id: 3403, category: "常用数据", title: "植树问题", formula: "两端都栽：棵数 = 间隔数 + 1\n只栽一端：棵数 = 间隔数\n两端不栽：棵数 = 间隔数 − 1", note: "先求「总长 ÷ 间距 = 间隔数」，再按栽法加减。画图最稳。"),
        MathFormula(id: 3404, category: "常用数据", title: "平均速度", formula: "平均速度 = 总路程 ÷ 总时间", note: "不是「去速和回速的平均数」。往返同路时总路程是 2 倍单程，总时间是去程+回程。"),
    ]
}

// MARK: - 列表

private struct FormulaGroup: Identifiable {
    let category: String
    let items: [MathFormula]
    var id: String { category }
}

struct MathReferenceListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [FormulaGroup]

    init() {
        var ordered: [String] = []
        var map: [String: [MathFormula]] = [:]
        for f in MathFormula.all {
            if map[f.category] == nil { ordered.append(f.category) }
            map[f.category, default: []].append(f)
        }
        groups = ordered.map { FormulaGroup(category: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "公式速查",
                actions: AnyView(
                    IosTextButton(text: "去数学问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.category)
                        ForEach(group.items) { f in
                            FormulaRow(formula: f) { router.push(.formulaDetail(f.id)) }
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
                .fill(Hyper.math)
                .frame(width: 3, height: 16)
            Text(title)
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Spacer()
        }
        .padding(.horizontal, 14)
    }
}

private struct FormulaRow: View {
    let formula: MathFormula
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text(formula.title)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Text(formula.formula.replacingOccurrences(of: "\n", with: "  "))
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(formula.category)
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.math)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Hyper.math.opacity(0.12)))
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

struct MathFormulaDetailView: View {
    let formula: MathFormula
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text(formula.category)
                        .font(HyperType.footnote)
                        .foregroundStyle(Hyper.math)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Hyper.math.opacity(0.12)))
                    Spacer()
                }
                .padding(.horizontal, 14)

                Text(formula.title)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)

                formulaBlock
                noteBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "公式练笔：\(formula.title)",
                        outline: formula.prompt
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
        .navigationTitle(formula.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formulaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("公式")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(formula.formula)
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
            Text("怎么用 · 易错点")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(formula.note)
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
