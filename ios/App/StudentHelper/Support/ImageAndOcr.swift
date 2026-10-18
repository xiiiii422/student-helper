import Foundation
import ImageIO
import UIKit
import Vision

/// 图片压缩与 base64，对齐安卓 `core/util/BitmapUtils`。
/// 上传给视觉模型前先降采样：手机直出 4000×3000 的图既慢又贵，题目文字 1280 长边足够看清。
enum ImageCodec {

    static let maxEdge: CGFloat = 1280
    static let jpegQuality: CGFloat = 0.72

    static func compress(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func base64(from image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: jpegQuality) else { return nil }
        return data.base64EncodedString()
    }

    /// 从本地路径读图并编码；文件不存在或解码失败返回 nil（重试图片题时用到）。
    static func base64FromFile(path: String) -> String? {
        guard let raw = UIImage(contentsOfFile: path) else { return nil }
        return base64(from: compress(raw))
    }
}

/// 本地 OCR：iOS 用 Vision，安卓用 ML Kit。两者都只是「预填可编辑文字」，
/// 识别不准时原图仍会发给视觉模型，所以这里不追求 100% 正确，只追求别把用户卡住。
enum OcrService {

    struct Result {
        let text: String
        let confidence: Double
    }

    /// 中英文混合识别。Vision 在后台线程跑，这里包成 async 供 SwiftUI 调用。
    static func recognize(image: UIImage) async -> Result {
        guard let cgImage = image.cgImage else { return Result(text: "", confidence: 0) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: Result(text: "", confidence: 0))
                        return
                    }
                    var lines: [String] = []
                    var total: Double = 0
                    var count = 0
                    for observation in observations {
                        guard let top = observation.topCandidates(1).first else { continue }
                        lines.append(top.string)
                        total += Double(top.confidence)
                        count += 1
                    }
                    let confidence = count > 0 ? total / Double(count) : 0
                    continuation.resume(
                        returning: Result(text: lines.joined(separator: "\n"), confidence: confidence)
                    )
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                // 只列中英两种：写多了会让 Vision 在标点与数字上乱猜
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: Result(text: "", confidence: 0))
                }
            }
        }
    }
}

/// 本地图片落盘，对齐安卓 `core/util/FileStorage`：拍照/相册统一拷进 App 沙盒，
/// 数据库里只存路径，导出备份时连图一起打包。
enum FileStorage {

    static var imagesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 把外部 URL（相册/相机临时文件）搬进沙盒，返回沙盒内地址；失败返回 nil。
    @discardableResult
    static func persist(imageAt source: URL) -> URL? {
        let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let name = "img_\(stamp).\(ext)"
        let target = imagesDirectory.appendingPathComponent(name)
        do {
            // 相册里的资源可能是只读的临时文件，必须先 copy 再删来源
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            // 拷不动就退一步：直接读数据重写一份
            guard let data = try? Data(contentsOf: source) else { return nil }
            return (try? data.write(to: target)) != nil ? target : nil
        }
    }

    static func deleteAllImages() {
        try? FileManager.default.removeItem(at: imagesDirectory)
    }

    static var totalImageBytes: Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + size
        }
    }
}
