package com.example.studenthelper.ui.composition

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.example.studenthelper.ui.components.CompositionCard
import com.example.studenthelper.ui.components.IosLargeTitle
import com.example.studenthelper.ui.theme.CompositionAccent

/** 作文列表（iOS 分组列表风）：大标题 + 悬浮蓝色圆形按钮。 */
@Composable
fun CompositionListScreen(
    onNewComposition: () -> Unit,
    onOpenDetail: (Long) -> Unit,
    viewModel: CompositionListViewModel = hiltViewModel(),
) {
    val rows by viewModel.rows.collectAsState()
    var pendingDelete by remember { mutableStateOf<com.example.studenthelper.data.local.entity.CompositionEntity?>(null) }

    Scaffold(
        topBar = { IosLargeTitle(title = "作文") },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onNewComposition,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = androidx.compose.ui.graphics.Color.White,
                shape = androidx.compose.foundation.shape.CircleShape,
            ) {
                Icon(Icons.Filled.Add, "新建作文")
            }
        },
    ) { innerPadding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            if (rows.isEmpty()) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Box(
                        modifier = Modifier
                            .size(64.dp)
                            .clip(CircleShape)
                            .background(CompositionAccent.copy(alpha = 0.10f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.EditNote,
                            contentDescription = null,
                            tint = CompositionAccent,
                            modifier = Modifier.size(30.dp),
                        )
                    }
                    Text(
                        "还没有作文",
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(top = 16.dp),
                    )
                    Text(
                        "把作文发上来，老师会给分数、优点和改进建议",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                    Button(
                        onClick = onNewComposition,
                        shape = RoundedCornerShape(22.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                        ),
                        modifier = Modifier.padding(top = 24.dp),
                    ) {
                        Text("写一篇作文", fontSize = 15.sp, modifier = Modifier.padding(vertical = 4.dp))
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = 16.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(
                        top = 4.dp, bottom = 96.dp,
                    ),
                    verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp),
                ) {
                    items(rows, key = { it.entity.id }) { row ->
                        Box(Modifier.animateItem()) {
                            CompositionCard(
                                item = row.entity,
                                firstImageUri = row.firstImageUri,
                                summary = row.summary,
                                onClick = { onOpenDetail(row.entity.id) },
                                onLongClick = { pendingDelete = row.entity },
                            )
                        }
                    }
                }
            }
        }
    }

    pendingDelete?.let { target ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("删除这篇作文？") },
            text = { Text("「${target.title}」的批改记录与图片将一并删除，不可恢复。") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.delete(target)
                    pendingDelete = null
                }) { Text("删除", color = Color(0xFFF53F3F)) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("取消") }
            },
        )
    }
}
