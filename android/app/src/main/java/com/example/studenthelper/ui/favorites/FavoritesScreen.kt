package com.example.studenthelper.ui.favorites

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.ui.theme.ChineseAccent
import com.example.studenthelper.ui.theme.EnglishAccent
import com.example.studenthelper.ui.theme.MathAccent

private fun subjectAccent(s: String): Color = when (s) {
    "chinese" -> ChineseAccent
    "math" -> MathAccent
    "english" -> EnglishAccent
    else -> MathAccent
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(
    onBack: () -> Unit,
    viewModel: FavoritesViewModel = hiltViewModel(),
) {
    val items by viewModel.items.collectAsState()
    val filter by viewModel.currentFilter.collectAsState()
    var expandedIds by remember { mutableStateOf(setOf<Long>()) }

    Scaffold(
        topBar = {
            com.example.studenthelper.ui.components.IosNavBar(
                title = "错题本",
                onBack = onBack,
            )
        },
    ) { innerPadding ->
        Column(Modifier.fillMaxSize().padding(innerPadding)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                FilterChip(selected = filter == null, onClick = { viewModel.setFilter(null) }, label = { Text("全部") })
                Subject.entries.forEach { s ->
                    FilterChip(
                        selected = filter == s,
                        onClick = { viewModel.setFilter(s) },
                        label = { Text(s.label) },
                    )
                }
            }

            if (items.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("还没有收藏的错题", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(items, key = { it.favorite.id }) { fav ->
                        val accent = subjectAccent(fav.favorite.subject)
                        val expanded = fav.favorite.id in expandedIds
                        Card(
                            onClick = {
                                expandedIds = if (expanded) expandedIds - fav.favorite.id
                                else expandedIds + fav.favorite.id
                            },
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                            shape = RoundedCornerShape(20.dp),
                        ) {
                            Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.width(4.dp).height(48.dp).background(accent, RoundedCornerShape(2.dp)))
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        fav.msgTextContent,
                                        fontSize = 15.sp,
                                        maxLines = if (expanded) Int.MAX_VALUE else 3,
                                        overflow = TextOverflow.Ellipsis,
                                        style = MaterialTheme.typography.bodyLarge,
                                    )
                                    Text(
                                        Subject.fromApi(fav.favorite.subject).label +
                                            if (expanded) " · 点击收起" else " · 点击展开",
                                        fontSize = 12.sp,
                                        color = accent,
                                    )
                                }
                                IconButton(onClick = { viewModel.remove(fav.favorite.message_id, Subject.fromApi(fav.favorite.subject)) }) {
                                    Icon(Icons.Filled.Delete, "移除", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
