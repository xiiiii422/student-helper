import SwiftUI
import UIKit
import SHCore

/// OCR 确认弹窗，对齐安卓 `ui/components/OcrConfirmDialog.kt`：
/// 识别结果可编辑、可重识别、并让用户决定「只发文字」还是「文字连原图一起发」。
/// 之所以要问一句：识别准不准只有学生自己看得出来，而带原图会走更贵的视觉通道。
struct OcrConfirmSheet: View {
    let pending: PendingOcr
    let onSend: (String, SendMode) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var mode: SendMode
    @Environment(\.hyperPalette) private var palette

    init(pending: PendingOcr, onSend: @escaping (String, SendMode) -> Void, onCancel: @escaping () -> Void) {
        self.pending = pending
        self.onSend = onSend
        self.onCancel = onCancel
        _text = State(initialValue: pending.text)
        _mode = State(initialValue: pending.suggestedMode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    thumbnail

                    VStack(alignment: .leading, spacing: 6) {
                        Text("识别结果（可以改）")
                            .font(HyperType.labelLarge)
                            .foregroundStyle(palette.textSecondary)
                        TextEditor(text: $text)
                            .font(HyperType.body)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(palette.fill)
                            )
                    }

                    confidenceRow

                    VStack(alignment: .leading, spacing: 8) {
                        Text("怎么问")
                            .font(HyperType.labelLarge)
                            .foregroundStyle(palette.textSecondary)
                        ForEach([SendMode.textOnly, .textAndImage], id: \.self) { option in
                            modeRow(option)
                        }
                        Text(footnote)
                            .font(HyperType.footnote)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .padding(16)
            }
            .background(palette.background)
            .navigationTitle("确认题目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") { onSend(text, mode) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let image = LocalImage.load(pending.imageUri) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var confidenceRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)
            Text("识别置信度 \(Int(pending.confidence * 100))%")
                .font(HyperType.bodyMedium)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
    }

    private var confidenceColor: Color {
        if pending.confidence >= 0.85 { return Hyper.statusOk }
        if pending.confidence >= 0.6 { return Hyper.scoreFair }
        return palette.error
    }

    private var footnote: String {
        switch mode {
        case .textOnly: return "只发文字：更快更省，适合识别结果已经完整的情况。"
        case .textAndImage: return "连原图一起发：老师会先看图片原貌，识别漏了也能补上。"
        }
    }

    private func modeRow(_ option: SendMode) -> some View {
        Button {
            mode = option
            Haptics.lightTap()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(mode == option ? palette.accent : palette.textTertiary)
                Text(option.label)
                    .font(HyperType.bodyMedium)
                    .foregroundStyle(palette.text)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(mode == option ? palette.accent : palette.divider, lineWidth: mode == option ? 1.2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 图片全屏预览。安卓用 Dialog，iOS 用 fullScreenCover + 双指缩放。
struct PreviewImageView: View {
    let uri: String
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = LocalImage.load(uri) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = scale > 1 ? 1 : 2
                            lastScale = scale
                        }
                    }
            } else {
                Text("图片已不在本机")
                    .foregroundStyle(.white.opacity(0.7))
            }
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(16)
                    }
                }
                Spacer()
            }
        }
    }
}
