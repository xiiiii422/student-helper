package com.example.studenthelper.ui.composition

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studenthelper.core.network.dto.CompositionFeedbackDto
import com.example.studenthelper.data.local.entity.CompositionEntity
import com.example.studenthelper.data.repository.CompositionRepository
import com.example.studenthelper.domain.composition.FeedbackParser
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class CompositionDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repo: CompositionRepository,
) : ViewModel() {

    private val compositionId: Long = savedStateHandle.get<Long>("id") ?: -1L

    private val _entity = MutableStateFlow<CompositionEntity?>(null)
    val entity: StateFlow<CompositionEntity?> = _entity.asStateFlow()

    private val _feedback = MutableStateFlow<CompositionFeedbackDto?>(null)
    val feedback: StateFlow<CompositionFeedbackDto?> = _feedback.asStateFlow()

    private val _parseFailed = MutableStateFlow(false)
    val parseFailed: StateFlow<Boolean> = _parseFailed.asStateFlow()

    private val _rewriteResult = MutableStateFlow<String?>(null)
    val rewriteResult: StateFlow<String?> = _rewriteResult.asStateFlow()

    private val _rewriting = MutableStateFlow(false)
    val rewriting: StateFlow<Boolean> = _rewriting.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        viewModelScope.launch {
            val e = repo.getById(compositionId)
            _entity.value = e
            if (e != null) {
                val fb = FeedbackParser.parse(e.aiFeedback)
                _feedback.value = fb
                _parseFailed.value = fb == null
            } else {
                _error.value = "未找到该作文"
            }
        }
    }

    fun rewriteSegment(text: String) {
        if (_rewriting.value) return
        _rewriting.value = true
        _rewriteResult.value = null
        viewModelScope.launch {
            try {
                _rewriteResult.value = repo.rewrite(text)
            } catch (e: Exception) {
                _error.value = e.message ?: "改写失败"
            } finally {
                _rewriting.value = false
            }
        }
    }

    fun dismissRewrite() { _rewriteResult.value = null }
    fun consumeError() { _error.value = null }
}
