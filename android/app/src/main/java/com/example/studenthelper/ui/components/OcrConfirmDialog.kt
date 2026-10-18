package com.example.studenthelper.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.studenthelper.R

enum class SendMode { TEXT_ONLY, TEXT_AND_IMAGE }

/**
 * 拍照/手写后的识别结果确认对话框。
 * @param confidence 本地 OCR 平均置信度（0-1）
 * @param suggestedMode 根据 OcrRouter 决策的推荐模式，作为单选初值
 */
@Composable
fun OcrConfirmDialog(
    imageUri: String?,
    initialText: String,
    confidence: Float,
    suggestedMode: SendMode,
    onDismiss: () -> Unit,
    onReRecognize: () -> Unit,
    onConfirm: (text: String, mode: SendMode) -> Unit,
) {
    var text by remember { mutableStateOf(initialText) }
    var mode by remember { mutableStateOf(suggestedMode) }

    val confPct = (confidence * 100).toInt()
    val confLabel = when {
        confidence >= 0.90f -> "较高，可直接发送"
        confidence >= 0.60f -> "一般，建议校对后发送"
        else -> "较低，请手动校对或改用图片发送"
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.ocr_confirm_title), fontSize = 18.sp, fontWeight = FontWeight.Bold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!imageUri.isNullOrBlank()) {
                    AsyncImage(
                        model = imageUri,
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(140.dp)
                            .clip(RoundedCornerShape(10.dp)),
                    )
                }
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 3,
                    maxLines = 6,
                    placeholder = { Text("识别为空可手动输入题目") },
                )
                Text(
                    "识别置信度 $confPct%，$confLabel",
                    fontSize = 13.sp,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = mode == SendMode.TEXT_ONLY, onClick = { mode = SendMode.TEXT_ONLY })
                    Text(stringResource(R.string.ocr_mode_text_only), fontSize = 14.sp)
                    RadioButton(selected = mode == SendMode.TEXT_AND_IMAGE, onClick = { mode = SendMode.TEXT_AND_IMAGE })
                    Text(stringResource(R.string.ocr_mode_text_and_image), fontSize = 14.sp)
                }
                TextButton(onClick = onReRecognize) { Text(stringResource(R.string.ocr_re_recognize)) }
            }
        },
        confirmButton = {
            Button(onClick = { onConfirm(text, mode) }) { Text("发送") }
        },
        dismissButton = {
            OutlinedButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
        },
    )
}
