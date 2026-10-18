package com.example.studenthelper.ui.me

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.example.studenthelper.ui.components.IosNavBar

/**
 * 模型服务设置（直连模式）：供应商预设一键切换 + 自定义 base/key/模型名。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val form by viewModel.form.collectAsState()
    val message by viewModel.message.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(message) {
        message?.let { snackbarHostState.showSnackbar(it); viewModel.consumeMessage() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = { IosNavBar(title = "模型服务设置", onBack = onBack) },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("供应商预设", style = MaterialTheme.typography.headlineSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                viewModel.presets.forEach { preset ->
                    FilterChip(
                        selected = form.providerId == preset.id,
                        onClick = { viewModel.selectPreset(preset) },
                        label = { Text(preset.label) },
                    )
                }
            }
            Text(
                "切换预设后自动填入对应接口地址与模型名；Key 使用内置默认值，也可在下方修改。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            OutlinedTextField(
                value = form.baseUrl,
                onValueChange = viewModel::setBaseUrl,
                label = { Text("接口地址（Base URL）") },
                placeholder = { Text("https://open.bigmodel.cn/api/paas/v4") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = form.apiKey,
                onValueChange = viewModel::setApiKey,
                label = { Text("API Key") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
            )
            OutlinedTextField(
                value = form.chatModel,
                onValueChange = viewModel::setChatModel,
                label = { Text("文本模型（讲题/批改）") },
                placeholder = { Text("glm-4.7-flash") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = form.vlModel,
                onValueChange = viewModel::setVlModel,
                label = { Text("视觉模型（拍照识题）") },
                placeholder = { Text("glm-4v-flash") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(onClick = viewModel::saveConfig, modifier = Modifier.weight(1f)) {
                    Text("保存")
                }
                OutlinedButton(onClick = viewModel::ping, modifier = Modifier.weight(1f)) {
                    Text("连接测试", color = MaterialTheme.colorScheme.primary)
                }
            }

            Text(
                "说明：App 直连大模型服务，无需电脑。Key 明文存于本机（自用版设计），请勿公开分发本应用。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
