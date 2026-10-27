import SwiftUI
import SHCore

/// 数学应用题解题步骤库：离线参考资料，放在「数学」页。
/// 与「公式速查」（列公式）互补——这个讲「怎么想、怎么一步步解」常见应用题类型
/// （鸡兔同笼 / 植树问题 / 行程问题 / 工程问题 / 和差倍 / 百分数）。是方法论，不只是公式。

// MARK: - 数据模型

struct ProblemType: Identifiable {
    let id: Int
    let category: String
    let title: String
    /// 一句话思路 / 口诀。
    let idea: String
    /// 解题步骤（有序）。
    let steps: [String]
    /// 一个示范例题 + 简答。
    let example: String

    var prompt: String {
        let stepText = steps.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n")
        return """
        【应用题练一练：\(title)】
        思路：\(idea)
        步骤：
        \(stepText)
        例题：\(example)
        """
    }
}

extension ProblemType {
    static let all: [ProblemType] = [
        ProblemType(id: 9001, category: "经典题型", title: "鸡兔同笼", idea: "假设全是其中一种，看差多少脚，再换。", steps: [
            "假设笼子里全是鸡（每只2只脚）。",
            "算出假设的总脚数：头数 × 2。",
            "用实际脚数减去假设脚数，得到多出来的脚。",
            "每把一只鸡换成兔，脚多 2 只，除以 2 得兔的只数。",
            "头数减去兔数，得到鸡的只数。",
        ], example: "头共8，脚共22。假设全鸡=16脚，多6脚，兔=6÷2=3只，鸡=8-3=5只。"),
        ProblemType(id: 9002, category: "经典题型", title: "植树问题", idea: "看两端种不种：间隔数 = 总长 ÷ 间距。", steps: [
            "先算间隔数：总长 ÷ 间距。",
            "两端都种：棵数 = 间隔数 + 1。",
            "只种一端：棵数 = 间隔数。",
            "两端都不种：棵数 = 间隔数 - 1。",
            "封闭图形（圆形）：棵数 = 间隔数。",
        ], example: "一条路长20米，每5米种一棵，两端都种：间隔=4，棵数=4+1=5棵。"),
        ProblemType(id: 9003, category: "运动题型", title: "行程问题", idea: "记住：路程 = 速度 × 时间。", steps: [
            "找已知：速度、时间、路程中给了哪两个。",
            "求路程：速度 × 时间。",
            "求时间：路程 ÷ 速度。",
            "求速度：路程 ÷ 时间。",
            "相遇问题：总路程 = 速度和 × 相遇时间。",
        ], example: "甲每小时行5千米，走3小时：路程=5×3=15千米。"),
        ProblemType(id: 9004, category: "工程题型", title: "工程问题", idea: "把总量看成1，效率 = 1 ÷ 时间。", steps: [
            "把总工程看作 1。",
            "甲效率 = 1 ÷ 甲单独用时。",
            "乙效率 = 1 ÷ 乙单独用时。",
            "合作效率 = 甲效率 + 乙效率。",
            "合作时间 = 1 ÷ 合作效率。",
        ], example: "甲6天完，乙3天完：效率和=1/6+1/3=1/2，合作=1÷1/2=2天。"),
        ProblemType(id: 9005, category: "数量关系", title: "和差倍问题", idea: "画线段图，把「一倍量」找出来。", steps: [
            "和倍：一倍量 = 和 ÷（倍数 + 1）。",
            "差倍：一倍量 = 差 ÷（倍数 - 1）。",
            "和差：大数 =（和 + 差）÷ 2，小数 =（和 - 差）÷ 2。",
            "先确定谁是「一倍量」，再列算式。",
            "用加法验算两数之和/差是否对得上。",
        ], example: "两数和为30，差为8：大=(30+8)/2=19，小=(30-8)/2=11。"),
        ProblemType(id: 9006, category: "百分数", title: "百分数应用题", idea: "找准「单位1」：谁的几分之几。", steps: [
            "找单位1：通常「的」前面、「比」后面是单位1。",
            "求部分：单位1 × 百分率。",
            "求率：部分 ÷ 单位1。",
            "求单位1：部分 ÷ 对应百分率。",
            "增减问题：现量 = 原量 ×（1 ± 百分率）。",
        ], example: "50元涨价20%：50×(1+20%)=60元。"),
        ProblemType(id: 9007, category: "经典题型", title: "年龄问题", idea: "年龄差永远不变。", steps: [
            "写出两人今年年龄与年龄差。",
            "记住：再过几年，两人都长同样岁数，差不变。",
            "和差型：用和差公式（大=(和+差)/2）。",
            "倍型：用差倍公式（一倍量=差÷（倍-1））。",
            "把求出的年龄代回验算。",
        ], example: "父比子大28岁，父是子的5倍：子=28÷(5-1)=7岁，父=35岁。"),
        ProblemType(id: 9008, category: "数量关系", title: "归一问题", idea: "先算「一份是多少」，再算总数。", steps: [
            "正归一：先求单一量（÷），再求总量（×）。",
            "反归一：先求单一量，再看总量包含几个单一量。",
            "3台机器2小时做60个：1台1小时=60÷3÷2=10个。",
            "再按问题乘或除。",
            "注意单位统一（小时/分钟）。",
        ], example: "3台2小时做60个，求5台4小时：单量=10，总=10×5×4=200个。"),
    ]
}

// MARK: - 列表

private struct ProblemSection: Identifiable {
    let category: String
    let items: [ProblemType]
    var id: String { category }
}

struct MathProblemListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [ProblemSection]

    init() {
        var ordered: [String] = []
        var map: [String: [ProblemType]] = [:]
        for p in ProblemType.all {
            if map[p.category] == nil { ordered.append(p.category) }
            map[p.category, default: []].append(p)
        }
        groups = ordered.map { ProblemSection(category: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "应用题解题",
                actions: AnyView(
                    IosTextButton(text: "去数学问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.category)
                        ForEach(group.items) { p in
                            ProblemRow(type: p) { router.push(.problemDetail(p.id)) }
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

private struct ProblemRow: View {
    let type: ProblemType
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text(type.title)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Text(type.idea)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(type.category)
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

struct MathProblemDetailView: View {
    let type: ProblemType
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(type.title)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                ideaBlock
                stepsBlock
                exampleBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "应用题练一练：\(type.title)",
                        outline: type.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这个方法去练")
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
        .navigationTitle(type.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ideaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("思路")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(type.idea)
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

    private var stepsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("解题步骤")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<type.steps.count, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1).")
                            .font(HyperType.bodyMedium)
                            .foregroundStyle(Hyper.math)
                            .frame(width: 18, alignment: .leading)
                        Text(type.steps[i])
                            .font(HyperType.bodyMedium)
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.cardShape.fill(palette.card))
        .padding(.horizontal, 14)
    }

    private var exampleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("例题")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(type.example)
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
