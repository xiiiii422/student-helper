package com.example.studenthelper.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** iOS 正在输入指示器：三颗错相跳动/淡入淡出的灰点。 */
@Composable
fun LoadingDots(
    color: Color = Color(0xFFB0B0B8),
    dotSize: Int = 8,
) {
    val transition = rememberInfiniteTransition(label = "typing")
    Row(
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier.padding(vertical = 4.dp),
    ) {
        repeat(3) { i ->
            val phase = i * 160
            val alpha by transition.animateFloat(
                initialValue = 0.35f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 480, delayMillis = phase),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "a$i",
            )
            val rise by transition.animateFloat(
                initialValue = 0f,
                targetValue = -3f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 480, delayMillis = phase),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "r$i",
            )
            Box(
                modifier = Modifier
                    .size(dotSize.dp)
                    .offset(y = rise.dp)
                    .alpha(alpha)
                    .background(color, CircleShape)
            )
        }
    }
}
