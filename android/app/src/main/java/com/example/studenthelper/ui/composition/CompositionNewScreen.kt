package com.example.studenthelper.ui.composition

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import com.example.studenthelper.R
import com.example.studenthelper.core.util.FileStorage
import com.example.studenthelper.ui.components.rememberImagePickers
import com.example.studenthelper.ui.theme.CompositionAccent

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CompositionNewScreen(
    onBack: () -> Unit,
    onSubmitted: (Long) -> Unit,
    viewModel: CompositionNewViewModel = hiltViewModel(),
) {
    val draft by viewModel.draft.collectAsState()
    val submitting by viewModel.submitting.collectAsState()
    val ocrWorking by viewModel.ocrWorking.collectAsState()
    val error by viewModel.error.collectAsState()
    val navigatedId by viewModel.navigatedId.collectAsState()

    val context = androidx.compose.ui.platform.LocalContext.current
    val fileStorage = remember { FileStorage(context) }
    val snackbarHostState = remember { SnackbarHostState() }

    val pickers = rememberImagePickers(fileStorage = fileStorage) { file ->
        viewModel.addImage(file)
    }

    LaunchedEffect(navigatedId) {
        navigatedId?.let { onSubmitted(it) }
    }
    LaunchedEffect(error) {
        error?.let { snackbarHostState.showSnackbar(it); viewModel.consumeError() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            com.example.studenthelper.ui.components.IosNavBar(
                title = stringResource(R.string.composition_new),
                onBack = onBack,
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = draft.title,
                onValueChange = viewModel::setTitle,
                label = { Text(stringResource(R.string.composition_title_hint)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = draft.requirement,
                onValueChange = viewModel::setRequirement,
                label = { Text(stringResource(R.string.composition_requirement_hint)) },
                modifier = Modifier.fillMaxWidth(),
            )

            Text("作文照片（最多4张）", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // 次级动作用浅底钮：两个实心蓝会跟底部“开始批改”抢主操作
                FilledTonalButton(onClick = { pickers.launchCamera() }, enabled = !submitting) {
                    Icon(Icons.Filled.CameraAlt, null, modifier = Modifier.size(18.dp))
                    Text("拍照", modifier = Modifier.padding(start = 6.dp))
                }
                FilledTonalButton(onClick = { pickers.launchGallery() }, enabled = !submitting) {
                    Icon(Icons.Filled.Image, null, modifier = Modifier.size(18.dp))
                    Text("相册", modifier = Modifier.padding(start = 6.dp))
                }
            }
            if (ocrWorking) {
                Text("识别中…（可先编辑已识别内容）", color = CompositionAccent)
            }
            if (draft.imageFiles.isNotEmpty()) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(vertical = 4.dp)) {
                    itemsIndexed(draft.imageFiles) { index, file ->
                        Box {
                            AsyncImage(
                                model = file,
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(90.dp)
                                    .clip(RoundedCornerShape(8.dp)),
                            )
                            IconButton(
                                onClick = { viewModel.removeImage(index) },
                                modifier = Modifier.align(Alignment.TopEnd).size(24.dp),
                            ) {
                                Icon(
                                    Icons.Filled.Close,
                                    "删除",
                                    tint = MaterialTheme.colorScheme.error,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }
                }
            }

            OutlinedTextField(
                value = draft.content,
                onValueChange = viewModel::setContent,
                label = { Text("作文正文（识别后可修改，或直接输入）") },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(260.dp),
                minLines = 8,
            )

            Button(
                onClick = { viewModel.submit() },
                // 正文和照片都空时不给点：以前看着能点，点下去只弹一句“请先输入”，白挨一下
                enabled = !submitting && (draft.content.isNotBlank() || draft.imageFiles.isNotEmpty()),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (submitting) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    Text(
                        stringResource(R.string.composition_correcting),
                        modifier = Modifier.padding(start = 6.dp),
                    )
                } else {
                    Text(stringResource(R.string.composition_start_correct))
                }
            }
        }
    }
}
