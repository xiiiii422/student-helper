package com.example.studenthelper.ui.me

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.FolderZip
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.Unarchive
import androidx.compose.material.icons.outlined.WifiTethering
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.example.studenthelper.core.network.PingResult
import com.example.studenthelper.ui.theme.EnglishAccent
import com.example.studenthelper.ui.theme.HyperTextTertiary
import com.example.studenthelper.ui.theme.MiBlue
import com.example.studenthelper.ui.theme.MiOrange
import com.example.studenthelper.ui.theme.ScorePoor
import com.example.studenthelper.ui.theme.StatusOk

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeScreen(
    onOpenFavorites: () -> Unit,
    onOpenSettings: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val message by viewModel.message.collectAsState()
    val exportedFile by viewModel.exportedFile.collectAsState()
    val restartRequired by viewModel.restartRequired.collectAsState()
    val pinging by viewModel.pinging.collectAsState()
    val pingResults by viewModel.pingResults.collectAsState()

    val snackbarHostState = remember { SnackbarHostState() }
    var showClearConfirm by remember { mutableStateOf(false) }
    var showAbout by remember { mutableStateOf(false) }

    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let { viewModel.importData(context, it) } }

    LaunchedEffect(message) {
        message?.let { snackbarHostState.showSnackbar(it); viewModel.consumeMessage() }
    }

    // 导出成功 → 拉起系统分享
    LaunchedEffect(exportedFile) {
        exportedFile?.let { file ->
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "application/zip"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(Intent.createChooser(share, "分享备份"))
            viewModel.consumeExportedFile()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            com.example.studenthelper.ui.components.IosLargeTitle(title = "我的")
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                shape = RoundedCornerShape(20.dp),
            ) {
                Column(Modifier.padding(16.dp)) {
                    Text("学习小助手", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.onSurface)
                    Text("自用版 · 数据仅存本机", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Spacer(Modifier.height(16.dp))

            // 外观模式（澎湃 OS 深色支持）
            Text(
                "外观",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 20.dp, bottom = 6.dp),
            )
            MenuCard {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    val mode by viewModel.themeMode.collectAsState()
                    listOf(0 to "跟随系统", 1 to "浅色", 2 to "深色").forEach { (value, label) ->
                        FilterChip(
                            selected = mode == value,
                            onClick = { viewModel.setThemeMode(value) },
                            label = { Text(label) },
                        )
                    }
                }
            }
            Spacer(Modifier.height(16.dp))

            MenuCard {
                MenuItem("错题本", Icons.Outlined.CollectionsBookmark, MiBlue) { onOpenFavorites() }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                MenuItem("模型服务设置", Icons.Outlined.Tune, MiBlue) { onOpenSettings() }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                // 点击后到出结果可多达半分钟，没任何反馈会被当成卡死；结果也常驻在这一行
                MenuItem(
                    "连接测试",
                    Icons.Outlined.WifiTethering,
                    EnglishAccent,
                    trailing = { PingStatus(pinging, pingResults) },
                ) { viewModel.ping() }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                MenuItem("导出数据（zip）", Icons.Outlined.FolderZip, MiOrange) { viewModel.exportData() }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                MenuItem("导入数据（zip）", Icons.Outlined.Unarchive, MiOrange) {
                    importLauncher.launch(arrayOf("application/zip", "application/x-zip-compressed", "*/*"))
                }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                MenuItem("清空所有数据", Icons.Outlined.DeleteOutline, ScorePoor, danger = true) { showClearConfirm = true }
                HorizontalDivider(Modifier.padding(start = 56.dp))
                MenuItem("关于", Icons.Outlined.Info, HyperTextTertiary) { showAbout = true }
            }

            if (restartRequired) {
                Spacer(Modifier.height(16.dp))
                Button(onClick = {
                    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    intent?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    context.startActivity(intent)
                    Runtime.getRuntime().exit(0)
                }, modifier = Modifier.fillMaxWidth()) {
                    Text("导入完成 · 点我重启生效")
                }
            }
        }
    }

    if (showAbout) {
        AlertDialog(
            onDismissRequest = { showAbout = false },
            title = { Text("学习小助手") },
            text = {
                Column {
                    Text("版本 1.0.0（自用版）")
                    Spacer(Modifier.height(6.dp))
                    Text("面向小学六年级的试题讲解与作文批改助手。数据仅存本机，可在本页导出备份。")
                }
            },
            confirmButton = { TextButton(onClick = { showAbout = false }) { Text("知道了") } },
        )
    }

    if (showClearConfirm) {
        AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            title = { Text("确认清空？") },
            text = { Text("将删除所有消息、作文、错题与图片，且不可恢复。建议先导出备份。") },
            confirmButton = {
                TextButton(onClick = { viewModel.clearAll(); showClearConfirm = false }) {
                    Text("确认清空", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { showClearConfirm = false }) { Text("取消") } },
        )
    }
}

@Composable
private fun MenuCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        shape = RoundedCornerShape(20.dp),
    ) {
        Column(Modifier.padding(vertical = 4.dp)) { content() }
    }
}

@Composable
private fun MenuItem(
    text: String,
    icon: ImageVector,
    iconTint: Color,
    danger: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(30.dp)
                .clip(RoundedCornerShape(9.dp))
                .background(iconTint.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.size(18.dp),
            )
        }
        Text(
            text = text,
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
            fontSize = 16.sp,
            color = if (danger) scheme.error else scheme.onSurface,
        )
        if (trailing != null) {
            trailing()
        } else {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = scheme.onSurfaceVariant.copy(alpha = 0.45f),
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

/**
 * “连接测试”行尾状态：没测过给个箭头，测中转圈，测完每家一个绿/红点。
 * 不拿 chevron 给一个不会跳转的动作用——那是“还有下一页”的意思。
 */
@Composable
private fun PingStatus(pinging: Boolean, results: List<PingResult>) {
    val scheme = MaterialTheme.colorScheme
    when {
        pinging -> CircularProgressIndicator(
            modifier = Modifier.size(15.dp),
            strokeWidth = 2.dp,
            color = scheme.onSurfaceVariant,
        )
        results.isEmpty() -> Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = scheme.onSurfaceVariant.copy(alpha = 0.45f),
            modifier = Modifier.size(18.dp),
        )
        else -> Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            results.forEach { r ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(if (r.ok) StatusOk else scheme.error)
                    )
                    Text(
                        r.provider,
                        fontSize = 12.sp,
                        color = scheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            }
        }
    }
}
