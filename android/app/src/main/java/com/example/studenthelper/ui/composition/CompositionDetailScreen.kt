package com.example.studenthelper.ui.composition

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import com.example.studenthelper.R
import com.example.studenthelper.ui.components.FeedbackDetail
import com.example.studenthelper.ui.components.IosNavBar
import com.example.studenthelper.ui.components.PreviewImageDialog

@Composable
fun CompositionDetailScreen(
    onBack: () -> Unit,
    viewModel: CompositionDetailViewModel = hiltViewModel(),
) {
    val entity by viewModel.entity.collectAsState()
    val feedback by viewModel.feedback.collectAsState()
    val parseFailed by viewModel.parseFailed.collectAsState()
    val rewriteResult by viewModel.rewriteResult.collectAsState()
    val rewriting by viewModel.rewriting.collectAsState()
    val error by viewModel.error.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }
    var showRewriteDialog by remember { mutableStateOf(false) }
    var pendingSegment by remember { mutableStateOf<String?>(null) }
    var previewUri by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(error) {
        error?.let { snackbarHostState.showSnackbar(it); viewModel.consumeError() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            IosNavBar(
                title = entity?.title ?: stringResource(R.string.tab_composition),
                onBack = onBack,
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState()),
        ) {
            val e = entity
            if (e != null) {
                // 作文原稿（图片 + 正文）
                val uris = parseUris(e.imageUris)
                if (uris.isNotEmpty() || e.content.isNotBlank()) {
                    SectionCard(title = "作文原稿") {
                        if (uris.isNotEmpty()) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                uris.forEach { uri ->
                                    AsyncImage(
                                        model = uri,
                                        contentDescription = "作文手稿",
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier
                                            .size(width = 92.dp, height = 120.dp)
                                            .clip(RoundedCornerShape(10.dp))
                                            .clickable { previewUri = uri },
                                    )
                                }
                            }
                            Spacer(Modifier.height(10.dp))
                        }
                        if (e.content.isNotBlank()) {
                            Text(
                                e.content,
                                fontSize = 15.sp,
                                lineHeight = 24.sp,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            }

            val fb = feedback
            if (fb != null) {
                FeedbackDetail(feedback = fb, onRewriteSegment = { seg ->
                    pendingSegment = seg
                    showRewriteDialog = true
                })
            } else if (parseFailed) {
                Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("AI 返回格式异常，以下为原始回复：", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(8.dp))
                        Text(
                            entity?.aiFeedback ?: "",
                            modifier = Modifier.fillMaxWidth().padding(12.dp),
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            } else if (entity == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    // 段落改写对话框
    if (showRewriteDialog && pendingSegment != null) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showRewriteDialog = false; viewModel.dismissRewrite() },
            title = { Text("针对该段再改一次") },
            text = {
                Column {
                    Text("原句：$pendingSegment", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(12.dp))
                    val result = rewriteResult
                    if (rewriting) {
                        CircularProgressIndicator()
                    } else if (result != null) {
                        Text(result, fontSize = 15.sp, lineHeight = 23.sp)
                    } else {
                        viewModel.rewriteSegment(pendingSegment!!)
                        Text("改写中…")
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.Button(
                    onClick = { showRewriteDialog = false; viewModel.dismissRewrite() },
                ) { Text("关闭") }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(
                    onClick = { showRewriteDialog = false; viewModel.dismissRewrite() },
                ) { Text("取消") }
            },
        )
    }

    PreviewImageDialog(uri = previewUri, onDismiss = { previewUri = null })
}

@Composable
private fun SectionCard(title: String, content: @Composable () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        shape = RoundedCornerShape(20.dp),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(
                title,
                fontWeight = FontWeight.Bold,
                fontSize = 16.sp,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(bottom = 10.dp),
            )
            content()
        }
    }
}

private fun parseUris(imageUrisJson: String): List<String> {
    val cleaned = imageUrisJson.trim().removePrefix("[").removeSuffix("]")
    if (cleaned.isBlank()) return emptyList()
    return cleaned.split(",").map { it.trim().trim('"') }.filter { it.isNotBlank() }
}
