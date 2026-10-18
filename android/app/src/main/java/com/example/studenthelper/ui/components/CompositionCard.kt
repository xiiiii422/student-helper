package com.example.studenthelper.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.studenthelper.core.util.DateUtils
import com.example.studenthelper.data.local.entity.CompositionEntity
import com.example.studenthelper.ui.theme.ScoreExcellent
import com.example.studenthelper.ui.theme.ScoreFair
import com.example.studenthelper.ui.theme.ScoreGood
import com.example.studenthelper.ui.theme.ScorePoor
import com.example.studenthelper.ui.theme.SurfaceWhite
import com.example.studenthelper.ui.theme.TertiaryLabel

fun scoreColor(score: Int): Color = when {
    score >= 90 -> ScoreExcellent
    score >= 80 -> ScoreGood
    score >= 70 -> ScoreFair
    else -> ScorePoor
}

/** 澎湃 OS 风分组列表卡片：白底、20dp 圆角、无阴影、分数圆徽章；长按删除。 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun CompositionCard(
    item: CompositionEntity,
    firstImageUri: String?,
    summary: String?,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onLongClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(20.dp),
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (firstImageUri != null) {
                AsyncImage(
                    model = firstImageUri,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(width = 60.dp, height = 76.dp)
                        .clip(RoundedCornerShape(10.dp)),
                )
            }
            Column(Modifier.weight(1f)) {
                Text(item.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                Text(
                    summary ?: "点击查看批改",
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    modifier = Modifier.padding(vertical = 3.dp),
                )
                Text(DateUtils.format(item.created_at), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .background(scoreColor(item.score), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text("${item.score}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            }
        }
    }
}
