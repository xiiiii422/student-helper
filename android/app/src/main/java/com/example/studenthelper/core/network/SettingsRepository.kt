package com.example.studenthelper.core.network

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.example.studenthelper.BuildConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "settings")

/** 大模型供应商预设：切换后 base/model 自动覆盖，仅需保留对应 Key。 */
data class ProviderPreset(
    val id: String,
    val label: String,
    val baseUrl: String,
    val chatModel: String,
    val vlModel: String,
    val vlMaxTokens: Int,
    val chatMaxTokens: Int,
    /** 列表行右侧状态位用，全名（“智谱 GLM 免费”）塞不进去。 */
    val short: String = label,
    /**
     * 关掉“思考模式”。两家 flash 都是混合推理模型且默认开着思考，
     * 实测不关时 SSE 只吐 reasoning_content、content 全空，App 把它丢了就变成“问了没人答”几分钟。
     * 自定义服务无从推断参数是否兼容，一律不送。
     */
    val disableThinking: Boolean = false,
)

object Presets {
    val GLM = ProviderPreset(
        id = "glm", label = "智谱 GLM 免费", short = "智谱",
        baseUrl = "https://open.bigmodel.cn/api/paas/v4",
        chatModel = "glm-4.7-flash", vlModel = "glm-4v-flash",
        vlMaxTokens = 1024, chatMaxTokens = 4000,
        disableThinking = true,
    )
    val DEEPSEEK = ProviderPreset(
        id = "deepseek", label = "DeepSeek", short = "DeepSeek",
        baseUrl = "https://api.deepseek.com",
        chatModel = "deepseek-flash", vlModel = "deepseek-flash",
        vlMaxTokens = 4000, chatMaxTokens = 4000,
        disableThinking = true,
    )
    val ALL = listOf(GLM, DEEPSEEK)

    /** 给人看的供应商名（限流切换时要告诉学生现在换成谁了）。 */
    fun labelOf(id: String): String = ALL.firstOrNull { it.id == id }?.label ?: "当前服务"

    fun shortOf(id: String): String = ALL.firstOrNull { it.id == id }?.short ?: "当前"
}

/** 运行时直连大模型配置；缺省值来自 BuildConfig（编译期预埋）。 */
class SettingsRepository(private val context: Context) {

    private val keyProvider = stringPreferencesKey("provider")
    private val keyBaseUrl = stringPreferencesKey("api_base_url")
    private val keyApiKey = stringPreferencesKey("api_key")
    private val keyChatModel = stringPreferencesKey("chat_model")
    private val keyVlModel = stringPreferencesKey("vl_model")
    private val keyThemeMode = intPreferencesKey("theme_mode")   // 0 跟随系统 / 1 浅色 / 2 深色

    /** 外观模式：0 跟随系统，1 强制浅色，2 强制深色。 */
    val themeMode: Flow<Int> = context.dataStore.data.map { it[keyThemeMode] ?: 0 }

    suspend fun setThemeMode(mode: Int) {
        context.dataStore.edit { it[keyThemeMode] = mode }
    }

    val providerId: Flow<String> = context.dataStore.data
        .map { it[keyProvider] ?: BuildConfig.DEFAULT_PROVIDER }

    val apiBaseUrl: Flow<String> = context.dataStore.data
        .map { it[keyBaseUrl] ?: presetOf(it[keyProvider]).baseUrl }

    val apiKey: Flow<String> = context.dataStore.data
        .map { it[keyApiKey] ?: defaultKeyFor(it[keyProvider]) }

    val chatModel: Flow<String> = context.dataStore.data
        .map { it[keyChatModel] ?: presetOf(it[keyProvider]).chatModel }

    val vlModel: Flow<String> = context.dataStore.data
        .map { it[keyVlModel] ?: presetOf(it[keyProvider]).vlModel }

    private fun presetOf(providerId: String?): ProviderPreset =
        Presets.ALL.firstOrNull { it.id == providerId } ?: Presets.GLM

    private fun defaultKeyFor(providerId: String?): String = when (providerId ?: BuildConfig.DEFAULT_PROVIDER) {
        "deepseek" -> DEEPSEEK_KEY_FALLBACK
        else -> BuildConfig.DEFAULT_API_KEY
    }

    /**
     * 备用供应商：主家被限流时自动切过去。
     * 免费档的 RPM 限制不是退避几十秒能跨过去的，自用版唯一可靠的兜底就是第 2 家 Key。
     * 自定义配置无从推断 Key，返回 null。
     */
    fun fallbackFor(cfg: LlmConfig): LlmConfig? {
        val other = when (cfg.providerId) {
            "glm" -> Presets.DEEPSEEK
            "deepseek" -> Presets.GLM
            else -> return null
        }
        if (other.baseUrl.removeSuffix("/") == cfg.baseUrl) return null
        return LlmConfig(
            providerId = other.id,
            baseUrl = other.baseUrl,
            apiKey = defaultKeyFor(other.id),
            chatModel = other.chatModel,
            vlModel = other.vlModel,
            chatMaxTokens = other.chatMaxTokens,
            vlMaxTokens = other.vlMaxTokens,
            disableThinking = other.disableThinking,
        )
    }

    suspend fun current(): LlmConfig {
        val p = context.dataStore.data.first()
        val preset = presetOf(p[keyProvider])
        val pid = p[keyProvider] ?: preset.id
        return LlmConfig(
            providerId = pid,
            baseUrl = (p[keyBaseUrl] ?: preset.baseUrl).trim().removeSuffix("/"),
            apiKey = (p[keyApiKey] ?: defaultKeyFor(p[keyProvider])).trim(),
            chatModel = (p[keyChatModel] ?: preset.chatModel).trim(),
            vlModel = (p[keyVlModel] ?: preset.vlModel).trim(),
            chatMaxTokens = preset.chatMaxTokens,
            vlMaxTokens = preset.vlMaxTokens,
            disableThinking = preset.disableThinking && pid != "custom",
        )
    }

    /** 切换预设：base/model 跟着预设走，已手动改过的字段被覆盖。 */
    suspend fun applyPreset(preset: ProviderPreset) {
        context.dataStore.edit {
            it[keyProvider] = preset.id
            it[keyBaseUrl] = preset.baseUrl
            it[keyChatModel] = preset.chatModel
            it[keyVlModel] = preset.vlModel
        }
    }

    suspend fun setCustomConfig(baseUrl: String, apiKey: String, chatModel: String, vlModel: String) {
        context.dataStore.edit {
            it[keyProvider] = "custom"
            it[keyBaseUrl] = baseUrl.trim().removeSuffix("/")
            it[keyApiKey] = apiKey.trim()
            it[keyChatModel] = chatModel.trim()
            it[keyVlModel] = vlModel.trim()
        }
    }

    companion object {
        /**
         * DeepSeek Key（用户自备，切换预设时自动使用）。
         * 从 BuildConfig 来，而 BuildConfig 由不入库的 android/secrets.properties 注入；
         * 源码里再不留一份明文，否则推到 GitHub 就永久进 git 历史。
         */
        val DEEPSEEK_KEY_FALLBACK: String = BuildConfig.DEEPSEEK_API_KEY
    }
}

data class LlmConfig(
    val providerId: String,
    val baseUrl: String,
    val apiKey: String,
    val chatModel: String,
    val vlModel: String,
    val chatMaxTokens: Int,
    val vlMaxTokens: Int,
    /** true 时请求体里带 `thinking: {type: disabled}`，否则对端会先“想”几分钟不吐正文。 */
    val disableThinking: Boolean = false,
) {
    fun channel(hasImage: Boolean): Channel =
        if (hasImage) Channel(vlModel, vlMaxTokens) else Channel(chatModel, chatMaxTokens)

    data class Channel(val model: String, val maxTokens: Int)
}
