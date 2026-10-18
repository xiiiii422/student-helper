package com.example.studenthelper.ui.components

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import com.example.studenthelper.core.util.FileStorage
import java.io.File

/**
 * 封装"拍照"与"从相册选图"，回调统一给出保存到本地 imagesDir 后的 File。
 * 拍照：先建空文件 → FileProvider Uri → TakePicture 写入。
 * 相册：PickVisualMedia → 拷贝到 imagesDir 新文件。
 */
data class ImagePickers(
    val launchCamera: () -> Unit,
    val launchGallery: () -> Unit,
)

@Composable
fun rememberImagePickers(
    fileStorage: FileStorage,
    onImageSaved: (File) -> Unit,
): ImagePickers {
    val context = LocalContext.current
    var pendingCameraFile by remember { mutableStateOf<File?>(null) }

    val cameraLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { success ->
        val f = pendingCameraFile
        if (success && f != null && f.exists()) onImageSaved(f)
    }

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri != null) {
            val dest = fileStorage.newImageFile(prefix = "gallery")
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    dest.outputStream().use { output -> input.copyTo(output) }
                }
            }
            if (dest.exists()) onImageSaved(dest)
        }
    }

    return ImagePickers(
        launchCamera = {
            val target = fileStorage.newImageFile(prefix = "cam")
            target.parentFile?.mkdirs()
            runCatching { target.createNewFile() }
            pendingCameraFile = target
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", target)
            cameraLauncher.launch(uri)
        },
        launchGallery = {
            galleryLauncher.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
            )
        },
    )
}
