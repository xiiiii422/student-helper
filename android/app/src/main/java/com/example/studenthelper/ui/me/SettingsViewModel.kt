package com.example.studenthelper.ui.me

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studenthelper.core.network.LlmClient
import com.example.studenthelper.core.network.PingResult
import com.example.studenthelper.core.network.ProviderPreset
import com.example.studenthelper.core.network.SettingsRepository
import com.example.studenthelper.data.local.AppDatabase
import com.example.studenthelper.domain.usecase.BackupManager
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File

/** 可编辑的直连配置快照。 */
data class ApiConfigForm(
    val providerId: String = "glm",
    val baseUrl: String = "",
    val apiKey: String = "",
    val chatModel: String = "",
    val vlModel: String = "",
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settings: SettingsRepository,
    private val llm: LlmClient,
    private val backup: BackupManager,
    private val db: AppDatabase,
) : ViewModel() {

    private val _form = MutableStateFlow(ApiConfigForm())
    val form: StateFlow<ApiConfigForm> = _form.asStateFlow()

    val presets: List<ProviderPreset> = com.example.studenthelper.core.network.Presets.ALL

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    /** 导出成功后的文件，供 UI 分享。 */
    private val _exportedFile = MutableStateFlow<File?>(null)
    val exportedFile: StateFlow<File?> = _exportedFile.asStateFlow()

    private val _restartRequired = MutableStateFlow(false)
    val restartRequired: StateFlow<Boolean> = _restartRequired.asStateFlow()

    private val _pinging = MutableStateFlow(false)
    val pinging: StateFlow<Boolean> = _pinging.asStateFlow()

    /** 上一次连接测试的结果，常驻在“连接测试”行右侧；snackbar 几秒就没，看不出当前状态。 */
    private val _pingResults = MutableStateFlow<List<PingResult>>(emptyList())
    val pingResults: StateFlow<List<PingResult>> = _pingResults.asStateFlow()

    /** 外观模式：0 跟随系统 / 1 浅色 / 2 深色 */
    val themeMode: StateFlow<Int> = settings.themeMode
        .stateIn(viewModelScope, kotlinx.coroutines.flow.SharingStarted.Eagerly, 0)
    fun setThemeMode(mode: Int) {
        viewModelScope.launch { settings.setThemeMode(mode) }
    }

    init {
        viewModelScope.launch {
            val c = settings.current()
            _form.value = ApiConfigForm(c.providerId, c.baseUrl, c.apiKey, c.chatModel, c.vlModel)
        }
    }

    fun setBaseUrl(v: String) { _form.value = _form.value.copy(baseUrl = v) }
    fun setApiKey(v: String) { _form.value = _form.value.copy(apiKey = v) }
    fun setChatModel(v: String) { _form.value = _form.value.copy(chatModel = v) }
    fun setVlModel(v: String) { _form.value = _form.value.copy(vlModel = v) }

    fun selectPreset(preset: ProviderPreset) {
        viewModelScope.launch {
            settings.applyPreset(preset)
            val c = settings.current()
            // Key 跟随当前预设默认值（除非用户曾手动改过同供应商 Key）
            _form.value = ApiConfigForm(c.providerId, c.baseUrl, c.apiKey, c.chatModel, c.vlModel)
            _message.value = "已切换到 ${preset.label}"
        }
    }

    fun saveConfig() {
        viewModelScope.launch {
            val f = _form.value
            settings.setCustomConfig(f.baseUrl, f.apiKey, f.chatModel, f.vlModel)
            _message.value = "已保存模型服务配置"
        }
    }

    fun ping() {
        if (_pinging.value) return
        viewModelScope.launch {
            _pinging.value = true
            // 一家都测不通时不能只说“失败”：本机断网和供应商限流是两件完全不同的事
            val results = runCatching { llm.pingAll() }.getOrElse {
                listOf(PingResult("本机网络", false, it.describe()))
            }
            _pingResults.value = results
            _pinging.value = false
            _message.value = results.joinToString("；") { r ->
                if (r.ok) "${r.provider} 已连接（${r.detail}）" else "${r.provider} 失败：${r.detail}"
            }
        }
    }

    fun exportData() {
        viewModelScope.launch {
            runCatching { backup.exportZip() }
                .onSuccess {
                    _exportedFile.value = it
                    _message.value = "已导出：${it.name}"
                }
                .onFailure { _message.value = "导出失败：${it.message}" }
        }
    }

    fun importData(context: Context, uri: Uri) {
        viewModelScope.launch {
            val tmp = File(context.cacheDir, "import.zip")
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    tmp.outputStream().use { output -> input.copyTo(output) }
                } ?: error("无法读取文件")
                backup.importZip(tmp)
            }.onSuccess { ok ->
                _message.value = if (ok) "导入成功，请重启应用生效" else "导入失败：文件损坏"
                if (ok) _restartRequired.value = true
            }.onFailure { _message.value = "导入失败：${it.message}" }
            tmp.delete()
        }
    }

    fun clearAll() {
        viewModelScope.launch {
            backup.clearAll {
                db.messageDao().clearAll()
                db.compositionDao().clearAll()
                db.favoriteDao().clearAll()
            }
            _message.value = "已清空所有数据"
        }
    }

    fun consumeMessage() { _message.value = null }
    fun consumeExportedFile() { _exportedFile.value = null }
}

/** 很多 IO 异常（如 NetworkOnMainThreadException）message 为 null，只打 message 会只剩“失败：null”。 */
internal fun Throwable.describe(): String =
    message?.takeIf { it.isNotBlank() } ?: javaClass.simpleName
