package com.example.studenthelper.ui.favorites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.data.local.dao.FavoriteWithMessage
import com.example.studenthelper.data.repository.FavoriteRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel
class FavoritesViewModel @Inject constructor(
    private val repo: FavoriteRepository,
) : ViewModel() {

    private val filter = MutableStateFlow<Subject?>(null)

    @OptIn(ExperimentalCoroutinesApi::class)
    val items: StateFlow<List<FavoriteWithMessage>> = filter
        .flatMapLatest { subj ->
            if (subj == null) repo.observeAll() else repo.observeBySubject(subj)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val currentFilter: StateFlow<Subject?> = filter

    fun setFilter(subject: Subject?) { filter.value = subject }

    fun remove(messageId: Long, subject: Subject) {
        viewModelScope.launch { repo.toggle(messageId, subject) } // toggle 已收藏 = 取消
    }
}
