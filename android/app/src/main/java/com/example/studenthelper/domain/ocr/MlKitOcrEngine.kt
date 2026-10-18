package com.example.studenthelper.domain.ocr

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class OcrLine(val text: String, val confidence: Float)
data class OcrBlock(val text: String, val lines: List<OcrLine>)
data class OcrRawResult(val text: String, val blocks: List<OcrBlock>) {
    /** 所有行的平均置信度；无内容返回 0。 */
    val averageConfidence: Float
        get() {
            val all = blocks.flatMap { it.lines }
            return if (all.isEmpty()) 0f else all.map { it.confidence }.average().toFloat()
        }
}

@Singleton
class MlKitOcrEngine @Inject constructor() {

    private val recognizer = TextRecognition.getClient(
        ChineseTextRecognizerOptions.Builder().build()
    )

    suspend fun recognize(bitmap: Bitmap): OcrRawResult = suspendCancellableCoroutine { cont ->
        val image = InputImage.fromBitmap(bitmap, 0)
        recognizer.process(image)
            .addOnSuccessListener { result ->
                val blocks = result.textBlocks.map { b ->
                    OcrBlock(
                        text = b.text,
                        lines = b.lines.map { l -> OcrLine(l.text, l.confidence ?: 0f) }
                    )
                }
                cont.resume(OcrRawResult(result.text, blocks))
            }
            .addOnFailureListener { cont.resumeWithException(it) }
    }

    fun close() {
        runCatching { recognizer.close() }
    }
}
