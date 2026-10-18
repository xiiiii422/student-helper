package com.example.studenthelper.domain.ocr

import android.graphics.Bitmap
import com.example.studenthelper.core.common.Subject
import javax.inject.Inject
import javax.inject.Singleton

/** OCR 处理后的路由模式决策（纯逻辑，便于单测）。 */
enum class OcrMode { TEXT_ONLY, TEXT_AND_IMAGE, IMAGE_ONLY }

/** OCR 处理后的路由结果，决定发送给后端的内容形态。 */
sealed class OcrResult {
    /** 高置信度纯文本：只发文字给 DeepSeek（省 token、更快）。 */
    data class TextOnly(val text: String, val confidence: Float) : OcrResult()

    /** 中置信度：文字为主，附带图片作为兜底。 */
    data class TextWithImageFallback(val text: String, val confidence: Float, val bitmap: Bitmap) : OcrResult()

    /** 低置信度：几乎完全依赖多模态看图。 */
    data class ImageOnly(val bitmap: Bitmap, val confidence: Float, val partialText: String = "") : OcrResult()
}

@Singleton
class OcrRouter @Inject constructor(
    private val mlKit: MlKitOcrEngine,
) {
    suspend fun process(bitmap: Bitmap, subject: Subject): OcrResult {
        val raw = runCatching { mlKit.recognize(bitmap) }.getOrNull()
            ?: return OcrResult.ImageOnly(bitmap, 0f)

        val avgConf = raw.averageConfidence
        return when (decide(raw.text, avgConf, subject)) {
            OcrMode.TEXT_ONLY -> OcrResult.TextOnly(raw.text, avgConf)
            OcrMode.TEXT_AND_IMAGE -> OcrResult.TextWithImageFallback(raw.text, avgConf, bitmap)
            OcrMode.IMAGE_ONLY -> OcrResult.ImageOnly(bitmap, avgConf, partialText = raw.text)
        }
    }

    companion object {
        /** 多行版式阈值：语文/英语题常是“文章+小题”的多段结构，超过此行数纯文字会丢版式。 */
        private const val MULTI_LINE_THRESHOLD = 4

        /** 纯决策函数：根据识别文本、平均置信度、学科，给出发送模式。 */
        fun decide(text: String, avgConf: Float, subject: Subject): OcrMode {
            val hasMathSymbols = subject == Subject.MATH && MATH_PATTERN.containsMatchIn(text)
            // 图多字少（数学几何/竖式常见特征）：识别到的有效字符极少
            val sparseText = subject == Subject.MATH &&
                text.count { !it.isWhitespace() } < 12
            // 语文/英语的阅读理解类版式：多行文本必须带图，否则 AI 看不到文章与题目的对应关系
            val multiLineLayout = subject != Subject.MATH &&
                text.lines().count { it.isNotBlank() } >= MULTI_LINE_THRESHOLD
            return when {
                avgConf >= 0.90f && !hasMathSymbols && !sparseText && !multiLineLayout -> OcrMode.TEXT_ONLY
                avgConf >= 0.60f -> OcrMode.TEXT_AND_IMAGE
                else -> OcrMode.IMAGE_ONLY
            }
        }

        // 常见数学符号 / 算式特征，命中则倾向走多模态兜底
        private val MATH_PATTERN = Regex(
            "[∫∑√π∞≈≠≤≥÷×±]\\d*" +          // 特殊符号
                "|\\d+\\s*[+\\-*/÷×]\\s*\\d+\\s*=" + // 四则算式
                "|\\d+/\\d+" +                    // 分数
                "|\\angle|⊥|∥|△|○"                    // 几何符号
        )
    }
}
