import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI
import SHCore

/// 输入栏，逐条对齐安卓 `ui/components/InputBar.kt`：
/// 左侧拍照 / 相册两个入口，中间浅灰胶囊输入框，右侧圆形上箭头发送。
/// 半透乳白底 + 发丝顶线，和底栏同一套材质。
///
/// 手写入口已移除：小学生搜题就是拍一张，在手机上比划写字反而更慢。
struct InputBarView: View {
    @Binding var text: String
    let enabled: Bool
    let accent: Color
    /// 正在流式生成：发送按钮换成「停止」，点一下取消当前请求（已生成的部分会保留）
    var isStreaming: Bool = false
    var onTakePhoto: () -> Void = {}
    var onPickImage: () -> Void = {}
    var onSend: () -> Void = {}
    var onStop: () -> Void = {}

    @Environment(\.hyperPalette) private var palette
    @FocusState private var focused: Bool

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canSend: Bool { enabled && hasContent }

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .bottom, spacing: 6) {
                icon("camera", label: "拍照", action: onTakePhoto)
                icon("photo.on.rectangle", label: "相册", action: onPickImage)

                field

                sendButton
                    .padding(.bottom, 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(palette.card.opacity(0.94))
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("输入或描述你的题目…", text: $text, axis: .vertical)
                .font(HyperType.body)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }
                .disabled(!enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.fill)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendButton: some View {
        Button {
            if isStreaming {
                Haptics.lightTap()
                onStop()
                return
            }
            guard canSend else { return }
            Haptics.lightTap()
            focused = false
            onSend()
        } label: {
            ZStack {
                Circle()
                    .fill(isStreaming ? palette.accent : (canSend ? palette.accent : palette.text.opacity(0.2)))
                    .frame(width: 34, height: 34)
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: isStreaming ? 13 : 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 38, height: 38)
        .accessibilityLabel(isStreaming ? "停止生成" : "发送")
    }

    private func icon(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 40, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// 拍照：系统相机直入，不弹相册选择器（拍题是最高频动作，少一步是一步）。
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let url = Self.writeTemp(image) else {
                parent.onCancel()
                return
            }
            parent.onCapture(url)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.onCancel()
        }

        /// 相机回传的是内存里的 UIImage，先落成临时文件，好让后续链路与「从相册选」统一走 URL。
        private static func writeTemp(_ image: UIImage) -> URL? {
            guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("capture_\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
            return (try? data.write(to: url)) != nil ? url : nil
        }
    }
}

/// 相册多选（作文支持到 4 页手稿，一次选多页比来回进相册省事）。
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 4
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                parent.onCancel()
                return
            }
            // 用 loadTransferable(Data) 而不是已废弃的 loadObject(ofClass:)：
            // 拿到的是原始文件数据，HEIC 不用先转一道，也不会把整张原图读进内存
            for result in results {
                let provider = result.itemProvider
                guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
                _ = provider.loadTransferable(type: Data.self) { object in
                    switch object {
                    case .success(let data):
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("lib_\(UUID().uuidString).jpg")
                        if (try? data.write(to: url)) != nil {
                            DispatchQueue.main.async { self.parent.onPick(url) }
                        }
                    case .failure:
                        DispatchQueue.main.async { self.parent.onCancel() }
                    }
                }
            }
        }
    }
}
