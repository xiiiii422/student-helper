package com.example.studenthelper.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.core.util.MarkdownLite

/**
 * 澎湃 OS 风消息气泡（小米短信/即时通讯观感）：
 * - 用户：小米蓝实底、白字、18dp 圆角 + 右下小尖
 * - AI：浅灰气泡、黑字、左下小尖；定稿后数学用 KaTeX 渲染
 * - 流式中：文本尾部带光标；空内容时显示三点输入指示器
 * - 长按气泡可删除该条消息
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun ChatBubble(
    role: String,             // "user" / "assistant"
    text: String,
    subject: Subject,
    imageUri: String? = null,
    isStreaming: Boolean = false,
    statusHint: String? = null,
    isFavorited: Boolean = false,
    onToggleFavorite: (() -> Unit)? = null,
    onCopy: (() -> Unit)? = null,
    onImageClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
) {
    val isUser = role == "user"
    val scheme = MaterialTheme.colorScheme
    val bubbleColor = if (isUser) scheme.primary else scheme.surfaceVariant
    val textColor = if (isUser) scheme.onPrimary else scheme.onSurface

    val corner = if (isUser) {
        RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 18.dp, bottomEnd = 6.dp)
    } else {
        RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = 6.dp, bottomEnd = 18.dp)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Column(
            horizontalAlignment = if (isUser) Alignment.End else Alignment.Start,
            modifier = Modifier.widthIn(max = if (isUser) 290.dp else 310.dp),
        ) {
            if (!imageUri.isNullOrBlank()) {
                val imageModifier = Modifier
                    .padding(bottom = 4.dp)
                    .widthIn(max = 210.dp)
                    .height(160.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .then(
                        if (onImageClick != null) {
                            Modifier.clickable { onImageClick() }
                        } else Modifier
                    )
                AsyncImage(
                    model = imageUri,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = imageModifier,
                )
            }

            Box(
                modifier = Modifier
                    .clip(corner)
                    .background(bubbleColor)
                    .combinedClickable(
                        onClick = {},
                        onLongClick = onLongClick,
                    )
                    .padding(horizontal = 14.dp, vertical = 9.dp),
            ) {
                when {
                    // 流式且尚无内容 → 输入指示器（重试时附一行小字，免得长等待被当成死机）
                    isStreaming && text.isEmpty() -> Column {
                        LoadingDots(color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (statusHint != null) {
                            Text(
                                text = statusHint,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 12.sp,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                    }
                    // 定稿数学且含 LaTeX → KaTeX WebView（无公式不建 WebView，省内存）
                    !isStreaming && subject == Subject.MATH && MarkdownLite.containsLatex(text) ->
                        MathText(content = text, color = textColor)
                    // 流式中 → 纯文本预览（去 Markdown 符号）+ 光标
                    isStreaming -> Text(
                        text = MarkdownLite.strip(text) + "▍",
                        color = textColor,
                        fontSize = 17.sp,
                        lineHeight = 24.sp,
                    )
                    // 定稿 → 轻量富文本（加粗/标题/列表）
                    else -> Text(
                        text = MarkdownLite.toAnnotated(text),
                        color = textColor,
                        fontSize = 17.sp,
                        lineHeight = 24.sp,
                    )
                }
            }

            // 极简操作行：仅定稿 AI 气泡显示
            if (!isUser && !isStreaming && onToggleFavorite != null) {
                Spacer(Modifier.height(1.dp))
                Row(horizontalArrangement = Arrangement.Start) {
                    if (onCopy != null) {
                        IconButton(onClick = onCopy, modifier = Modifier.height(28.dp)) {
                            Icon(
                                Icons.Outlined.ContentCopy,
                                contentDescription = "复制",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(16.dp),
                            )
                        }
                    }
                    IconButton(onClick = onToggleFavorite, modifier = Modifier.height(28.dp)) {
                        Icon(
                            imageVector = if (isFavorited) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                            contentDescription = "收藏",
                            tint = if (isFavorited) MaterialTheme.colorScheme.primary
                                   else MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }
        }
    }
}
