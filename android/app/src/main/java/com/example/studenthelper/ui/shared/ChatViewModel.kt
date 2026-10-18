package com.example.studenthelper.ui.shared

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.core.util.BitmapUtils
import com.example.studenthelper.core.util.FileStorage
import com.example.studenthelper.data.local.entity.MessageEntity
import com.example.studenthelper.data.repository.ChatRepository
import com.example.studenthelper.data.repository.FavoriteRepository
import com.example.studenthelper.domain.ocr.OcrResult
import com.example.studenthelper.domain.ocr.OcrRouter
import com.example.studenthelper.ui.components.SendMode
import dagger.hilt.android.lifecycle.HiltViewModel
import java.io.File
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

/** 拍照/手写后、发送前的待确认状态。 */
data class PendingOcr(
    val imageUri: String,
    val text: String,
    val confidence: Float,
    val suggestedMode: SendMode,
    val imageBase64: String,
)

@HiltViewModel
class ChatViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val chatRepo: ChatRepository,
    private val favoriteRepo: FavoriteRepository,
    private val ocrRouter: OcrRouter,
    private val fileStorage: FileStorage,
) : ViewModel() {

    val subject: Subject = Subject.fromRoute(
        savedStateHandle.get<String>("subject") ?: "math"
    ) ?: Subject.MATH

    private val _messages = MutableStateFlow<List<MessageEntity>>(emptyList())
    val messages: StateFlow<List<MessageEntity>> = _messages.asStateFlow()

    private val _streaming = MutableStateFlow(false)
    val streaming: StateFlow<Boolean> = _streaming.asStateFlow()

    private val _liveAssistantText = MutableStateFlow<String?>(null)
    val liveAssistantText: StateFlow<String?> = _liveAssistantText.asStateFlow()

    /**
     * 等待期状态提示（“模型服务繁忙，正在重试 2/4”）。
     * 上游退避重试最长可达近一分钟，只有三个跳动的点会被当成卡死，所以把重试次数透到 UI。
     */
    private val _statusHint = MutableStateFlow<String?>(null)
    val statusHint: StateFlow<String?> = _statusHint.asStateFlow()

    private val _pendingOcr = MutableStateFlow<PendingOcr?>(null)
    val pendingOcr: StateFlow<PendingOcr?> = _pendingOcr.asStateFlow()

    private val _ocrWorking = MutableStateFlow(false)
    val ocrWorking: StateFlow<Boolean> = _ocrWorking.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    /**
     * 发送失败时常驻对话流里的错误（snackbar 几秒就消失，学生抬头时已看不到）。
     * 只由下一次发送/重试成功清除。
     */
    private val _sendFailure = MutableStateFlow<String?>(null)
    val sendFailure: StateFlow<String?> = _sendFailure.asStateFlow()

    /** 本学科已被收藏的 assistant 消息 id 集，驱动星星图标态。 */
    private val _favoritedIds = MutableStateFlow<Set<Long>>(emptySet())
    val favoritedIds: StateFlow<Set<Long>> = _favoritedIds.asStateFlow()

    init {
        viewModelScope.launch {
            // 先清理上次进程被杀遗留的流式占位，再订阅历史
            runCatching { chatRepo.cleanupStale(subject) }
            chatRepo.observeMessages(subject)
                .catch { _error.value = "读取历史失败: ${it.message}" }
                .collect { list ->
                    // 若正在流式，隐藏 DB 里那条空的 streaming 占位（用 liveAssistantText 覆盖）
                    _messages.value = list
                }
        }
        viewModelScope.launch {
            runCatching { _favoritedIds.value = favoriteRepo.favoritedMessageIds(subject) }
        }
    }

    /** 用户直接键入文字发送。 */
    fun sendText(text: String) {
        if (text.isBlank()) return
        launchSend(userText = text, imageUri = null, imageBase64 = null, confidence = null)
    }

    /**
     * 处理一张已保存到本地的图片文件：加载 → OCR 路由 → 弹出确认。
     * @param file imagesDir 下已存在的文件
     */
    fun processImageFile(file: File) {
        if (_ocrWorking.value) return
        _ocrWorking.value = true
        viewModelScope.launch {
            try {
                val bitmap = BitmapUtils.loadCompressed(file)
                val base64 = BitmapUtils.toBase64(bitmap)
                val result = ocrRouter.process(bitmap, subject)
                val pending = when (result) {
                    is OcrResult.TextOnly -> PendingOcr(
                        imageUri = file.absolutePath, text = result.text,
                        confidence = result.confidence, suggestedMode = SendMode.TEXT_ONLY,
                        imageBase64 = base64,
                    )
                    is OcrResult.TextWithImageFallback -> PendingOcr(
                        imageUri = file.absolutePath, text = result.text,
                        confidence = result.confidence, suggestedMode = SendMode.TEXT_AND_IMAGE,
                        imageBase64 = base64,
                    )
                    is OcrResult.ImageOnly -> PendingOcr(
                        imageUri = file.absolutePath, text = result.partialText,
                        confidence = result.confidence, suggestedMode = SendMode.TEXT_AND_IMAGE,
                        imageBase64 = base64,
                    )
                }
                _pendingOcr.value = pending
            } catch (e: Exception) {
                _error.value = "识别失败: ${e.message}"
            } finally {
                _ocrWorking.value = false
            }
        }
    }

    /** 重新识别当前待确认图片。 */
    fun reRecognizePending() {
        val current = _pendingOcr.value ?: return
        val file = File(current.imageUri)
        if (file.exists()) processImageFile(file)
    }

    fun dismissPendingOcr() {
        _pendingOcr.value = null
    }

    /** 确认发送（来自 OCR 对话框）。 */
    fun confirmPendingSend(text: String, mode: SendMode) {
        val pending = _pendingOcr.value ?: return
        val sendBase64 = if (mode == SendMode.TEXT_AND_IMAGE) pending.imageBase64 else null
        launchSend(
            userText = text,
            imageUri = pending.imageUri,
            imageBase64 = sendBase64,
            confidence = pending.confidence,
        )
        _pendingOcr.value = null
    }

    private fun launchSend(userText: String, imageUri: String?, imageBase64: String?, confidence: Float?) {
        if ((userText.isBlank() && imageBase64 == null) || _streaming.value) return
        _streaming.value = true
        _liveAssistantText.value = ""
        _sendFailure.value = null
        viewModelScope.launch {
            try {
                chatRepo.sendAndStream(
                    subject = subject,
                    userText = userText,
                    imageUri = imageUri,
                    imageBase64 = imageBase64,
                    ocrConfidence = confidence,
                    onRetry = { attempt, max -> _statusHint.value = "模型服务繁忙，正在重试（$attempt/$max）" },
                    onFallback = { label -> _statusHint.value = "当前供应商限流，已切换到$label" },
                    onDelta = { acc ->
                        if (_statusHint.value != null) _statusHint.value = null
                        _liveAssistantText.value = acc
                    },
                )
            } catch (e: Exception) {
                _sendFailure.value = friendlyError(e.message) ?: "回答失败，请重试"
            } finally {
                _streaming.value = false
                _liveAssistantText.value = null
                _statusHint.value = null
            }
        }
    }

    /** 重试最近一次提问（删残句重新生成）。 */
    fun retryLast() {
        if (_streaming.value) return
        _streaming.value = true
        _liveAssistantText.value = ""
        _sendFailure.value = null
        viewModelScope.launch {
            try {
                chatRepo.retryLast(
                    subject = subject,
                    onRetry = { attempt, max -> _statusHint.value = "模型服务繁忙，正在重试（$attempt/$max）" },
                    onFallback = { label -> _statusHint.value = "当前供应商限流，已切换到$label" },
                    onDelta = { acc ->
                        if (_statusHint.value != null) _statusHint.value = null
                        _liveAssistantText.value = acc
                    },
                )
            } catch (e: Exception) {
                _sendFailure.value = friendlyError(e.message) ?: "重试失败"
            } finally {
                _streaming.value = false
                _liveAssistantText.value = null
                _statusHint.value = null
            }
        }
    }

    fun toggleFavorite(messageId: Long) {
        viewModelScope.launch {
            runCatching { favoriteRepo.toggle(messageId, subject) }
                .onSuccess { fav ->
                    _favoritedIds.value =
                        if (fav) _favoritedIds.value + messageId
                        else _favoritedIds.value - messageId
                }
                .onFailure { _error.value = it.message }
        }
    }

    /** 长按删除单条消息。 */
    fun deleteMessage(messageId: Long) {
        viewModelScope.launch {
            runCatching { chatRepo.deleteMessage(messageId) }
                .onFailure { _error.value = it.message }
        }
    }

    fun clearHistory() {
        _sendFailure.value = null
        viewModelScope.launch { runCatching { chatRepo.clearSubject(subject) } }
    }

    fun consumeError() { _error.value = null }

    companion object {
        /** 把技术错误翻译成小学生能懂的行动提示。 */
        fun friendlyError(msg: String?): String? {
            if (msg == null) return "网络异常，请重试"
            return when {
                msg.contains("401") || msg.contains("403") ||
                    msg.contains("auth", true) || msg.contains("Api Key", true) ||
                    msg.contains("API key", true) ->
                    "模型身份验证失败，请到“模型服务设置”检查 API Key"
                msg.contains("繁忙") || msg.contains("429") ||
                    msg.contains("1302") || msg.contains("1305") || msg.contains("速率") ->
                    "模型服务当前繁忙（两家都已试过），点“重试”或稍后再试"
                msg.contains("超时") || msg.contains("timeout", true) ->
                    "响应超时，点“重试”再试一次"
                msg.contains("Unable to resolve host") || msg.contains("Failed to connect") ||
                    msg.contains("network", true) ->
                    "网络连接失败，检查手机是否联网后重试"
                else -> msg
            }
        }
    }
}
