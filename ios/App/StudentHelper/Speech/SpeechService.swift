import AVFoundation
import Combine
import SwiftUI

/// 讲稿朗读服务：把 AI 的回答用接近真人的语速、音色念出来。
///
/// 「像人」这件事靠三处细节，而不是靠换一个音色就完事：
/// 1. 先过 `SpeechText` 归一化 —— `\(\frac{7}{8}\)` 必须念成「八分之七」，不能念成反斜杠 frac
/// 2. 按句子切成一条条 utterance 排队 —— 长答案立刻开口，标点处自然换气
/// 3. 中文段用 zh-CN 音色、英文段用 en-US 音色 —— 英语题讲解是中文夹英文，
///    单一中文音色念 English 单词会明显发假
///
/// 额外利用 iOS 特性：优先挑系统里已下载的「高质量/增强」中文音色，
/// 并在朗读时把当前句子回传给气泡做高亮（类似系统「朗读屏幕」）。
@MainActor
final class SpeechService: NSObject, ObservableObject {

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    /// 当前正在念的那句，气泡用它做高亮；念完清空。
    @Published private(set) var spokenChunk: String?
    @Published private(set) var progress: (Int, Int)? = nil

    /// 语速：0.45 接近老师讲课的节奏（系统默认 0.5 偏快，0.35 又拖沓）。
    @Published var rate: Float {
        didSet { defaults.set(rate, forKey: Self.rateKey) }
    }
    /// 是否讲完自动朗读。关掉后仍可手动点气泡上的朗读按钮。
    @Published var autoSpeak: Bool {
        didSet { defaults.set(autoSpeak, forKey: Self.autoKey) }
    }
    /// 用户指定的音色 identifier；nil 表示自动挑最好的。
    @Published var preferredVoice: String? {
        didSet { defaults.set(preferredVoice, forKey: Self.voiceKey) }
    }

    private static let rateKey = "speech.rate"
    private static let autoKey = "speech.auto"
    private static let voiceKey = "speech.voice"

    private let synthesizer = AVSpeechSynthesizer()
    private let defaults: UserDefaults
    private var chunks: [SpeechText.Chunk] = []
    private var cursor = 0

    override init() {
        self.defaults = .standard
        self.rate = (defaults.object(forKey: Self.rateKey) as? Float) ?? 0.45
        self.autoSpeak = (defaults.object(forKey: Self.autoKey) as? Bool) ?? false
        self.preferredVoice = defaults.string(forKey: Self.voiceKey)
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - 可用音色（给设置页的 picker 用）

    /// 中英两种语言的可选音色，按质量从高到低排；系统没装增强音色时只剩默认款。
    nonisolated static func availableVoices() -> [AVSpeechSynthesisVoice] {
        let langs = ["zh-CN", "zh-CN", "en-US", "en-GB"]
        var seen = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { langs.contains($0.language) && seen.insert($0.identifier).inserted }
            .sorted { qualityRank($0) > qualityRank($1) }
    }

    nonisolated private static func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        if #available(iOS 17.0, *) {
            switch voice.quality {
            case .premium: return 4
            case .enhanced: return 3
            case .siri: return 2
            default: return 1
            }
        }
        return voice.language.hasPrefix("zh") ? 2 : 1
    }

    // MARK: - 播放控制

    func speak(_ text: String) {
        stop()
        let parsed = SpeechText.chunks(text)
        guard !parsed.isEmpty else { return }
        chunks = parsed
        cursor = 0
        speakCurrent()
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func togglePauseResume() {
        if isPaused { resume() } else if isSpeaking { pause() }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        chunks = []
        cursor = 0
        isSpeaking = false
        isPaused = false
        spokenChunk = nil
        progress = nil
    }

    private func speakCurrent() {
        guard cursor < chunks.count else {
            isSpeaking = false
            isPaused = false
            spokenChunk = nil
            progress = nil
            return
        }
        let chunk = chunks[cursor]
        let utterance = AVSpeechUtterance(string: chunk.text)
        utterance.rate = rate
        utterance.preUtteranceDelay = cursor == 0 ? 0 : 0.05
        // 句末停得久一点、逗号停得短一点，节奏才不像连读
        utterance.postUtteranceDelay = trailingPause(of: chunk.text)
        utterance.volume = 1.0
        if let voice = pickVoice(for: chunk.language) { utterance.voice = voice }
        isSpeaking = true
        isPaused = false
        spokenChunk = chunk.text
        progress = (cursor + 1, chunks.count)
        synthesizer.speak(utterance)
    }

    private func trailingPause(of text: String) -> Float {
        guard let last = text.last else { return 0.1 }
        switch last {
        case "。", "！", "？", "…": return 0.30
        case "；", "：": return 0.20
        case "，", "、", ",": return 0.10
        default: return 0.12
        }
    }

    private func pickVoice(for language: SpeechText.Language) -> AVSpeechSynthesisVoice? {
        let wanted = language == .chinese ? "zh-CN" : "en-US"
        if let id = preferredVoice, let v = AVSpeechSynthesisVoice(identifier: id),
           v.language.hasPrefix(String(wanted.prefix(2))) {
            return v
        }
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.replacingOccurrences(of: "_", with: "-").hasPrefix(wanted) }
        if #available(iOS 17.0, *) {
            if let best = candidates.max(by: { quality($0) > quality($1) }) { return best }
        }
        return candidates.first ?? AVSpeechSynthesisVoice(language: wanted)
    }

    @available(iOS 17.0, *)
    private func quality(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 4
        case .enhanced: return 3
        case .siri: return 2
        default: return 1
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // spokenAudio 模式会自动压低背景音乐，而不是直接停掉；.defaultToOutputs 让插耳机/外放切换正常
        try? session.setCategory(
            .playback, mode: .spokenAudio,
            options: [.duckOthers, .defaultToOutputs, .mixWithOthers]
        )
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cursor += 1
            self.speakCurrent()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.spokenChunk = nil
            self.progress = nil
        }
    }
}
