package com.example.studenthelper.core.util

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** 管理 App 内部私有目录下的图片与导出文件。 */
class FileStorage(private val context: Context) {

    private val imagesDir: File by lazy {
        File(context.filesDir, "images").apply { mkdirs() }
    }
    val exportsDir: File by lazy {
        File(context.filesDir, "exports").apply { mkdirs() }
    }

    /** 生成一张新图片文件（未写入），文件名带时间戳。 */
    fun newImageFile(prefix: String = "img"): File {
        val ts = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())
        return File(imagesDir, "${prefix}_$ts.jpg")
    }

    fun imageByName(name: String): File = File(imagesDir, name)
    fun imagesDir(): File = imagesDir

    /** 删除单张图片。 */
    fun deleteImage(path: String?) {
        if (path.isNullOrBlank()) return
        runCatching { File(path).takeIf { it.exists() }?.delete() }
    }
}

object DateUtils {
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
    private val fileStamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)

    fun format(ts: Long): String = dateFormat.format(Date(ts))
    fun fileStamp(ts: Long = System.currentTimeMillis()): String = fileStamp.format(Date(ts))
}
