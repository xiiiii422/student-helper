package com.example.studenthelper.domain.usecase

import android.content.Context
import com.example.studenthelper.core.util.FileStorage
import com.example.studenthelper.data.local.AppDatabase
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 导出：把 Room db 文件 + images 目录打包成 zip 到 exports/。
 * 导入：从用户选定的 zip 恢复 db 与 images（覆盖式）。
 *
 * 注意：导入前应关闭数据库（自用场景通常在 App 冷启动时提示恢复并重启进程）。
 */
@Singleton
class BackupManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val fileStorage: FileStorage,
) {
    private val dbFile get() = File(context.getDatabasePath(AppDatabase.DB_NAME).absolutePath)

    suspend fun exportZip(): File = withContext(Dispatchers.IO) {
        // 确保 WAL 数据落盘
        stampCheckpoints()
        val out = File(
            fileStorage.exportsDir,
            "student_helper_" +
                SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".zip"
        )
        ZipOutputStream(FileOutputStream(out)).use { zos ->
            // 1. db 文件
            if (dbFile.exists()) {
                zos.putNextEntry(ZipEntry(DB_ENTRY))
                FileInputStream(dbFile).use { it.copyTo(zos) }
                zos.closeEntry()
            }
            // 2. images 目录
            val imgDir = fileStorage.imagesDir()
            if (imgDir.exists()) {
                imgDir.walkTopDown().filter { it.isFile }.forEach { f ->
                    zos.putNextEntry(ZipEntry("$IMG_ENTRY${f.name}"))
                    FileInputStream(f).use { it.copyTo(zos) }
                    zos.closeEntry()
                }
            }
        }
        out
    }

    /** 将 zip 内容写入正确位置（db + images），调用方随后应结束进程重启。 */
    suspend fun importZip(zip: File): Boolean = withContext(Dispatchers.IO) {
        try {
            ZipInputStream(FileInputStream(zip)).use { zis ->
                var entry = zis.nextEntry
                while (entry != null) {
                    when {
                        entry.name == DB_ENTRY -> {
                            dbFile.parentFile?.mkdirs()
                            FileOutputStream(dbFile).use { zis.copyTo(it) }
                        }
                        entry.name.startsWith(IMG_ENTRY) -> {
                            val target = File(fileStorage.imagesDir(), File(entry.name).name)
                            target.parentFile?.mkdirs()
                            FileOutputStream(target).use { zis.copyTo(it) }
                        }
                    }
                    zis.closeEntry()
                    entry = zis.nextEntry
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    /** 清空所有业务数据（表 + 图片），保留后端配置。 */
    suspend fun clearAll(clearTables: suspend () -> Unit) = withContext(Dispatchers.IO) {
        clearTables()
        fileStorage.imagesDir().deleteRecursively()
        fileStorage.imagesDir().mkdirs()
    }

    private fun stampCheckpoints() {
        runCatching {
            // 触发 WAL checkpoint，保证主 db 文件包含所有数据
            context.openOrCreateDatabase(AppDatabase.DB_NAME, Context.MODE_PRIVATE, null).close()
        }
    }

    companion object {
        private const val DB_ENTRY = "student_helper.db"
        private const val IMG_ENTRY = "images/"
    }
}
