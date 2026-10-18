import Foundation
import Security
import SHCore

/// Keychain 读写（kClass = generic password，按 service+account 定位）。
///
/// 这是 iOS 相对安卓的一处实打实的改进：安卓把 API Key 硬编码进了源码，
/// iOS 侧 Key 只进 Keychain（FirstThisDeviceOnly，不随备份迁移），
/// 源码与 git 历史里都不出现明文 Key。
enum Keychain {
    static let service = "com.example.studenthelper"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 设置持久化：偏好走 UserDefaults，Key 走 Keychain。
/// 取值口径与安卓 SettingsRepository 完全一致（provider / base / model / themeMode）。
final class SettingsStore: SettingsProviding, @unchecked Sendable {

    private enum Key {
        static let provider = "provider"
        static let baseUrl = "api_base_url"
        static let chatModel = "chat_model"
        static let vlModel = "vl_model"
        static let themeMode = "theme_mode"
    }

    private let defaults: UserDefaults
    /// 编译期预埋的 Key（来自 Secrets.xcconfig → Info.plist），首次启动时写入 Keychain。
    private let bundledKeys: [String: String]

    init(
        defaults: UserDefaults = .standard,
        bundledKeys: [String: String] = SettingsStore.keysFromBundle()
    ) {
        self.defaults = defaults
        self.bundledKeys = bundledKeys
        seedKeysIntoKeychainIfNeeded()
    }

    static func keysFromBundle() -> [String: String] {
        let info = Bundle.main.infoDictionary
        var map: [String: String] = [:]
        if let glm = info?["GLMApiKey"] as? String, !glm.isEmpty { map["glm"] = glm }
        if let ds = info?["DeepSeekApiKey"] as? String, !ds.isEmpty { map["deepseek"] = ds }
        return map
    }

    private func seedKeysIntoKeychainIfNeeded() {
        for (provider, key) in bundledKeys where Keychain.read(account: "apikey." + provider) == nil {
            Keychain.write(key, account: "apikey." + provider)
        }
    }

    // MARK: Key

    func apiKey(for provider: String) -> String {
        Keychain.read(account: "apikey." + provider) ?? ""
    }

    func setApiKey(_ value: String, for provider: String) {
        if value.isEmpty { Keychain.delete(account: "apikey." + provider) }
        else { Keychain.write(value, account: "apikey." + provider) }
    }

    // MARK: 偏好

    var providerId: String {
        get {
            // 空串也算“没配”：Info.plist 里的 $(DEFAULT_PROVIDER) 在 CI 未传值时会被展开成 ""，
            // 而 `??` 只认 nil，会把 providerId 变成 ""，进而查不到 Key（装上看能打开、一提问就 401）。
            if let stored = defaults.string(forKey: Key.provider), !stored.isEmpty { return stored }
            if let bundled = Bundle.main.infoDictionary?["DefaultProvider"] as? String, !bundled.isEmpty {
                return bundled
            }
            return "glm"
        }
        set { defaults.set(newValue, forKey: Key.provider) }
    }

    var customBaseUrl: String? {
        get { defaults.string(forKey: Key.baseUrl) }
        set { defaults.set(newValue, forKey: Key.baseUrl) }
    }

    var customChatModel: String? {
        get { defaults.string(forKey: Key.chatModel) }
        set { defaults.set(newValue, forKey: Key.chatModel) }
    }

    var customVlModel: String? {
        get { defaults.string(forKey: Key.vlModel) }
        set { defaults.set(newValue, forKey: Key.vlModel) }
    }

    /// 0 跟随系统 / 1 浅色 / 2 深色
    var themeMode: Int {
        get { defaults.object(forKey: Key.themeMode) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Key.themeMode) }
    }

    // MARK: SettingsProviding

    func current() async -> LlmConfig {
        let id = providerId
        let preset = id == "custom" ? Presets.preset(of: nil) : Presets.preset(of: id)
        let base = (customBaseUrl ?? preset.baseUrl)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LlmConfig(
            providerId: id,
            baseUrl: trimTrailingSlash(base.isEmpty ? preset.baseUrl : base),
            apiKey: apiKey(for: id),
            chatModel: nonEmpty(customChatModel) ?? preset.chatModel,
            vlModel: nonEmpty(customVlModel) ?? preset.vlModel,
            chatMaxTokens: preset.chatMaxTokens,
            vlMaxTokens: preset.vlMaxTokens,
            // 自定义服务无从推断 thinking 参数是否兼容，一律不送
            disableThinking: id != "custom" && preset.disableThinking
        )
    }

    /// 备用供应商：主家被限流时自动切过去。自定义配置返回 nil。
    func fallback(for cfg: LlmConfig) async -> LlmConfig? {
        guard let preset = Presets.fallbackPreset(for: cfg) else { return nil }
        let key = apiKey(for: preset.id)
        guard !key.isEmpty else { return nil }
        return LlmConfig(
            providerId: preset.id,
            baseUrl: trimTrailingSlash(preset.baseUrl),
            apiKey: key,
            chatModel: preset.chatModel,
            vlModel: preset.vlModel,
            chatMaxTokens: preset.chatMaxTokens,
            vlMaxTokens: preset.vlMaxTokens,
            disableThinking: preset.disableThinking
        )
    }

    /// 切换预设：base/model 跟着预设走，已手动改过的字段被覆盖（与安卓 applyPreset 一致）。
    func applyPreset(_ preset: ProviderPreset) {
        providerId = preset.id
        customBaseUrl = preset.baseUrl
        customChatModel = preset.chatModel
        customVlModel = preset.vlModel
    }

    func setCustom(baseUrl: String, chatModel: String, vlModel: String, apiKey: String?) {
        providerId = "custom"
        customBaseUrl = trimTrailingSlash(baseUrl.trimmingCharacters(in: .whitespacesAndNewlines))
        customChatModel = chatModel.trimmingCharacters(in: .whitespacesAndNewlines)
        customVlModel = vlModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let apiKey, !apiKey.isEmpty { setApiKey(apiKey, for: "custom") }
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimTrailingSlash(_ url: String) -> String {
        var s = url
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
