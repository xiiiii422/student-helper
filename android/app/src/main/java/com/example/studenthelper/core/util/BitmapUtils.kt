package com.example.studenthelper.core.util

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File

/** Bitmap 压缩 / Base64 / 旋转 工具。 */
object BitmapUtils {

    private const val MAX_DIMENSION = 2200      // 长边上限：语文阅读类密集小字需更高分辨率，8 Elite 算力充裕
    private const val JPEG_QUALITY = 85          // 压缩质量

    /** 从文件加载并压缩 Bitmap，处理 EXIF 旋转。 */
    fun loadCompressed(file: File, maxDimension: Int = MAX_DIMENSION): Bitmap {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, opts)
        var sample = 1
        val maxEdge = maxOf(opts.outWidth, opts.outHeight)
        while (maxEdge / sample > maxDimension) sample *= 2

        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = BitmapFactory.decodeFile(file.absolutePath, decodeOpts)
            ?: throw IllegalStateException("无法解码图片: ${file.absolutePath}")

        val rotation = ExifInterface(file.absolutePath)
            .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            .let { exifToDegrees(it) }
        if (rotation != 0) {
            val m = Matrix().apply { postRotate(rotation.toFloat()) }
            bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
        }
        return bmp
    }

    /** Bitmap -> 无 data 前缀的 JPEG base64。 */
    fun toBase64(bitmap: Bitmap, quality: Int = JPEG_QUALITY): String {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
        return android.util.Base64.encodeToString(out.toByteArray(), android.util.Base64.NO_WRAP)
    }

    /** 压缩保存到文件（JPEG）。 */
    fun saveCompressed(bitmap: Bitmap, dest: File, quality: Int = JPEG_QUALITY): File {
        dest.parentFile?.mkdirs()
        dest.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        return dest
    }

    private fun exifToDegrees(orientation: Int): Int = when (orientation) {
        ExifInterface.ORIENTATION_ROTATE_90 -> 90
        ExifInterface.ORIENTATION_ROTATE_180 -> 180
        ExifInterface.ORIENTATION_ROTATE_270 -> 270
        else -> 0
    }
}
