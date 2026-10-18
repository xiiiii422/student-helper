package com.example.studenthelper.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.studenthelper.core.network.dto.CompositionFeedbackDto
import com.example.studenthelper.ui.theme.NoteBetter
import com.example.studenthelper.ui.theme.NoteBetterDark
import com.example.studenthelper.ui.theme.NoteOriginal
import com.example.studenthelper.ui.theme.NoteOriginalDark

@Composable
fun FeedbackDetail(feedback: CompositionFeedbackDto, onRewriteSegment: (String) -> Unit) {
    // 原句/改进两处提示色随深浅模式切换，不在组件里写死十六进制
    val originalColor = if (isSystemInDarkTheme()) NoteOriginalDark else NoteOriginal
    val betterColor = if (isSystemInDarkTheme()) NoteBetterDark else NoteBetter
    Column(
        modifier = Modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            ScoreRing(score = feedback.totalScore)
            Column {
                ScoreBar("内容", feedback.breakdown.content)
                ScoreBar("结构", feedback.breakdown.structure)
                ScoreBar("语言", feedback.breakdown.language)
                ScoreBar("书写", feedback.breakdown.writing)
            }
        }

        Section("总评") { Text(feedback.summary, fontSize = 15.sp, lineHeight = 24.sp) }

        if (feedback.strengths.isNotEmpty()) {
            Section("优点") {
                feedback.strengths.forEach { s ->
                    Bullet("【${s.location}】${s.content}\n    ↳ ${s.why}")
                }
            }
        }

        if (feedback.issues.isNotEmpty()) {
            Section("问题") {
                feedback.issues.forEach { issue ->
                    Column(Modifier.padding(vertical = 4.dp)) {
                        Text("【${issue.type}】${issue.location}", fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        Text("原句：${issue.original}", fontSize = 13.sp, color = originalColor)
                        Text("说明：${issue.explanation}", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("建议：${issue.suggestion}", fontSize = 13.sp, color = betterColor)
                    }
                }
            }
        }

        if (feedback.suggestions.isNotEmpty()) {
            Section("改进建议") {
                feedback.suggestions.forEachIndexed { i, sug -> Bullet("${i + 1}. $sug") }
            }
        }

        if (feedback.rewrites.isNotEmpty()) {
            Section("好句升级") {
                feedback.rewrites.forEach { r ->
                    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                        Text("原句：${r.original}", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("改写：${r.rewritten}", fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        Text("为什么更好：${r.why}", fontSize = 12.sp, color = betterColor)
                        Text(
                            text = "点此针对该句再改一次 ›",
                            fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .clickable { onRewriteSegment(r.original) },
                        )
                    }
                }
            }
        }

        if (feedback.sample.isNotBlank()) {
            Section("同类范文片段") {
                Text(feedback.sample, fontSize = 14.sp, lineHeight = 24.sp, color = MaterialTheme.colorScheme.onSurface)
            }
        }
    }
}

@Composable
fun ScoreRing(score: Int) {
    // iOS 风弹入：spring 缩放 + 淡入
    val scale = remember { Animatable(0.6f) }
    val alpha = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        scale.animateTo(1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = 300f))
        alpha.animateTo(1f, spring(dampingRatio = Spring.DampingRatioNoBouncy))
    }
    Box(
        modifier = Modifier
            .scale(scale.value)
            .alpha(alpha.value)
            .size(80.dp)
            .background(scoreColor(score), RoundedCornerShape(40.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("$score", color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Text("分", color = Color.White, fontSize = 12.sp)
        }
    }
}

@Composable
private fun ScoreBar(label: String, value: Int) {
    val fraction = (value.coerceIn(0, 25)) / 25f
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 3.dp)) {
        Text(label, fontSize = 13.sp, modifier = Modifier.width(44.dp))
        Box(
            Modifier
                .size(width = 120.dp, height = 8.dp)
                .background(Color(0xFFE5E7EB), RoundedCornerShape(4.dp))
        ) {
            Box(
                Modifier
                    .fillMaxWidth(fraction)
                    .fillMaxHeight()
                    .background(scoreColor((value * 4).coerceIn(0, 100)), RoundedCornerShape(4.dp))
            )
        }
        Spacer(Modifier.width(6.dp))
        Text("$value", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        shape = RoundedCornerShape(20.dp),
    ) {
        Column(Modifier.padding(14.dp)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.padding(bottom = 8.dp))
            content()
        }
    }
}

@Composable
private fun Bullet(text: String) {
    Text("• $text", fontSize = 14.sp, lineHeight = 22.sp, modifier = Modifier.padding(vertical = 2.dp))
}
