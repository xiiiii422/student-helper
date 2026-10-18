package com.example.studenthelper.data.repository

import com.example.studenthelper.core.common.DispatcherProvider
import com.example.studenthelper.core.network.LlmClient
import com.example.studenthelper.domain.composition.FeedbackParser
import com.example.studenthelper.data.local.dao.CompositionDao
import com.example.studenthelper.data.local.entity.CompositionEntity
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

@Singleton
class CompositionRepository @Inject constructor(
    private val dao: CompositionDao,
    private val llm: LlmClient,
    private val dispatchers: DispatcherProvider,
) {
    fun observeAll(): Flow<List<CompositionEntity>> = dao.observeAll()

    suspend fun getById(id: Long): CompositionEntity? = withContext(dispatchers.io) {
        dao.getById(id)
    }

    suspend fun delete(c: CompositionEntity) = withContext(dispatchers.io) { dao.delete(c) }

    suspend fun clearAll() = withContext(dispatchers.io) { dao.clearAll() }

    /** 提交作文 → 拿到批改结果 → 落库，返回新记录 id。 */
    suspend fun submitAndSave(
        title: String,
        content: String,
        imageUrisJson: String,
        imagesBase64: List<String>,
        requirement: String?,
    ): Long = withContext(dispatchers.io) {
        val raw = llm.completeComposition(
            title = title,
            grade = "六年级",
            content = content,
            requirement = requirement,
            imagesBase64 = imagesBase64,   // 多页手稿全部上传，不再只发第一页
        )
        val score = FeedbackParser.parse(raw)?.totalScore ?: 0
        dao.insert(
            CompositionEntity(
                title = title.ifBlank { "未命名作文" },
                content = content,
                imageUris = imageUrisJson,
                aiFeedback = raw,   // 存原文，详情页再解析
                score = score,
            )
        )
    }

    suspend fun rewrite(text: String): String = withContext(dispatchers.io) {
        llm.completeRewrite(text)
    }
}
