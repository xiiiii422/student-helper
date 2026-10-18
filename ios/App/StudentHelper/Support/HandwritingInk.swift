import Foundation
import UIKit

// ML Kit 的模块名在 8.x / 9.x 之间调整过：9.x 起是独立的
// MLKitDigitalInkRecognition，老版本走 MLKit 伞模块。两种都兜住。
#if canImport(MLKitDigitalInkRecognition)
import MLKitDigitalInkRecognition
#elseif canImport(MLKit)
import MLKit
#endif

/// 一笔手写：点坐标 + 相对这一笔首点的时间（毫秒）。
/// ML Kit Digital Ink 需要时间戳来判断笔画顺序和停顿，纯坐标会丢掉这个信息。
struct InkStroke: Equatable {
    struct Point: Equatable {
        let x: CGFloat
        let y: CGFloat
        let t: Int
    }
    var points: [Point]
}

/// 离线手写识别（ML Kit Digital Ink）。
///
/// 为什么不继续用「把笔迹渲染成图片再交给 Vision」：
/// Vision 只有印刷体模型，中文手写基本认不出来；Digital Ink 吃的是笔迹坐标 + 时间，
/// 本来就是为手写设计的，中文（zh-Hani）和英文（en-US）都有官方模型。
///
/// 模型不打进包体：首次识别前下载一次（每个语言约 20MB 量级，仅在 Wi-Fi 下），之后完全离线。
enum HandwritingInk {

    struct Candidate: Identifiable, Equatable {
        let text: String
        let score: Float
        var id: String { text }
    }

    enum InkError: LocalizedError {
        case noModel
        case downloadFailed(String)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .noModel: return "这台设备不支持手写识别"
            case .downloadFailed(let m): return "手写模型没准备好：\(m)"
            case .emptyResult: return "没认出字来"
            }
        }
    }

    /// 识别顺序：先中文（汉字 + 数字都能覆盖），再英文（补拉丁字母）。
    static let languageTags = ["zh-Hani", "en-US"]

    private static let manager = ModelManager.modelManager()

    // MARK: 模型管理

    static func model(for tag: String) -> DigitalInkRecognitionModel? {
        guard let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: tag) else {
            return nil
        }
        return DigitalInkRecognitionModel(modelIdentifier: identifier)
    }

    static func isReady(tag: String) -> Bool {
        guard let m = model(for: tag) else { return false }
        return manager.isModelDownloaded(m)
    }

    /// 至少一个语言模型已就绪，手写板就可以直接用。
    static var anyReady: Bool {
        languageTags.contains { isReady(tag: $0) }
    }

    /// 保证模型可用；没下载就触发下载并轮询到完成。
    static func prepare(tag: String, timeout: TimeInterval = 120) async throws -> DigitalInkRecognitionModel {
        guard let m = model(for: tag) else { throw InkError.noModel }
        if manager.isModelDownloaded(m) { return m }

        manager.download(
            m,
            conditions: ModelDownloadConditions(
                allowsCellularAccess: false,
                allowsBackgroundDownloading: true
            )
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if manager.isModelDownloaded(m) { return m }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw InkError.downloadFailed("下载超时，检查 WiFi 后重试")
    }

    // MARK: 识别

    /// 交给指定语言模型识别，返回按分数倒序的候选。
    static func recognize(strokes: [InkStroke], tag: String) async throws -> [Candidate] {
        let m = try await prepare(tag: tag)
        let ink = Ink(strokes: strokes.compactMap { stroke -> Stroke? in
            let points = stroke.points.map {
                StrokePoint(x: Float($0.x), y: Float($0.y), t: $0.t)
            }
            guard points.count > 1 else { return nil }
            return Stroke(points: points)
        })
        guard !ink.strokes.isEmpty else { throw InkError.emptyResult }

        let options = DigitalInkRecognizerOptions(model: m)
        let recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognize(ink: ink) { result, error in
                if let error {
                    continuation.resume(throwing: InkError.downloadFailed(error.localizedDescription))
                    return
                }
                let candidates: [Candidate] = (result?.candidates ?? []).compactMap { c in
                    let text = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return Candidate(text: text, score: c.score?.floatValue ?? 0)
                }
                guard !candidates.isEmpty else {
                    continuation.resume(throwing: InkError.emptyResult)
                    return
                }
                continuation.resume(returning: candidates.sorted { $0.score > $1.score })
            }
        }
    }

    /// 两个语言模型都跑一遍再合并去重：中文模型认不出纯英文单词，英文模型认不出汉字。
    static func recognizeMerged(strokes: [InkStroke]) async -> [Candidate] {
        var merged: [Candidate] = []
        for tag in languageTags {
            guard isReady(tag: tag) || tag == languageTags.first else { continue }
            if let list = try? await recognize(strokes: strokes, tag: tag) {
                merged.append(contentsOf: list)
            }
        }
        var seen = Set<String>()
        return merged
            .sorted { $0.score > $1.score }
            .filter { seen.insert($0.text).inserted }
    }
}
