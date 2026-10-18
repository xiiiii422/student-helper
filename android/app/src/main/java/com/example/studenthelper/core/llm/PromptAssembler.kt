package com.example.studenthelper.core.llm

/** 一条 OpenAI 格式消息（content 纯文本；多模态 parts 由 buildUserContent 生成）。 */
data class Msg(val role: String, val content: String)

/** 多模态 content 数组的元素（text 或 image_url data URL）。 */
data class ContentPart(val type: String, val text: String? = null, val imageUrl: String? = null)

/**
 * 纯函数消息组装器：选科 System Prompt、历史截断、作文/改写消息模板。
 * 不依赖 Android，可 JVM 单测。
 */
object PromptAssembler {

    const val DEFAULT_MAX_TURNS = 8

    fun chatMessages(
        subject: String,
        userText: String,
        history: List<Msg>,
        maxTurns: Int = DEFAULT_MAX_TURNS,
    ): List<Msg> {
        val system = Msg("system", requireNotNull(Prompts.SYSTEM_PROMPTS[subject]) { "unknown subject: $subject" })
        val trimmed = history.takeLast(maxTurns * 2)
        return listOf(system) + trimmed + Msg("user", userText)
    }

    fun compositionUserMessage(
        title: String,
        grade: String,
        content: String?,
        requirement: String?,
        imageCount: Int = 0,
    ): String {
        val body = content?.takeIf { it.isNotBlank() } ?: "（图片形式提交，请先识别图中作文内容）"
        val sb = StringBuilder()
        sb.append("作文标题：").append(title).append("\n年级：").append(grade).append("\n")
        if (!requirement.isNullOrBlank()) sb.append("题目要求：").append(requirement).append("\n")
        if (imageCount > 1) {
            sb.append("说明：作者共上传了 ").append(imageCount)
                .append(" 页手稿图片，按页码顺序排列，请通读全部页面后再批改，引用时注明第几页。\n")
        }
        sb.append("作文正文：\n").append(body)
        return sb.toString()
    }

    fun compositionMessages(
        title: String,
        grade: String,
        content: String?,
        requirement: String?,
        imageCount: Int = 0,
    ): List<Msg> = listOf(
        Msg("system", Prompts.COMPOSITION_PROMPT),
        Msg("user", compositionUserMessage(title, grade, content, requirement, imageCount)),
    )

    /** 段落改写。 */
    fun rewriteMessages(text: String): List<Msg> = listOf(
        Msg("system", Prompts.REWRITE_PROMPT),
        Msg("user", text),
    )

    /**
     * 多模态 user 消息的 content 数组：文字在前，图片按顺序在后（支持作文多页手稿）。
     * images 为空时返回空列表，调用方降级为纯文本 content。
     */
    fun buildUserContent(text: String, imagesBase64: List<String>): List<ContentPart> {
        if (imagesBase64.isEmpty()) return emptyList()
        return listOf(ContentPart("text", text, null)) +
            imagesBase64.map { ContentPart("image_url", null, "data:image/jpeg;base64,$it") }
    }

    /** 讲题温度求准确，改写求多样。 */
    fun temperatureFor(kind: Kind): Double = when (kind) {
        Kind.CHAT -> 0.3
        Kind.COMPOSITION -> 0.3
        Kind.REWRITE -> 0.7
    }

    enum class Kind { CHAT, COMPOSITION, REWRITE }
}
