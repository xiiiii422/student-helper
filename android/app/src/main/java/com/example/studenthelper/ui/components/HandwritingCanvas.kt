package com.example.studenthelper.ui.components

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog

/**
 * 全屏手写对话框：用户手写后导出为 Bitmap 回调 onConfirm。
 * 记录每笔 Path，确认时在离屏 Bitmap 上重绘，保证 OCR 输入清晰。
 */
@Composable
fun HandwritingDialog(
    onDismiss: () -> Unit,
    onConfirm: (Bitmap) -> Unit,
) {
    val paths = remember { mutableListOf<Path>() }
    var currentPath by remember { mutableStateOf(Path()) }
    var canvasW by remember { mutableIntStateOf(0) }
    var canvasH by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    val strokePx = with(density) { 6.dp.toPx() }
    // 深色模式下画布底变深，屏幕笔迹用白色；导出位图仍为白底黑字（OCR 友好）
    val ink = if (androidx.compose.foundation.isSystemInDarkTheme()) Color.White else Color.Black

    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(12.dp),
        ) {
            Text("在下方手写题目 / 文字", modifier = Modifier.padding(bottom = 8.dp))

            val canvasModifier = Modifier
                .fillMaxWidth()
                .height(320.dp)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .onSizeChanged { canvasW = it.width; canvasH = it.height }
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragStart = { offset ->
                            currentPath = Path().apply { moveTo(offset.x, offset.y) }
                        },
                        onDrag = { change, _ ->
                            change.consume()
                            currentPath.lineTo(change.position.x, change.position.y)
                        },
                        onDragEnd = {
                            paths.add(currentPath)
                            currentPath = Path()
                        },
                    )
                }

            Canvas(canvasModifier) {
                val style = Stroke(width = strokePx, cap = StrokeCap.Round)
                paths.forEach { drawPath(it, ink, style = style) }
                drawPath(currentPath, ink, style = style)
            }

            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { paths.clear(); currentPath = Path() }, modifier = Modifier.weight(1f)) {
                    Text("清除")
                }
                OutlinedButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text("取消")
                }
                Button(
                    onClick = {
                        val bmp = renderPaths(paths, canvasW, canvasH, strokePx)
                        onConfirm(bmp)
                    },
                    modifier = Modifier.weight(1f),
                ) { Text("确定") }
            }
        }
    }
}

private fun renderPaths(
    paths: List<Path>,
    widthPx: Int,
    heightPx: Int,
    strokeWidthPx: Float,
): Bitmap {
    val w = if (widthPx > 0) widthPx else 800
    val h = if (heightPx > 0) heightPx else 600
    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val canvas = android.graphics.Canvas(bitmap)
    canvas.drawColor(Color.White.toArgb())
    val paint = android.graphics.Paint().apply {
        color = Color.Black.toArgb()
        style = android.graphics.Paint.Style.STROKE
        strokeWidth = strokeWidthPx
        strokeCap = android.graphics.Paint.Cap.ROUND
        isAntiAlias = true
    }
    paths.forEach { canvas.drawPath(it.asAndroidPath(), paint) }
    return bitmap
}
