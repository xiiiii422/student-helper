import SwiftUI
import UIKit
import SHCore

/// 批改结果详情，对齐安卓 `ui/components/FeedbackDetail.kt` 的分块顺序：
/// 分项 → 总评 → 优点 → 问题 → 改进建议 → 好句升级 → 范文片段。
struct FeedbackDetailView: View {
    let feedback: CompositionFeedback
    @Environment(\.hyperPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            breakdownCard
            if !feedback.summary.isEmpty {
                section("总评") { Text(feedback.summary).font(HyperType.body).foregroundStyle(palette.text) }
            }
            if !feedback.strengths.isEmpty {
                section("优点") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(feedback.strengths) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.content).font(HyperType.body).foregroundStyle(palette.text)
                                Text("\(item.location)｜\(item.why)")
                                    .font(HyperType.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }
            }
            if !feedback.issues.isEmpty {
                section("需要修改") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(feedback.issues) { issue in
                            issueCard(issue)
                        }
                    }
                }
            }
            if !feedback.suggestions.isEmpty {
                section("改进建议") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(feedback.suggestions.enumerated()), id: \.offset) { index, text in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(HyperType.bodyMedium)
                                    .foregroundStyle(palette.textTertiary)
                                Text(text).font(HyperType.bodyMedium).foregroundStyle(palette.text)
                            }
                        }
                    }
                }
            }
            if !feedback.rewrites.isEmpty {
                section("好句升级") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(feedback.rewrites) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                labelLine("原句", item.original, color: noteOriginal)
                                labelLine("更好", item.rewritten, color: noteBetter)
                                Text(item.why).font(HyperType.footnote).foregroundStyle(palette.textSecondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(HyperRadius.smallShape.fill(palette.card))
                        }
                    }
                }
            }
            if !feedback.sample.isEmpty {
                section("同类范文片段") {
                    Text(feedback.sample).font(HyperType.bodyMedium).foregroundStyle(palette.text)
                }
            }
        }
    }

    // 批改语义色要分深浅：深底上用 #B45309 这种暗棕几乎看不见
    private var noteOriginal: Color { palette.isDark ? Hyper.noteOriginalDark : Hyper.noteOriginal }
    private var noteBetter: Color { palette.isDark ? Hyper.noteBetterDark : Hyper.noteBetter }

    private var breakdownCard: some View {
        let rows: [(String, Int)] = [
            ("内容", feedback.breakdown.content),
            ("结构", feedback.breakdown.structure),
            ("语言", feedback.breakdown.language),
            ("书写", feedback.breakdown.writing),
        ]
        return VStack(spacing: 10) {
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 10) {
                    Text(row.0).font(HyperType.bodyMedium).foregroundStyle(palette.textSecondary)
                        .frame(width: 44, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.fill).frame(height: 6)
                            Capsule()
                                .fill(ScoreColor.forScore(Int(Double(row.1) / 25 * 100)))
                                .frame(width: max(6, geo.size.width * CGFloat(row.1) / 25), height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("\(row.1)/25")
                        .font(HyperType.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            if feedback.totalScore != feedback.breakdownTotal {
                // 模型给过总分 90、分项合计 62 的情况，不一致就摊开说，别让学生猜
                Text("总分 \(feedback.totalScore) 与分项合计 \(feedback.breakdownTotal) 不一致，以分项为准。")
                    .font(HyperType.footnote)
                    .foregroundStyle(Hyper.composition)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    private func issueCard(_ issue: IssueItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(issue.location)｜\(issue.type)")
                .font(HyperType.footnote)
                .foregroundStyle(palette.textTertiary)
            labelLine("原句", issue.original, color: noteOriginal)
            Text(issue.explanation).font(HyperType.bodyMedium).foregroundStyle(palette.text)
            labelLine("改成", issue.suggestion, color: noteBetter)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HyperRadius.smallShape.fill(palette.card))
    }

    private func labelLine(_ label: String, _ value: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 0.6))
            Text(value).font(HyperType.bodyMedium).foregroundStyle(color)
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(HyperType.titleMedium)
                .foregroundStyle(palette.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 生成作文（iOS 新增功能）：给题目 → 审题 + 提纲 + 范文 + 好词好句，并且能整篇朗读。
///
/// 刻意不做成「一键抄一篇」：结构与讲题一致，学生可以先照提纲自己写，
/// 范文当参照；朗读用的是同一套 SpeechService，范文的提示词里也写了「便于朗读」。
struct EssayView: View {
    @StateObject var vm: EssayViewModel
    @Environment(\.hyperPalette) private var palette
    @EnvironmentObject private var speechHolder: SpeechService

    @State private var title = ""
    @State private var requirement = ""
    @State private var genre = "记叙文"
    @State private var words = 500

    private let genres = ["记叙文", "写人", "记事", "写景", "读后感", "书信", "说明文"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inputs
                generateButton
                if vm.generating {
                    HStack(spacing: 8) {
                        LoadingDots(color: palette.textSecondary)
                        Text("老师正在写…").font(HyperType.bodyMedium).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, 6)
                }
                if let result = vm.result {
                    resultCard(result)
                }
                if let error = vm.error {
                    Text(error).font(HyperType.bodyMedium).foregroundStyle(palette.error)
                }
            }
            .padding(16)
        }
        .background(palette.background)
        .navigationTitle("生成作文")
        .navigationBarTitleDisplayMode(.inline)
        // 离开页面就掐掉生成任务：以前这个 Task 脱离视图生命周期，
        // 学生等不及退出去别处，请求还会跑完、范文还会悄悄写进作文列表。
        .onDisappear { vm.cancelGeneration() }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledField("作文题目", text: $title, placeholder: "如：一次难忘的经历")
            labeledField("题目要求（可选）", text: $requirement, placeholder: "如：写出心理活动，结尾呼应开头")

            Picker("体裁", selection: $genre) {
                ForEach(genres, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(palette.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("字数：约 \(words) 字")
                    .font(HyperType.footnote)
                    .foregroundStyle(palette.textSecondary)
                Slider(value: Binding(get: { Double(words) }, set: { words = Int($0) }), in: 300...800, step: 50)
                    .tint(Hyper.composition)
            }
        }
        .padding(14)
        .background(HyperRadius.cardShape.fill(palette.card))
    }

    private func labeledField(
        _ label: String, text: Binding<String>, placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(HyperType.footnote).foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: text)
                .font(HyperType.body)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(palette.fill))
        }
    }

    private var canGenerate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.generating
    }

    private var generateButton: some View {
        Button {
            // 生成中再点一次就是停止：长文本要等十几秒，没有出口只能干等
            if vm.generating { vm.cancelGeneration() }
            else { vm.start(title: title, requirement: requirement, genre: genre, words: words) }
        } label: {
            Text(vm.generating ? "停止生成" : "生成范文")
                .font(HyperType.titleMedium)
                // 禁用态别用「浅色底 + 白字」——在浅色背景上几乎看不见，
                // 换成灰底深灰字，学生一眼就知道是「还不能点」而不是「按钮坏了」。
                .foregroundStyle(buttonEnabled ? Color.white : palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(buttonEnabled ? buttonColor : palette.divider))
        }
        .buttonStyle(.plain)
        .disabled(!buttonEnabled)
    }

    /// 生成中：按钮本身变成「停止」，所以此时必须可点（不再受标题是否为空影响）
    private var buttonEnabled: Bool { vm.generating || canGenerate }
    private var buttonColor: Color { vm.generating ? palette.error : Hyper.composition }

    private func resultCard(_ result: EssayViewModel.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("范文").font(HyperType.titleMedium).foregroundStyle(palette.text)
                Spacer()
                Button {
                    if speechHolder.isSpeaking { speechHolder.stop() }
                    else { speechHolder.speak(result.raw) }
                } label: {
                    Label(
                        speechHolder.isSpeaking ? "停止朗读" : "朗读",
                        systemImage: speechHolder.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill"
                    )
                    .font(HyperType.labelLarge)
                    .foregroundStyle(Hyper.composition)
                }
                .buttonStyle(.plain)
            }
            ForEach(result.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(HyperType.labelLarge)
                        .foregroundStyle(Hyper.composition)
                    Text(section.body)
                        .font(HyperType.body)
                        .lineSpacing(HyperType.bodyLineSpacing)
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                UIPasteboard.general.string = result.raw
                Haptics.success()
            } label: {
                Label("复制全文", systemImage: "doc.on.doc")
                    .font(HyperType.labelLarge)
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(HyperRadius.cardShape.fill(palette.card))
    }
}

@MainActor
final class EssayViewModel: ObservableObject {
    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    struct Result {
        let raw: String
        let sections: [Section]
    }

    @Published var result: Result?
    @Published var generating = false
    @Published var error: String?

    private let llm: LlmService
    private let store: AppStore
    /// 当前生成任务。留着句柄才能在离开页面/点停止时取消它——
    /// 以前 Task 是脱离生命周期甩出去跑的，退出去后请求照跑完、范文照写进列表。
    private var task: Task<Void, Never>?
    /// 代数守卫。@MainActor 只保证方法之间不并行，`await` 处会让出：
    /// 用户「点停止 → 马上又点生成」时，旧任务此刻才收尾，若无条件清 task/generating，
    /// 抹掉的是**新任务**的状态（新任务从此停不掉、按钮还显示生成中）。
    /// 因此任何对共享状态的写，都要先确认自己仍是当前这一代。
    private var generation = 0

    init(llm: LlmService, store: AppStore) {
        self.llm = llm
        self.store = store
    }

    /// 取消生成：掐网络请求，且不清 result（留着上次成果）。
    func cancelGeneration() {
        generation += 1
        task?.cancel()
        task = nil
        generating = false
    }

    /// 启动生成并把任务句柄存下来，这样 cancelGeneration / onDisappear 才掐得住它。
    func start(title: String, requirement: String, genre: String, words: Int) {
        guard !generating else { return }
        generation += 1
        let myGen = generation
        generating = true
        task = Task { [weak self] in
            await self?.run(
                generation: myGen, title: title, requirement: requirement,
                genre: genre, words: words
            )
        }
    }

    /// 一次生成的实际过程。所有对共享状态的写都先过代数校验。
    private func run(
        generation myGen: Int, title: String, requirement: String,
        genre: String, words: Int
    ) async {
        defer {
            if myGen == generation {
                generating = false
                task = nil
            }
        }
        // 排到这条任务之前用户已经取消/重新发起过：整段都不该再动共享状态
        guard myGen == generation else { return }
        error = nil
        do {
            let messages = PromptAssembler.essayMessages(
                title: title,
                requirement: requirement.isEmpty ? nil : requirement,
                genre: genre,
                wordCount: words
            )
            let raw = try await llm.complete(
                systemPrompt: messages[0].content,
                userText: messages[1].content,
                temperature: PromptAssembler.temperature(for: .essay)
            )
            // 请求返回但用户已经取消/退出：别再写库、别再弹结果，否则就是「悄悄多出一篇」
            if myGen != generation || Task.isCancelled { return }
            result = Self.parse(raw)
            // 生成的范文也进作文列表，学生改完可以直接送去批改
            store.insert(
                Composition(
                    title: title,
                    content: Self.essayBody(from: raw),
                    imageUris: "[]",
                    aiFeedback: ""
                )
            )
        } catch is CancellationError {
            // 主动取消不算错误，界面上什么都不留
        } catch {
            if myGen != generation || Task.isCancelled { return }
            self.error = LlmPolicy.friendlyError(
                (error as? LlmError)?.message ?? error.localizedDescription
            )
        }
    }

    /// 按【】小标题切段；没有小标题时整篇当一段，不硬编。
    static func parse(_ raw: String) -> Result {
        var sections: [Section] = []
        let pattern = try! NSRegularExpression(pattern: "【([^】]{1,10})】")
        let ns = raw as NSString
        let matches = pattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty {
            return Result(raw: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                          sections: [Section(title: "范文", body: raw.trimmingCharacters(in: .whitespacesAndNewlines))])
        }
        for (index, match) in matches.enumerated() {
            let name = ns.substring(with: match.range(at: 1))
            let start = match.range.location + match.range.length
            let end: Int
            if index + 1 < matches.count {
                end = matches[index + 1].range.location
            } else {
                end = ns.length
            }
            let body = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { sections.append(Section(title: name, body: body)) }
        }
        return Result(raw: raw.trimmingCharacters(in: .whitespacesAndNewlines), sections: sections)
    }

    /// 存进列表时只留正文，别把【审题】【提纲】一起当成学生写的作文。
    static func essayBody(from raw: String) -> String {
        let parsed = parse(raw)
        if let essay = parsed.sections.first(where: { $0.title == "范文" }) {
            return essay.body
        }
        return parsed.raw
    }
}
