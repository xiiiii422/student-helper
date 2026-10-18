package com.example.studenthelper.ui.composition

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studenthelper.core.util.FileStorage
import com.example.studenthelper.data.local.entity.CompositionEntity
import com.example.studenthelper.data.repository.CompositionRepository
import com.example.studenthelper.domain.composition.FeedbackParser
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
class CompositionListViewModel @Inject constructor(
    private val repo: CompositionRepository,
    private val fileStorage: FileStorage,
) : ViewModel() {

    data class Row(
        val entity: CompositionEntity,
        val firstImageUri: String?,
        val summary: String?,
    )

    val rows: StateFlow<List<Row>> = repo.observeAll()
        .map { list ->
            list.map { e ->
                Row(
                    entity = e,
                    firstImageUri = firstImage(e.imageUris),
                    summary = FeedbackParser.parse(e.aiFeedback)?.summary,
                )
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private fun firstImage(imageUrisJson: String): String? {
        // imageUris 存的是简单 JSON 数组字符串 ["/path1","/path2"]
        val cleaned = imageUrisJson.trim().removePrefix("[").removeSuffix("]")
        if (cleaned.isBlank()) return null
        return cleaned.split(",").firstOrNull()?.trim()?.trim('"')
    }

    /** 删除作文及其本地图片。 */
    fun delete(entity: CompositionEntity) {
        viewModelScope.launch {
            parseUris(entity.imageUris).forEach { fileStorage.deleteImage(it) }
            repo.delete(entity)
        }
    }

    private fun parseUris(imageUrisJson: String): List<String> {
        val cleaned = imageUrisJson.trim().removePrefix("[").removeSuffix("]")
        if (cleaned.isBlank()) return emptyList()
        return cleaned.split(",").map { it.trim().trim('"') }.filter { it.isNotBlank() }
    }
}
