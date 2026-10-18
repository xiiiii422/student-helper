package com.example.studenthelper.domain.composition

import com.example.studenthelper.core.network.AppJson
import com.example.studenthelper.core.network.dto.CompositionFeedbackDto

/** 把后端存的 raw 文本安全解析为 [CompositionFeedbackDto]；失败返回 null。 */
object FeedbackParser {

    fun parse(raw: String): CompositionFeedbackDto? {
        if (raw.isBlank()) return null
        val cleaned = raw.trim()
            .removePrefix("```json")
            .removePrefix("```")
            .removeSuffix("```")
            .trim()
        val start = cleaned.indexOf('{')
        val end = cleaned.lastIndexOf('}')
        if (start == -1 || end == -1 || end <= start) return null
        val jsonStr = cleaned.substring(start, end + 1)
        return runCatching {
            AppJson.decodeFromString(CompositionFeedbackDto.serializer(), jsonStr)
        }.getOrNull()
    }
}
