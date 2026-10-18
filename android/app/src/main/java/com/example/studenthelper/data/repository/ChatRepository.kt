package com.example.studenthelper.data.repository

import com.example.studenthelper.core.common.DispatcherProvider
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.core.llm.Msg
import com.example.studenthelper.core.network.LlmClient
import com.example.studenthelper.core.util.BitmapUtils
import com.example.studenthelper.data.local.dao.MessageDao
import com.example.studenthelper.data.local.entity.MessageEntity
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

@Singleton
class ChatRepository @Inject constructor(
    private val messageDao: MessageDao,
    private val llm: LlmClient,
    private val dispatchers: DispatcherProvider,
) {
    fun observeMessages(subject: Subject): Flow<List<MessageEntity>> =
        messageDao.observeBySubject(subject.apiValue)

    suspend fun clearSubject(subject: Subject) = withContext(dispatchers.io) {
        messageDao.clearSubject(subject.apiValue)
    }

    /** 启动时清理流式中断残留：删空占位、把未定稿消息收尾。 */
    suspend fun cleanupStale(subject: Subject) = withContext(dispatchers.io) {
        messageDao.deleteEmptyStreamingPlaceholders(subject.apiValue)
        messageDao.finalizeStaleStreaming(subject.apiValue)
    }

    /** 长按删除单条消息（收藏行随外键级联移除）。 */
    suspend fun deleteMessage(id: Long) = withContext(dispatchers.io) {
        messageDao.deleteById(id)
    }

    /**
     * 发送一条用户消息并流式接收 AI 回复。
     * onDelta 回调已累计文本（内存打字机）；onRetry 在服务端退避重试前通报进度；
     * Room 按 [FLUSH_INTERVAL_MS] 节流落盘；异常/断网在 finally 定稿部分回答，不留僵尸占位。
     */
    suspend fun sendAndStream(
        subject: Subject,
        userText: String,
        imageUri: String?,
        imageBase64: String?,
        ocrConfidence: Float?,
        onRetry: ((attempt: Int, max: Int) -> Unit)? = null,
        onFallback: ((providerLabel: String) -> Unit)? = null,
        onDelta: (accumulated: String) -> Unit,
    ): Long = withContext(dispatchers.io) {
        messageDao.insert(
            MessageEntity(
                subject = subject.apiValue,
                role = "user",
                textContent = userText,
                imageUri = imageUri,
                ocrConfidence = ocrConfidence,
            )
        )
        val recent = messageDao.getRecent(subject.apiValue, 16).reversed()
        val history = recent.dropLast(1).map { Msg(it.role, it.textContent) }
        streamInto(subject, userText, imageUri, imageBase64, history, onRetry, onFallback, onDelta)
    }

    /**
     * 重试最近一次提问：删除该提问之后的 AI 残句，重新流式生成。
     * 找不到用户消息返回 null。
     */
    suspend fun retryLast(
        subject: Subject,
        onRetry: ((attempt: Int, max: Int) -> Unit)? = null,
        onFallback: ((providerLabel: String) -> Unit)? = null,
        onDelta: (accumulated: String) -> Unit,
    ): Long? = withContext(dispatchers.io) {
        val recent = messageDao.getRecent(subject.apiValue, 10).reversed() // 旧→新
        val lastUserIdx = recent.indexOfLast { it.role == "user" }
        if (lastUserIdx < 0) return@withContext null
        val lastUser = recent[lastUserIdx]

        // 删除该提问之后的 assistant 残句
        for (i in (lastUserIdx + 1) until recent.size) {
            if (recent[i].role == "assistant") messageDao.deleteById(recent[i].id)
        }

        val history = recent.subList(maxOf(0, lastUserIdx - 16), lastUserIdx)
            .map { Msg(it.role, it.textContent) }

        // 图片消息重试时从本地文件重新编码
        val imageBase64 = lastUser.imageUri?.let { path ->
            runCatching {
                val f = File(path)
                if (f.exists()) BitmapUtils.toBase64(BitmapUtils.loadCompressed(f)) else null
            }.getOrNull()
        }

        streamInto(subject, lastUser.textContent, lastUser.imageUri, imageBase64, history, onRetry, onFallback, onDelta)
    }

    /** 流式核心：占位 → 收流（节流落盘）→ finally 定稿。 */
    private suspend fun streamInto(
        subject: Subject,
        userText: String,
        imageUri: String?,
        imageBase64: String?,
        history: List<Msg>,
        onRetry: ((attempt: Int, max: Int) -> Unit)?,
        onFallback: ((providerLabel: String) -> Unit)?,
        onDelta: (accumulated: String) -> Unit,
    ): Long {
        val assistantId = messageDao.insert(
            MessageEntity(
                subject = subject.apiValue,
                role = "assistant",
                textContent = "",
                isStreaming = true,
            )
        )
        val sb = StringBuilder()
        var lastFlushAt = 0L
        var streamError: String? = null
        try {
            llm.chatStream(
                subject = subject.apiValue,
                userText = userText,
                history = history,
                imageBase64 = imageBase64,
                onRetry = onRetry,
                onFallback = onFallback,
            ).collect { delta ->
                sb.append(delta)
                onDelta(sb.toString())
                val now = System.currentTimeMillis()
                if (now - lastFlushAt >= FLUSH_INTERVAL_MS) {
                    lastFlushAt = now
                    messageDao.update(
                        MessageEntity(
                            id = assistantId, subject = subject.apiValue, role = "assistant",
                            textContent = sb.toString(), isStreaming = true,
                        )
                    )
                }
            }
        } catch (e: Exception) {
            streamError = e.message
        } finally {
            if (sb.isEmpty()) {
                messageDao.deleteById(assistantId)
            } else {
                messageDao.update(
                    MessageEntity(
                        id = assistantId, subject = subject.apiValue, role = "assistant",
                        textContent = sb.toString(), isStreaming = false,
                    )
                )
            }
        }
        streamError?.let { throw RuntimeException(it) }
        return assistantId
    }

    companion object {
        /** Room 落盘最小间隔（毫秒） */
        private const val FLUSH_INTERVAL_MS = 300L
    }
}
