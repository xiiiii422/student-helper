package com.example.studenthelper.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val HyperLightScheme = lightColorScheme(
    primary = MiBlue,
    onPrimary = Color.White,
    secondary = MiOrange,
    onSecondary = Color.White,
    background = HyperBackground,
    onBackground = HyperText,
    surface = HyperCard,
    onSurface = HyperText,
    surfaceVariant = HyperFill,
    onSurfaceVariant = HyperTextSecondary,
    outline = HyperDivider,
    outlineVariant = HyperDivider,
    error = ScorePoor,
    onError = Color.White,
    scrim = Color.Black,
    // 不写这几项会退回 Material 默认紫，与小米蓝主题冲突（FilterChip / Snackbar 尤其明显）
    primaryContainer = Color(0xFFDCE9FF),
    onPrimaryContainer = Color(0xFF0B2E6B),
    secondaryContainer = Color(0xFFE8F1FF),
    onSecondaryContainer = Color(0xFF0A3E9E),
    tertiary = MiOrange,
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFEEDA),
    onTertiaryContainer = Color(0xFF5A2E00),
    inverseSurface = Color(0xFF2B2F36),
    inverseOnSurface = Color(0xFFF5F5F7),
    inversePrimary = Color(0xFF7FA9FF),
    surfaceBright = Color(0xFFFFFFFF),
)

/** 澎湃 OS 深色：近黑底、深灰卡、提亮品牌蓝，AI 气泡/填充用 #2C2C2E 系。 */
private val HyperDarkScheme = darkColorScheme(
    primary = MiBlueDark,
    onPrimary = Color.White,
    secondary = MiOrange,
    onSecondary = Color(0xFF1D1300),
    background = HyperBackgroundDark,
    onBackground = HyperTextDark,
    surface = HyperCardDark,
    onSurface = HyperTextDark,
    surfaceVariant = HyperFillDark,
    onSurfaceVariant = HyperTextDarkSecondary,
    outline = HyperDividerDark,
    outlineVariant = HyperDividerDark,
    error = Color(0xFFFF6960),
    onError = Color(0xFF2B0000),
    scrim = Color.Black,
    primaryContainer = Color(0xFF123C7D),
    onPrimaryContainer = Color(0xFFD6E6FF),
    secondaryContainer = Color(0xFF1E3A66),
    onSecondaryContainer = Color(0xFFBBD6FF),
    tertiary = MiOrange,
    onTertiary = Color(0xFF2B1600),
    tertiaryContainer = Color(0xFF4A2E10),
    onTertiaryContainer = Color(0xFFFFE0BD),
    inverseSurface = Color(0xFFE8E8EA),
    inverseOnSurface = Color(0xFF1C1C1E),
    inversePrimary = Color(0xFF0A59F7),
)

/**
 * 小米澎湃 OS（HyperOS）风主题：“生命感美学”——灰底白卡、全局圆角。
 * darkTheme=false 浅色 / true 深色；MiSans 字体由系统 FontFamily.Default 自动提供。
 */
@Composable
fun StudentHelperTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
            @Suppress("DEPRECATION")
            window.statusBarColor = Color.Transparent.toArgb()
            @Suppress("DEPRECATION")
            window.navigationBarColor = Color.Transparent.toArgb()
            window.decorView.setBackgroundColor(
                (if (darkTheme) HyperBackgroundDark else HyperBackground).toArgb()
            )
        }
    }
    MaterialTheme(
        colorScheme = if (darkTheme) HyperDarkScheme else HyperLightScheme,
        typography = AppTypography,
        shapes = AppShapes,
        content = content,
    )
}
