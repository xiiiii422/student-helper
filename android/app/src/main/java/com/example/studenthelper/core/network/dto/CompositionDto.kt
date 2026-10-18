package com.example.studenthelper.core.network.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** 作文批改结构化结果（模型直接返回的纯 JSON，客户端 FeedbackParser 解析）。 */
@Serializable
data class CompositionFeedbackDto(
    @SerialName("总分") val totalScore: Int = 0,
    @SerialName("分项") val breakdown: ScoreBreakdown = ScoreBreakdown(),
    @SerialName("总评") val summary: String = "",
    @SerialName("优点") val strengths: List<StrengthItem> = emptyList(),
    @SerialName("问题") val issues: List<IssueItem> = emptyList(),
    @SerialName("改进建议") val suggestions: List<String> = emptyList(),
    @SerialName("好句升级") val rewrites: List<RewriteItem> = emptyList(),
    @SerialName("同类范文片段") val sample: String = "",
)

@Serializable
data class ScoreBreakdown(
    @SerialName("内容") val content: Int = 0,
    @SerialName("结构") val structure: Int = 0,
    @SerialName("语言") val language: Int = 0,
    @SerialName("书写") val writing: Int = 0,
)

@Serializable
data class StrengthItem(
    @SerialName("位置") val location: String = "",
    @SerialName("内容") val content: String = "",
    @SerialName("为什么好") val why: String = "",
)

@Serializable
data class IssueItem(
    @SerialName("位置") val location: String = "",
    @SerialName("类型") val type: String = "",
    @SerialName("原句") val original: String = "",
    @SerialName("问题说明") val explanation: String = "",
    @SerialName("修改建议") val suggestion: String = "",
)

@Serializable
data class RewriteItem(
    @SerialName("原句") val original: String = "",
    @SerialName("改写") val rewritten: String = "",
    @SerialName("为什么更好") val why: String = "",
)
