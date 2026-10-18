import SwiftUI

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
            Task { await vm.generate(title: title, requirement: requirement, genre: genre, words: words) }
        } label: {
            Text(vm.generating ? "生成中…" : "生成范文")
                .font(HyperType.titleMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(canGenerate ? Hyper.composition : Hyper.composition.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
    }

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

    init(llm: LlmService, store: AppStore) {
        self.llm = llm
        self.store = store
    }

    func generate(title: String, requirement: String, genre: String, words: Int) async {
        guard !generating else { return }
        generating = true
        error = nil
        defer { generating = false }
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
        } catch {
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
