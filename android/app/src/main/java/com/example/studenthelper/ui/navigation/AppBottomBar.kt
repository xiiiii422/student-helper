package com.example.studenthelper.ui.navigation

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.studenthelper.ui.theme.ChineseAccent
import com.example.studenthelper.ui.theme.CompositionAccent
import com.example.studenthelper.ui.theme.EnglishAccent
import com.example.studenthelper.ui.theme.MathAccent
import com.example.studenthelper.ui.theme.MeAccent

private fun accentFor(tab: BottomTab): Color = when (tab) {
    BottomTab.CHINESE -> ChineseAccent
    BottomTab.MATH -> MathAccent
    BottomTab.ENGLISH -> EnglishAccent
    BottomTab.COMPOSITION -> CompositionAccent
    BottomTab.ME -> MeAccent
}

/**
 * 澎湃 OS 风 Tab 栏：乳白半透 + 发丝顶线。选中态统一用品牌蓝（HyperOS 系统应用
 * 不会一个 tab 一个颜色），学科强调色只保留为标签下一条 3dp 短横，兼顾识别与克制。
 */
@Composable
fun AppBottomBar(
    currentRoute: String?,
    onTabSelected: (BottomTab) -> Unit,
) {
    val selectedTab = BottomTab.fromRoute(currentRoute ?: "")
    val scheme = MaterialTheme.colorScheme

    Column(
        Modifier
            .fillMaxWidth()
            .background(scheme.surface.copy(alpha = 0.94f))
    ) {
        // 发丝分隔线
        Box(
            Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(scheme.outlineVariant)
        )
        // 内容避开手势导航条，背景色延伸到其后方
        Row5(selectedTab = selectedTab, onTabSelected = onTabSelected)
    }
}

@Composable
private fun Row5(
    selectedTab: BottomTab?,
    onTabSelected: (BottomTab) -> Unit,
) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(top = 6.dp, bottom = 6.dp),
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.SpaceEvenly,
    ) {
        BottomTab.entries.forEach { tab ->
            val selected = tab == selectedTab
            val accent = accentFor(tab)
            val scheme = MaterialTheme.colorScheme

            val tint by animateColorAsState(
                targetValue = if (selected) scheme.primary else scheme.onSurfaceVariant,
                animationSpec = spring(dampingRatio = Spring.DampingRatioLowBouncy, stiffness = 900f),
                label = "tabTint",
            )
            val scale by animateFloatAsState(
                targetValue = if (selected) 1.08f else 1f,
                animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = 600f),
                label = "tabScale",
            )

            androidx.compose.foundation.layout.Box(
                modifier = Modifier
                    .weight(1f)
                    .iosTap { onTabSelected(tab) },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        imageVector = if (selected) tab.iconSelected else tab.iconUnselected,
                        contentDescription = stringResource(tab.labelRes),
                        tint = tint,
                        modifier = Modifier
                            .size(26.dp)
                            .scale(scale),
                    )
                    Text(
                        text = stringResource(tab.labelRes),
                        fontSize = 10.sp,
                        color = tint,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                    // 学科色短横：常驻占位，避免选中切换时整栏高度跳动
                    val barAlpha by animateFloatAsState(
                        targetValue = if (selected) 1f else 0f,
                        animationSpec = spring(
                            dampingRatio = Spring.DampingRatioLowBouncy,
                            stiffness = 700f,
                        ),
                        label = "tabBar",
                    )
                    Box(
                        Modifier
                            .padding(top = 3.dp)
                            .width(14.dp)
                            .height(3.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(accent.copy(alpha = barAlpha)),
                    )
                }
            }
        }
    }
}

/** iOS 风无波纹点击反馈。 */
@Composable
private fun Modifier.iosTap(onClick: () -> Unit): Modifier {
    val interaction = remember { MutableInteractionSource() }
    return this.clickable(
        interactionSource = interaction,
        indication = null,
        onClick = onClick,
    )
}
