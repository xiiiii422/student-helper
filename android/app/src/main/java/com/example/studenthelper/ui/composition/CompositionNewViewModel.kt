package com.example.studenthelper.ui.composition

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studenthelper.core.util.BitmapUtils
import com.example.studenthelper.core.util.FileStorage
import com.example.studenthelper.data.repository.CompositionRepository
import com.example.studenthelper.domain.ocr.OcrRouter
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.domain.ocr.OcrResult
import dagger.hilt.android.lifecycle.HiltViewModel
import java.io.File
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CompositionDraft(
    val title: String = "",
    val requirement: String = "",
    val content: String = "",
    val imageFiles: List<File> = emptyList(),
)

@HiltViewModel
class CompositionNewViewModel @Inject constructor(
    private val repo: CompositionRepository,
    private val ocrRouter: OcrRouter,
    private val fileStorage: FileStorage,
) : ViewModel() {

    private val _draft = MutableStateFlow(CompositionDraft())
    val draft: StateFlow<CompositionDraft> = _draft.asStateFlow()

    private val _submitting = MutableStateFlow(false)
    val submitting: StateFlow<Boolean> = _submitting.asStateFlow()

    private val _ocrWorking = MutableStateFlow(false)
    val ocrWorking: StateFlow<Boolean> = _ocrWorking.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    /** 提交成功后的新作文 id，供 UI 导航。 */
    private val _navigatedId = MutableStateFlow<Long?>(null)
    val navigatedId: StateFlow<Long?> = _navigatedId.asStateFlow()

    fun setTitle(v: String) { _draft.value = _draft.value.copy(title = v) }
    fun setRequirement(v: String) { _draft.value = _draft.value.copy(requirement = v) }
    fun setContent(v: String) { _draft.value = _draft.value.copy(content = v) }

    fun removeImage(index: Int) {
        val list = _draft.value.imageFiles.toMutableList()
        if (index in list.indices) {
            fileStorage.deleteImage(list[index].absolutePath)
            list.removeAt(index)
            _draft.value = _draft.value.copy(imageFiles = list)
        }
    }

    /** 新增一张作文照片（最多 4 张），OCR 追加到 content。 */
    fun addImage(file: File) {
        val current = _draft.value
        if (current.imageFiles.size >= 4) {
            _error.value = "最多 4 张照片"
            return
        }
        _draft.value = current.copy(imageFiles = current.imageFiles + file)
        // OCR 预填正文（图片模式仍需识别文字供编辑）
        _ocrWorking.value = true
        viewModelScope.launch {
            try {
                val bitmap = BitmapUtils.loadCompressed(file)
                when (val r = ocrRouter.process(bitmap, Subject.CHINESE)) {
                    is OcrResult.TextOnly -> appendText(r.text)
                    is OcrResult.TextWithImageFallback -> appendText(r.text)
                    is OcrResult.ImageOnly -> if (r.partialText.isNotBlank()) appendText(r.partialText)
                }
            } catch (e: Exception) {
                _error.value = "识别失败：${e.message}（仍可提交图片）"
            } finally {
                _ocrWorking.value = false
            }
        }
    }

    private fun appendText(t: String) {
        if (t.isBlank()) return
        val cur = _draft.value.content
        val merged = if (cur.isBlank()) t else "$cur\n$t"
        _draft.value = _draft.value.copy(content = merged)
    }

    fun submit() {
        val d = _draft.value
        if (_submitting.value) return
        if (d.content.isBlank() && d.imageFiles.isEmpty()) {
            _error.value = "请先输入或拍照作文内容"
            return
        }
        _submitting.value = true
        viewModelScope.launch {
            try {
                val imagesBase64 = d.imageFiles.mapNotNull { f ->
                    runCatching { BitmapUtils.toBase64(BitmapUtils.loadCompressed(f)) }.getOrNull()
                }
                val imageUrisJson = "[" + d.imageFiles.joinToString(",") { "\"${it.absolutePath}\"" } + "]"
                val id = repo.submitAndSave(
                    title = d.title,
                    content = d.content,
                    imageUrisJson = imageUrisJson,
                    imagesBase64 = imagesBase64,
                    requirement = d.requirement.ifBlank { null },
                )
                _navigatedId.value = id
            } catch (e: Exception) {
                _error.value = e.message ?: "批改失败"
            } finally {
                _submitting.value = false
            }
        }
    }

    fun consumeError() { _error.value = null }
}
