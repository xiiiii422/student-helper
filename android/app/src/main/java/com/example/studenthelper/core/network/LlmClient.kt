package com.example.studenthelper.core.network

import android.util.Log
import com.example.studenthelper.core.llm.ContentPart
import com.example.studenthelper.core.llm.Msg
import com.example.studenthelper.core.llm.PromptAssembler
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import kotlinx.serialization.json.addJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

private val JSON_MT = "application/json; charset=utf-8".toMediaType()
private const val TAG = "LlmClient"
private val RETRY_CODES = setOf(429, 500, 502, 503, 504)
/**
 * 主家只给两次机会：免费档的 1305 不是退避几次能跨过去的，死磕不如换人。
 * 两家合计四次尝试，与之前主家四次 + 备用两次的总量持平，但失败到切换快得多。
 */
private const val MAX_RETRIES = 2
/** 备用供应商只给两次机会：主家都限流了，备用大概率也忙，不要让学生等太久。 */
private const val FALLBACK_RETRIES = 2
/**
 * 单次尝试等首个字词的上限。
 * 对端过载时会先接受请求、持续发 keepalive，连接不断但正文一行没有，
 * readTimeout 永远不触发（真机实测挂 200s+）；只能拿墙钟自己卡。
 */
private const val FIRST_TOKEN_BUDGET_MS = 40_000L

/**
 * 直连 OpenAI 兼容接口（智谱 GLM / DeepSeek）。
 * - 带图自动切 VL 通道（glm-4v-flash 上限 1024；deepseek-flash 图文同模型）
 * - 只转发 delta.content；两家 flash 默认开思考，靠 [LlmConfig.disableThinking] 直接关掉，
 *   否则对端几分钟只吐 reasoning_content，正文一行没有，学生面对的就是一直跳的三个点
 * - 429/5xx/上游拥塞自动指数退避重试（未吐字前才重试，避免重复内容）
 *   重试对用户不能是静默的：每次退避前通过 [onRetry] 通报第几次尝试，UI 才能显示“正在重试”
 * - 免费档限流（GLM 429/1302）靠退避跨不过去，改切另一家 Key 继续（[SettingsRepository.fallbackFor]）
 */
@Singleton
class LlmClient @Inject constructor(
    private val settings: SettingsRepository,
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        // 60s：思考关掉后正文是一直接着来的，真断流就是死了；之前给到 180s 让一次卡住能挂三分钟
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    // ───────────────────── 公开接口 ─────────────────────

    /** 带图单题讲解（拍照/手写）：内部转成图片列表。 */
    fun chatStream(
        subject: String,
        userText: String,
        history: List<Msg>,
        imageBase64: String?,
        onRetry: ((attempt: Int, max: Int) -> Unit)? = null,
        onFallback: ((providerLabel: String) -> Unit)? = null,
    ): Flow<String> =
        chatStreamMulti(subject, userText, history, listOfNotNull(imageBase64), onRetry, onFallback)

    /** 学科讲解（支持多图），流式增量文本。 */
    fun chatStreamMulti(
        subject: String,
        userText: String,
        history: List<Msg>,
        imagesBase64: List<String>,
        onRetry: ((attempt: Int, max: Int) -> Unit)? = null,
        onFallback: ((providerLabel: String) -> Unit)? = null,
    ): Flow<String> = flow {
        val cfg = settings.current()
        val msgs = PromptAssembler.chatMessages(subject, userText, history)
        val hasImage = imagesBase64.isNotEmpty()
        val temperature = PromptAssembler.temperatureFor(PromptAssembler.Kind.CHAT)
        runStream(
            cfg = cfg,
            fallback = settings.fallbackFor(cfg),
            bodyFor = { c -> buildBody(c.channel(hasImage), temperature, msgs, imagesBase64, stream = true, disableThinking = c.disableThinking) },
            onRetry = onRetry,
            onFallback = onFallback,
        ) { emit(it) }
    }.flowOn(Dispatchers.IO)

    /** 作文批改：累积完整回复（应为 JSON 文本）。支持最多 4 页手稿图。 */
    suspend fun completeComposition(
        title: String,
        grade: String,
        content: String?,
        requirement: String?,
        imagesBase64: List<String>,
    ): String {
        val cfg = settings.current()
        val msgs = PromptAssembler.compositionMessages(title, grade, content, requirement, imageCount = imagesBase64.size)
        val hasImage = imagesBase64.isNotEmpty()
        val temperature = PromptAssembler.temperatureFor(PromptAssembler.Kind.COMPOSITION)
        val sb = StringBuilder()
        runStream(cfg, settings.fallbackFor(cfg), { c ->
            buildBody(c.channel(hasImage), temperature, msgs, imagesBase64, stream = true, disableThinking = c.disableThinking)
        }, null, null) { sb.append(it) }
        return sb.toString()
    }

    /** 段落改写。 */
    suspend fun completeRewrite(text: String): String {
        val cfg = settings.current()
        val msgs = PromptAssembler.rewriteMessages(text)
        val temperature = PromptAssembler.temperatureFor(PromptAssembler.Kind.REWRITE)
        val sb = StringBuilder()
        runStream(cfg, settings.fallbackFor(cfg), { c ->
            buildBody(c.channel(false), temperature, msgs, emptyList(), stream = true, disableThinking = c.disableThinking)
        }, null, null) { sb.append(it) }
        return sb.toString()
    }

    /** 连通性检查：发一个 8-token 小请求，成功返回模型名。 */
    suspend fun ping(): String = pingWith(settings.current())

    /**
     * 主/备两家现在都在回答链路里，只测主家会把“主家限流、备用其实通”误报成“服务坏了”。
     * 并发分别测，两家各自给一个结果。
     */
    suspend fun pingAll(): List<PingResult> = coroutineScope {
        val cfg = settings.current()
        listOf(cfg, settings.fallbackFor(cfg)).filterNotNull().map { c ->
            async(Dispatchers.IO) {
                val name = Presets.shortOf(c.providerId)
                runCatching { pingWith(c) }.fold(
                    onSuccess = { PingResult(name, true, it) },
                    onFailure = { PingResult(name, false, pingDetail(it)) },
                )
            }
        }.map { it.await() }
    }

    private suspend fun pingWith(cfg: LlmConfig): String = withContext(Dispatchers.IO) {
        val msgs = listOf(Msg("user", "你好"))
        val channel = cfg.channel(false)
        val body = buildBody(
            channel = channel,
            temperature = 0.0,
            messages = msgs,
            imagesBase64 = emptyList(),
            stream = false,
            maxTokensOverride = 8,
            disableThinking = cfg.disableThinking,
        )
        val request = baseRequest(cfg).post(body.toString().toRequestBody(JSON_MT)).build()
        client.newCall(request).execute().use { resp ->
            val text = resp.body?.string() ?: ""
            if (!resp.isSuccessful) throw IllegalStateException("HTTP ${resp.code}: ${text.take(120)}")
            val model = runCatching { AppJson.parseToJsonElement(text).jsonObjectString("model") }.getOrNull()
            model ?: channel.model
        }
    }

    // ───────────────────── 内部实现 ─────────────────────

    private fun baseRequest(cfg: LlmConfig) = Request.Builder()
        .url(cfg.baseUrl + "/chat/completions")
        .addHeader("Authorization", "Bearer " + cfg.apiKey)
        .addHeader("Content-Type", "application/json")

    /**
     * 先走主供应商，耗尽后若判定为“限流”且已吐字之前，切到备用 Key 再来一轮。
     * bodyFor 按配置重建：切了供应商必须换 model / max_tokens，否则对端直接 400。
     */
    private suspend fun runStream(
        cfg: LlmConfig,
        fallback: LlmConfig?,
        bodyFor: (LlmConfig) -> kotlinx.serialization.json.JsonObject,
        onRetry: ((attempt: Int, max: Int) -> Unit)? = null,
        onFallback: ((providerLabel: String) -> Unit)? = null,
        onDelta: suspend (String) -> Unit,
    ) {
        // 已吐字就不能重发，否则学生看到重复段落；用数组在两个 drain 间传递
        val emitted = booleanArrayOf(false)
        try {
            drain(cfg, bodyFor(cfg), MAX_RETRIES, onRetry, emitted, onDelta)
        } catch (e: Exception) {
            val canSwitch = fallback != null && !emitted[0] && isRateLimited(e.message.orEmpty())
            if (!canSwitch) throw e
            // 自用版没有服务端日志，出问题时 logcat 是唯一线索：为什么切、切到哪家要留下
            Log.w(TAG, "${cfg.providerId} 限流，切到 ${fallback.providerId} 继续：${e.message}")
            onFallback?.invoke(Presets.labelOf(fallback.providerId))
            drain(fallback, bodyFor(fallback), FALLBACK_RETRIES, onRetry, emitted, onDelta)
        }
    }

    /** 单一供应商的重试窗口：成功则返回，次数耗尽则抛。 */
    private suspend fun drain(
        cfg: LlmConfig,
        bodyJson: kotlinx.serialization.json.JsonObject,
        maxAttempts: Int,
        onRetry: ((attempt: Int, max: Int) -> Unit)?,
        emitted: BooleanArray,
        onDelta: suspend (String) -> Unit,
    ) {
        val request = baseRequest(cfg).post(bodyJson.toString().toRequestBody(JSON_MT)).build()
        var lastError = ""
        for (attempt in 1..maxAttempts) {
            var done = false
            var needRetry = false
            val attemptStart = System.currentTimeMillis()
            try {
                client.newCall(request).execute().use { resp ->
                    if (!resp.isSuccessful) {
                        val text = runCatching { resp.body?.string() }.getOrNull().orEmpty()
                        lastError = "HTTP ${resp.code} ${text.take(120)}"
                        needRetry = resp.code in RETRY_CODES && !emitted[0]
                    } else {
                        val reader = resp.body!!.source().inputStream().bufferedReader()
                        while (true) {
                            // keepalive 会不断重置 socket 读超时，所以“连上了但不出字”必须单独卡
                            if (!emitted[0] && System.currentTimeMillis() - attemptStart > FIRST_TOKEN_BUDGET_MS) {
                                lastError = "${FIRST_TOKEN_BUDGET_MS / 1000}s 内没等到首个字词"
                                needRetry = true
                                break
                            }
                            val line = reader.readLine() ?: break
                            if (!line.startsWith("data:")) continue
                            val d = line.substring(5).trim()
                            if (d == "[DONE]") { done = true; break }
                            val chunk = runCatching {
                                AppJson.decodeFromString(SseChunk.serializer(), d)
                            }.getOrNull() ?: continue
                            chunk.error?.let { errEle ->
                                val errText = errEle.toString()
                                lastError = errText.take(160)
                                if (isBusy(errText) && !emitted[0]) { needRetry = true }
                                else throw IllegalStateException("模型返回错误：$lastError")
                            }
                            if (needRetry) break
                            val delta = chunk.choices.firstOrNull()?.delta?.content
                            if (!delta.isNullOrEmpty()) {
                                emitted[0] = true
                                onDelta(delta)
                            }
                        }
                        if (!done && !needRetry && !emitted[0]) needRetry = true
                    }
                }
            } catch (e: IllegalStateException) {
                throw e
            } catch (e: Exception) {
                if (emitted[0]) throw e
                lastError = "${e.javaClass.simpleName}: ${e.message.orEmpty()}".trim()
                needRetry = true
            }
            if (done) return
            if (needRetry && attempt < maxAttempts) {
                Log.w(TAG, "${cfg.providerId} 第 $attempt/$maxAttempts 次失败：$lastError")
                // 退避最长 15s，累计可接近一分钟不吐字；不报进度用户只会以为卡死
                onRetry?.invoke(attempt + 1, maxAttempts)
                delay(minOf((1L shl attempt) * 1000L, 15_000L))
                continue
            }
            if (needRetry) throw IllegalStateException("模型服务繁忙（$lastError），请稍后重试")
            throw IllegalStateException(lastError.ifBlank { "响应提前结束，请重试" })
        }
    }

    private fun buildBody(
        channel: LlmConfig.Channel,
        temperature: Double,
        messages: List<Msg>,
        imagesBase64: List<String>,
        stream: Boolean,
        maxTokensOverride: Int? = null,
        disableThinking: Boolean = false,
    ) = buildJsonObject {
        put("model", channel.model)
        put("stream", stream)
        put("temperature", temperature)
        put("max_tokens", maxTokensOverride ?: channel.maxTokens)
        // 混合推理模型（glm-4.x-flash / deepseek-flash）默认 thinking=enabled，
        // 不关掉就只得着 reasoning_content；两家连 VL 通道都接受这个字段（实测 200）
        if (disableThinking) putJsonObject("thinking") { put("type", "disabled") }
        val parts = PromptAssembler.buildUserContent(messages.last().content, imagesBase64)
        putJsonArray("messages") {
            messages.forEachIndexed { i, m ->
                addJsonObject {
                    put("role", m.role)
                    if (i == messages.lastIndex && parts.isNotEmpty() && m.role == "user") {
                        putJsonArray("content") {
                            parts.forEach { p ->
                                addJsonObject {
                                    put("type", p.type)
                                    p.text?.let { put("text", it) }
                                    p.imageUrl?.let { url ->
                                        put("image_url", buildJsonObject { put("url", url) })
                                    }
                                }
                            }
                        }
                    } else {
                        put("content", m.content)
                    }
                }
            }
        }
    }

    private fun isBusy(errText: String): Boolean =
        errText.contains("1302") || errText.contains("1305") || errText.contains("拥塞") ||
            errText.contains("速率") || errText.contains("稍后再试") ||
            errText.contains("rate limit", ignoreCase = true) || errText.contains("429")

    /** 只有“对端限流”值得换供应商；鉴权/余额/断网 切了也一样错。 */
    private fun isRateLimited(message: String): Boolean =
        message.contains("429") || message.contains("Too Many", ignoreCase = true) ||
            isBusy(message)

    /** 上游回的是 JSON，塞进 snackbar 里学生读不懂；压成一个词，原文进 logcat。 */
    private fun pingDetail(t: Throwable): String {
        val raw = t.message?.takeIf(String::isNotBlank) ?: t.javaClass.simpleName
        Log.w(TAG, "ping 失败：$raw")
        return when {
            raw.contains("1302") || raw.contains("1305") || raw.contains("429") ||
                raw.contains("访问量过大") || raw.contains("速率") || raw.contains("拥塞") -> "限流中"
            raw.contains("401") || raw.contains("1002") || raw.contains("apikey", true) ||
                raw.contains("auth", true) -> "Key 无效"
            raw.contains("403") || raw.contains("余额") || raw.contains("insufficient", true) -> "无权限/欠费"
            raw.contains("timeout", true) -> "响应超时"
            raw.contains("Unable to resolve") || raw.contains("Failed to connect") ||
                raw.contains("network", true) -> "本机无网络"
            else -> raw.take(24)
        }
    }

    @Serializable
    private data class SseChunk(
        val choices: List<SseChoice> = emptyList(),
        val error: JsonElement? = null,
    )

    @Serializable
    private data class SseChoice(val delta: SseDelta? = null)

    @Serializable
    private data class SseDelta(val content: String? = null)
}

/** 一家供应商的连通性结果：[detail] 成功时是模型名，失败时是原因。 */
data class PingResult(val provider: String, val ok: Boolean, val detail: String)

private fun JsonElement.jsonObjectString(key: String): String? =
    (this as? kotlinx.serialization.json.JsonObject)?.get(key)?.toString()?.trim('"')
