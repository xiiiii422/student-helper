import SwiftUI
import SHCore

/// 英语日常对话库：离线参考资料，放在「英语」页。
/// 与词汇（主题单词）、句型（语法结构）互补——这个给「完整情景对话」，是开口说的脚手架
/// （打招呼 / 问好 / 道谢 / 道歉 / 请求 / 购物 / 问路 / 学校）。每条一组问答 + 一句实用贴士，
/// 点「用这段对话去说」把对话带进「新建批改」，练写一段类似对话。

// MARK: - 数据模型

struct Dialogue: Identifiable {
    let id: Int
    let category: String
    let title: String
    /// 问答对。
    let lines: [(speaker: String, text: String)]
    /// 一句实用贴士（礼貌/替换词）。
    let tip: String

    var prompt: String {
        let convo = lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        return """
        【情景对话练写：\(title)】
        参考对话：
        \(convo)
        贴士：\(tip)
        试着用类似句式自己写一段小对话。
        """
    }
}

extension Dialogue {
    static let all: [Dialogue] = [
        Dialogue(id: 8001, category: "打招呼", title: "见面问好", lines: [
            ("A", "Hello! / Hi!"), ("B", "Hello! How are you?"),
            ("A", "I'm fine, thank you. And you?"), ("B", "I'm fine too."),
        ], tip: "熟人可用 Hi，正式一点用 Hello；How are you? 是最常用的问好。"),
        Dialogue(id: 8002, category: "道谢", title: "说谢谢", lines: [
            ("A", "Thank you very much!"), ("B", "You're welcome."),
            ("A", "Thanks for your help."), ("B", "No problem."),
        ], tip: "Thank you / Thanks 都可以；回答用 You're welcome 或 No problem。"),
        Dialogue(id: 8003, category: "道歉", title: "说对不起", lines: [
            ("A", "I'm sorry."), ("B", "That's OK."),
            ("A", "Excuse me."), ("B", "Yes?"),
        ], tip: "Excuse me 用于借过/打断；I'm sorry 用于做错事。"),
        Dialogue(id: 8004, category: "请求", title: "请别人帮忙", lines: [
            ("A", "Can you help me, please?"), ("B", "Sure / Of course."),
            ("A", "May I use your pen?"), ("B", "Yes, here you are."),
        ], tip: "Can you...? 更口语；May I...? 更礼貌，用于请求许可。"),
        Dialogue(id: 8005, category: "购物", title: "买东西", lines: [
            ("A", "How much is it?"), ("B", "It's ten yuan."),
            ("A", "I'll take it."), ("B", "Here you are."),
        ], tip: "问价格用 How much is/are...?；决定买说 I'll take it。"),
        Dialogue(id: 8006, category: "问路", title: "问地点", lines: [
            ("A", "Where is the school?"), ("B", "Go straight and turn left."),
            ("A", "Is it far?"), ("B", "No, it's near."),
        ], tip: "问地点用 Where is...?；指路常用 Go straight / turn left(right)。"),
        Dialogue(id: 8007, category: "学校", title: "课堂用语", lines: [
            ("A", "May I come in?"), ("B", "Come in, please."),
            ("A", "May I go to the toilet?"), ("B", "Yes, you may."),
        ], tip: "进教室、请假常用 May I...?，老师回答用 Yes, you may / Come in, please。"),
        Dialogue(id: 8008, category: "天气", title: "聊天气", lines: [
            ("A", "What's the weather like?"), ("B", "It's sunny and warm."),
            ("A", "I like sunny days."), ("B", "Me too."),
        ], tip: "问天气用 What's the weather like?；回答用 It's + 形容词。"),
        Dialogue(id: 8009, category: "喜好", title: "喜欢什么", lines: [
            ("A", "What do you like?"), ("B", "I like apples."),
            ("A", "Do you like cats?"), ("B", "Yes, I do. / No, I don't."),
        ], tip: "问喜好用 What do you like? / Do you like...?；回答用 I like... / Yes, I do。"),
        Dialogue(id: 8010, category: "吃饭", title: "三餐与口味", lines: [
            ("A", "What do you want to eat?"), ("B", "I want some noodles."),
            ("A", "Would you like some water?"), ("B", "Yes, please."),
        ], tip: "想要什么用 I want... / Would you like...? 表示邀请。"),
    ]
}

// MARK: - 列表

private struct DialogueSection: Identifiable {
    let category: String
    let items: [Dialogue]
    var id: String { category }
}

struct EnglishDialogueListView: View {
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    private let groups: [DialogueSection]

    init() {
        var ordered: [String] = []
        var map: [String: [Dialogue]] = [:]
        for d in Dialogue.all {
            if map[d.category] == nil { ordered.append(d.category) }
            map[d.category, default: []].append(d)
        }
        groups = ordered.map { DialogueSection(category: $0, items: map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            IosLargeTitle(
                title: "日常对话",
                actions: AnyView(
                    IosTextButton(text: "去英语问问") { router.push(.essay) }
                )
            )
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(groups) { group in
                        sectionHeader(group.category)
                        ForEach(group.items) { d in
                            DialogueRow(dialogue: d) { router.push(.dialogueDetail(d.id)) }
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

private struct DialogueRow: View {
    let dialogue: Dialogue
    let onOpen: () -> Void
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dialogue.title)
                    .font(HyperType.titleMedium)
                    .foregroundStyle(palette.text)
                Text(dialogue.lines.first?.text ?? "")
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(dialogue.category)
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

struct EnglishDialogueDetailView: View {
    let dialogue: Dialogue
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(dialogue.title)
                    .font(HyperType.title2)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)

                dialogueBlock
                tipBlock

                Button {
                    router.push(.compositionNewWithTemplate(
                        title: "情景对话练写：\(dialogue.title)",
                        outline: dialogue.prompt
                    ))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("用这段对话去说")
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
        .navigationTitle(dialogue.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dialogueBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("对话")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(dialogue.lines, id: \.speaker) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.speaker + ":")
                            .font(HyperType.bodyMedium)
                            .foregroundStyle(Hyper.english)
                            .frame(width: 18, alignment: .leading)
                        Text(line.text)
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

    private var tipBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("实用贴士")
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            Text(dialogue.tip)
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
