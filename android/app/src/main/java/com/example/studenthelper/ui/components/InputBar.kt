package com.example.studenthelper.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.studenthelper.R

/**
 * 澎湃 OS 风输入栏：灰底胶囊输入框 + 圆形发送按钮（小米蓝上箭头，禁用态变灰）。
 * 左侧三个细线工具图标：拍照 / 相册 / 手写。
 */
@Composable
fun InputBar(
    value: String,
    onValueChange: (String) -> Unit,
    enabled: Boolean,
    accent: Color,
    onTakePhoto: () -> Unit,
    onPickImage: () -> Unit,
    onHandwriting: () -> Unit,
    onSend: () -> Unit,
) {
    val hasContent = value.isNotBlank()
    val scheme = MaterialTheme.colorScheme

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(scheme.surface.copy(alpha = 0.94f))
            .imePadding()
            .padding(horizontal = 10.dp, vertical = 8.dp),
    ) {
        Row(
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            IconButton(onClick = onTakePhoto, modifier = Modifier.size(38.dp)) {
                Icon(Icons.Outlined.PhotoCamera, stringResource(R.string.take_photo), tint = scheme.onSurfaceVariant, modifier = Modifier.size(22.dp))
            }
            IconButton(onClick = onPickImage, modifier = Modifier.size(38.dp)) {
                Icon(Icons.Outlined.PhotoLibrary, stringResource(R.string.pick_image), tint = scheme.onSurfaceVariant, modifier = Modifier.size(22.dp))
            }
            IconButton(onClick = onHandwriting, modifier = Modifier.size(38.dp)) {
                Icon(Icons.Filled.Create, stringResource(R.string.handwriting), tint = scheme.onSurfaceVariant, modifier = Modifier.size(22.dp))
            }

            // 胶囊输入框
            TextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                modifier = Modifier
                    .weight(1f)
                    .heightIn(max = 130.dp),
                placeholder = {
                    Text(
                        stringResource(R.string.input_hint),
                        color = scheme.onSurfaceVariant,
                        fontSize = 17.sp,
                    )
                },
                textStyle = androidx.compose.ui.text.TextStyle(
                    fontSize = 17.sp,
                    lineHeight = 22.sp,
                    color = scheme.onSurface,
                ),
                shape = RoundedCornerShape(20.dp),
                maxLines = 5,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = scheme.surfaceVariant,
                    unfocusedContainerColor = scheme.surfaceVariant,
                    disabledContainerColor = scheme.surfaceVariant,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    disabledIndicatorColor = Color.Transparent,
                    cursorColor = accent,
                ),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { if (enabled && hasContent) onSend() }),
            )

            // 圆形发送按钮
            val canSend = enabled && hasContent
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .padding(bottom = 1.dp)
                    .clickable(enabled = canSend) { onSend() },
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .background(
                            if (canSend) scheme.primary else scheme.onSurface.copy(alpha = 0.2f),
                            CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.ArrowUpward,
                        contentDescription = stringResource(R.string.send),
                        tint = scheme.onPrimary,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
    }
}
