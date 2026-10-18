package com.example.studenthelper.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

// iOS 风：卡片 20dp、气泡 18dp、小件 12dp
val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(26.dp),
)

val BubbleShape = RoundedCornerShape(18.dp)
val CardShape = RoundedCornerShape(20.dp)
