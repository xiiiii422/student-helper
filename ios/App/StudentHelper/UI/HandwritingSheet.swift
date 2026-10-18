import SwiftUI
import UIKit
import SHCore

/// 手写输入板：手指写一道题，识别成文字填回输入框。
/// 对齐安卓 `ui/components/HandwritingCanvas.kt` 的用途 —— 有些题目学生打不出字
/// （分数、几何图形、古诗里的生僻字），但写得出来。
///
/// 识别优先走 ML Kit Digital Ink（吃笔迹，离线，中文/英文模型），
/// 只有它不可用时才退回「渲染成图片交给 Vision」的老路（Vision 对手写很差，仅作兜底）。
struct HandwritingSheet: View {
    let onResult: (String) -> Void

    @Environment(\.hyperPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [Stroke] = []
    @State private var current: [CGPoint] = []
    @State private var currentTimes: [Int] = []
    @State private var recognizing = false
    @State private var candidates: [HandwritingInk.Candidate] = []
    @State private var hint: String?

    struct Stroke: Equatable {
        var points: [CGPoint]
        /// 绝对毫秒时间戳，和 points 一一对应；转给 ML Kit 时再减掉首点做归一。
        var times: [Int] = []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                canvas
                if !candidates.isEmpty { candidateRow }
                toolbar
                if let hint {
                    Text(hint)
                        .font(HyperType.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, 16)
            .background(palette.background)
            .navigationTitle("手写题目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { recognize() } label: {
                        if recognizing {
                            ProgressView().frame(width: 24, height: 24)
                        } else {
                            Text("识别")
                        }
                    }
                    .disabled(strokes.isEmpty || recognizing)
                }
            }
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(palette.card)
            )
            // 横格线：手写有参照，字不会越写越歪
            var grid = Path()
            var y: CGFloat = 44
            while y < size.height {
                grid.move(to: CGPoint(x: 12, y: y))
                grid.addLine(to: CGPoint(x: size.width - 12, y: y))
                y += 44
            }
            context.stroke(grid, with: .color(palette.divider), lineWidth: 0.6)

            for stroke in strokes + [Stroke(points: current)] {
                guard stroke.points.count > 1 else {
                    if let only = stroke.points.first {
                        context.fill(
                            Path(ellipseIn: CGRect(x: only.x - 1.6, y: only.y - 1.6, width: 3.2, height: 3.2)),
                            with: .color(palette.text)
                        )
                    }
                    continue
                }
                var path = Path()
                path.addLines(stroke.points)
                context.stroke(
                    path,
                    with: .color(palette.text),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let t = Self.millis(value.time)
                    if current.isEmpty {
                        current = [value.location]
                        currentTimes = [t]
                    } else {
                        current.append(value.location)
                        currentTimes.append(t)
                    }
                }
                .onEnded { value in
                    if !current.isEmpty {
                        current.append(value.location)
                        currentTimes.append(Self.millis(value.time))
                        strokes.append(Stroke(points: current, times: currentTimes))
                    }
                    current = []
                    currentTimes = []
                }
        )
    }

    /// 候选字词：手写识别一次给多个候选，让学生自己挑比硬猜一个准。
    private var candidateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选一个填进去（或直接在下面改）")
                .font(HyperType.footnote)
                .foregroundStyle(palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(candidates.prefix(6)) { candidate in
                        Button {
                            accept(candidate.text)
                        } label: {
                            Text(candidate.text)
                                .font(HyperType.bodyMedium)
                                .foregroundStyle(palette.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(palette.fill)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            secondaryButton("撤销一笔", icon: "arrow.uturn.backward", disabled: strokes.isEmpty) {
                if !strokes.isEmpty { strokes.removeLast() }
                candidates = []
            }
            secondaryButton("清空", icon: "eraser", disabled: strokes.isEmpty) {
                strokes.removeAll()
                candidates = []
                hint = nil
            }
            Spacer()
        }
    }

    private func secondaryButton(
        _ label: String, icon: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(HyperType.bodyMedium)
            }
            .foregroundStyle(disabled ? palette.textTertiary : palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.fill)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func accept(_ text: String) {
        onResult(text)
        Haptics.success()
        dismiss()
    }

    // MARK: 识别

    private func recognize() {
        recognizing = true
        hint = nil
        candidates = []
        let finished = strokes

        if !HandwritingInk.anyReady {
            hint = "首次使用要先下载手写模型（约 20MB），请保持联网…"
        }

        Task {
            // 1) 首选：ML Kit Digital Ink（真正的笔迹识别）
            let inkStrokes = Self.toInkStrokes(finished)
            if !inkStrokes.isEmpty {
                let merged = await HandwritingInk.recognizeMerged(strokes: inkStrokes)
                if !merged.isEmpty {
                    await MainActor.run {
                        recognizing = false
                        candidates = merged
                        hint = "识别出 \(merged.count) 个候选，点一个填进去"
                    }
                    return
                }
            }

            // 2) 兜底：渲染成图片交给 Vision（手写效果差，但总比没结果强）
            await MainActor.run {
                hint = "手写模型没给出结果，改用图片识别兜底…"
            }
            let image = HandwritingRenderer.render(strokes: finished)
            let result = await OcrService.recognize(image: image)
            await MainActor.run {
                recognizing = false
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    hint = "没认出字来。写大一点、贴着横格写，或者改用拍照。"
                    Haptics.warning()
                } else {
                    candidates = [HandwritingInk.Candidate(text: text, score: 0)]
                    hint = "这是图片识别的结果，点一下填进去"
                }
            }
        }
    }

    private static func millis(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 * 1000)
    }

    private static func toInkStrokes(_ strokes: [Stroke]) -> [InkStroke] {
        strokes.compactMap { stroke in
            guard stroke.points.count > 1 else { return nil }
            let base = stroke.times.first ?? 0
            var points: [InkStroke.Point] = []
            for (i, p) in stroke.points.enumerated() {
                let raw = i < stroke.times.count ? stroke.times[i] : base + i * 16
                points.append(InkStroke.Point(x: p.x, y: p.y, t: max(0, raw - base)))
            }
            return InkStroke(points: points)
        }
    }
}

/// 把笔画画成白底黑字图，交给 Vision。
enum HandwritingRenderer {
    static func render(strokes: [HandwritingSheet.Stroke], size: CGSize = CGSize(width: 900, height: 1200)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for stroke in strokes {
                guard stroke.points.count > 1 else { continue }
                path.move(to: stroke.points[0])
                for point in stroke.points.dropFirst() { path.addLine(to: point) }
            }
            path.stroke()
        }
    }
}
