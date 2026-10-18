package com.example.studenthelper.ui.shared

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.Icons
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.core.util.BitmapUtils
import com.example.studenthelper.core.util.DateUtils
import com.example.studenthelper.core.util.FileStorage
import com.example.studenthelper.data.local.entity.MessageEntity
import com.example.studenthelper.ui.components.ChatBubble
import com.example.studenthelper.ui.components.HandwritingDialog
import com.example.studenthelper.ui.components.IosLargeTitle
import com.example.studenthelper.ui.components.IosTextButton
import com.example.studenthelper.ui.components.InputBar
import com.example.studenthelper.ui.components.OcrConfirmDialog
import com.example.studenthelper.ui.components.rememberImagePickers
import com.example.studenthelper.ui.theme.IosBlue
import com.example.studenthelper.ui.theme.TertiaryLabel

/** 追问快捷入口（小学生打字慢，点一下即发）。 */
private val FOLLOW_UPS = listOf("再讲一遍", "换个方法讲", "直接告诉我答案", "再出一道同类题")

/**
 * 三科共用聊天屏（iOS 风）：
 * 大标题导航、systemGray6 背景、iMessage 气泡、消息弹入动画。
 */
@Composable
fun ChatScreen(
    accent: Color,
    title: String,
    onBack: (() -> Unit)? = null,
    viewModel: ChatViewModel = hiltViewModel(),
) {
    val messages by viewModel.messages.collectAsState()
    val streaming by viewModel.streaming.collectAsState()
    val liveAssistant by viewModel.liveAssistantText.collectAsState()
    val statusHint by viewModel.statusHint.collectAsState()
    val pendingOcr by viewModel.pendingOcr.collectAsState()
    val ocrWorking by viewModel.ocrWorking.collectAsState()
    val error by viewModel.error.collectAsState()
    val sendFailure by viewModel.sendFailure.collectAsState()
    val favoritedIds by viewModel.favoritedIds.collectAsState()

    var input by remember { mutableStateOf("") }
    var showHandwriting by remember { mutableStateOf(false) }
    var previewUri by remember { mutableStateOf<String?>(null) }
    var msgToDelete by remember { mutableStateOf<MessageEntity?>(null) }
    var showClearConfirm by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }
    val listState = rememberLazyListState()
    val clipboard = LocalClipboardManager.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val fileStorage = remember { FileStorage(context) }

    LaunchedEffect(messages.size, liveAssistant?.length, sendFailure) {
        if (messages.isNotEmpty() || !liveAssistant.isNullOrEmpty()) {
            listState.scrollToItem(if (streaming) messages.size else messages.size - 1)
        }
    }

    LaunchedEffect(error) {
        error?.let {
            val result = snackbarHostState.showSnackbar(
                message = it,
                actionLabel = "重试",
                duration = SnackbarDuration.Short,
            )
            if (result == SnackbarResult.ActionPerformed) viewModel.retryLast()
            viewModel.consumeError()
        }
    }

    val pickers = rememberImagePickers(fileStorage = fileStorage) { file ->
        viewModel.processImageFile(file)
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            IosLargeTitle(
                title = title,
                actions = {
                    IosTextButton(text = "清空", onClick = { showClearConfirm = true })
                },
            )
        },
        bottomBar = {
            InputBar(
                value = input,
                onValueChange = { input = it },
                enabled = !streaming,
                accent = accent,
                onTakePhoto = { pickers.launchCamera() },
                onPickImage = { pickers.launchGallery() },
                onHandwriting = { showHandwriting = true },
                onSend = {
                    viewModel.sendText(input)
                    input = ""
                },
            )
        },
    ) { innerPadding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            if (messages.isEmpty() && liveAssistant == null) {
                EmptyState(
                    title = title,
                    accent = accent,
                    subject = viewModel.subject,
                    onPickExample = { input = it },
                )
            } else {
                LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                    itemsIndexed(messages, key = { _, m -> m.id }) { index, msg ->
                        val hidePlaceholder =
                            streaming && msg.role == "assistant" &&
                                msg.id == messages.lastOrNull()?.id && msg.isStreaming
                        if (!hidePlaceholder) {
                            Box(
                                Modifier.animateItem(
                                    placementSpec = spring(
                                        dampingRatio = Spring.DampingRatioLowBouncy,
                                        stiffness = 350f,
                                    ),
                                )
                            ) {
                                Column {
                                    // 时间分隔：首条或间隔超过 5 分钟
                                    val prev = messages.getOrNull(index - 1)
                                    if (prev == null || msg.created_at - prev.created_at > 5 * 60 * 1000L) {
                                        Box(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 2.dp), contentAlignment = Alignment.Center) {
                                            Text(
                                                DateUtils.format(msg.created_at),
                                                style = MaterialTheme.typography.labelMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                    BubbleRow(
                                        msg = msg,
                                        subject = viewModel.subject,
                                        isFavorited = msg.id in favoritedIds,
                                        onToggleFavorite = { viewModel.toggleFavorite(msg.id) },
                                        onCopy = { clipboard.setText(AnnotatedString(msg.textContent)) },
                                        onImageClick = msg.imageUri?.let { { previewUri = it } },
                                        onLongClick = { msgToDelete = msg },
                                    )
                                }
                            }
                        }
                    }
                    if (liveAssistant != null && streaming) {
                        item {
                            ChatBubble(
                                role = "assistant",
                                text = liveAssistant ?: "",
                                subject = viewModel.subject,
                                isStreaming = true,
                                statusHint = statusHint,
                            )
                        }
                    }
                    // 发送失败：在对话流里留一张常驻卡片，而不是几秒就消失的 snackbar
                    // 进程被杀后重进，sendFailure 丢了，但“最后一句是学生提问”本身就是没回答的信号
                    val tail = messages.lastOrNull()
                    val orphanedQuestion = sendFailure == null && tail != null && tail.role == "user"
                    if (!streaming && (sendFailure != null || orphanedQuestion)) {
                        item {
                            SendFailureCard(
                                reason = sendFailure ?: "上一次没能回答成功",
                                onRetry = { viewModel.retryLast() },
                            )
                        }
                    }
                    // 追问快捷入口：上一轮回答定稿后显示
                    val last = messages.lastOrNull()
                    if (!streaming && last != null && last.role == "assistant" && last.textContent.isNotBlank()) {
                        item {
                            androidx.compose.foundation.layout.Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState())
                                    .padding(horizontal = 14.dp, vertical = 6.dp),
                                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp),
                            ) {
                                FOLLOW_UPS.forEach { q ->
                                    SuggestionChip(
                                        onClick = { viewModel.sendText(q) },
                                        label = { Text(q, fontSize = 13.sp) },
                                    )
                                }
                            }
                        }
                    }
                    item { Box(Modifier.padding(bottom = 8.dp)) }
                }
            }

            // 本地 OCR 识别中：顶部胶囊提示，不遮挡对话
            if (ocrWorking) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    Text(
                        text = "识别中，请稍候",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.92f), RoundedCornerShape(16.dp))
                            .padding(horizontal = 14.dp, vertical = 7.dp),
                    )
                }
            }
        }
    }

    pendingOcr?.let { p ->
        OcrConfirmDialog(
            imageUri = p.imageUri,
            initialText = p.text,
            confidence = p.confidence,
            suggestedMode = p.suggestedMode,
            onDismiss = { viewModel.dismissPendingOcr() },
            onReRecognize = { viewModel.reRecognizePending() },
            onConfirm = { text, mode -> viewModel.confirmPendingSend(text, mode) },
        )
    }

    if (showHandwriting) {
        HandwritingDialog(
            onDismiss = { showHandwriting = false },
            onConfirm = { bitmap ->
                val file = fileStorage.newImageFile(prefix = "ink")
                BitmapUtils.saveCompressed(bitmap, file)
                showHandwriting = false
                viewModel.processImageFile(file)
            },
        )
    }

    // 图片全屏查看
    com.example.studenthelper.ui.components.PreviewImageDialog(
        uri = previewUri,
        onDismiss = { previewUri = null },
    )

    // 误触保护：清空前确认
    if (showClearConfirm) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            title = { Text("清空「$title」的全部对话？") },
            text = { Text("本学科的历史记录将被删除且不可恢复，已收藏的错题也会一并移除。") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.clearHistory()
                    showClearConfirm = false
                }) { Text("清空", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { showClearConfirm = false }) { Text("取消") } },
        )
    }

    // 长按删除确认
    msgToDelete?.let { m ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { msgToDelete = null },
            title = { Text("删除这条消息？") },
            text = {
                Text(
                    m.textContent.take(80) + if (m.textContent.length > 80) "…" else "",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteMessage(m.id)
                    msgToDelete = null
                }) { Text("删除", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { msgToDelete = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun BubbleRow(
    msg: MessageEntity,
    subject: Subject,
    isFavorited: Boolean,
    onToggleFavorite: () -> Unit,
    onCopy: () -> Unit,
    onImageClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
) {
    ChatBubble(
        role = msg.role,
        text = msg.textContent,
        subject = subject,
        imageUri = msg.imageUri,
        isStreaming = false,
        isFavorited = isFavorited,
        onToggleFavorite = if (msg.role == "assistant") onToggleFavorite else null,
        onCopy = if (msg.role == "assistant") onCopy else null,
        onImageClick = onImageClick,
        onLongClick = onLongClick,
    )
}

/** 学科示例提问：孩子第一次打开不知道问什么，点一下就填进输入框。 */
private fun examplesFor(subject: Subject): List<String> = when (subject) {
    Subject.CHINESE -> listOf(
        "“春风又绿江南岸”里的“绿”字好在哪里？",
        "修改病句：他大约估计这件事是他做的。",
        "《少年闰土》表达了作者怎样的感情？",
    )
    Subject.MATH -> listOf(
        "3/4 + 1/8 = ?",
        "一个圆的半径是 3cm，面积是多少？",
        "一件衣服打八折后是 120 元，原价多少钱？",
    )
    Subject.ENGLISH -> listOf(
        "He ___ (go) to school every day. 应该填什么？",
        "on time 和 in time 有什么区别？",
        "用 there is / there are 各造一个句子",
    )
}

@Composable
private fun EmptyState(
    title: String,
    accent: Color,
    subject: Subject,
    onPickExample: (String) -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(accent.copy(alpha = 0.10f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Outlined.HelpOutline,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(30.dp),
            )
        }
        Text(
            "向「$title」提问",
            style = MaterialTheme.typography.headlineSmall,
            color = scheme.onSurface,
            modifier = Modifier.padding(top = 16.dp),
        )
        Text(
            "打字、拍照或手写题目都可以",
            style = MaterialTheme.typography.bodyMedium,
            color = scheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 6.dp),
        )
        Spacer(Modifier.height(32.dp))
        Column(Modifier.fillMaxWidth()) {
            Text(
                "可以这样问",
                style = MaterialTheme.typography.labelLarge,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 6.dp, bottom = 8.dp),
            )
            examplesFor(subject).forEach { example ->
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(scheme.surface)
                        .border(0.5.dp, scheme.outlineVariant, RoundedCornerShape(14.dp))
                        .clickable { onPickExample(example) }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                ) {
                    Text(
                        example,
                        fontSize = 15.sp,
                        lineHeight = 22.sp,
                        color = scheme.onSurface,
                    )
                }
            }
        }
    }
}

/**
 * 发送失败卡片：贴在 AI 气泡该在的位置，带一条重试按钮。
 * 失败不能只靠 snackbar——snackbar 会被输入栏顶掉、也会自动消失，学生只剩一个“问了没人回”的空对话。
 */
@Composable
private fun SendFailureCard(reason: String, onRetry: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(scheme.surface)
                .border(0.5.dp, scheme.outlineVariant, RoundedCornerShape(16.dp))
                .padding(horizontal = 14.dp, vertical = 12.dp),
        ) {
            androidx.compose.foundation.layout.Row(
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(7.dp)
                        .clip(CircleShape)
                        .background(scheme.error),
                )
                Text(
                    "这次没能回答出来",
                    style = MaterialTheme.typography.bodyMedium,
                    color = scheme.onSurface,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
            Text(
                reason,
                style = MaterialTheme.typography.bodySmall,
                color = scheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            TextButton(
                onClick = onRetry,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 0.dp, end = 12.dp, top = 0.dp, bottom = 0.dp,
                ),
            ) {
                Text("重试", fontSize = 15.sp, color = scheme.primary)
            }
        }
    }
}
