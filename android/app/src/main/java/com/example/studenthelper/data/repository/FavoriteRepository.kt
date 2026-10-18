package com.example.studenthelper.data.repository

import com.example.studenthelper.core.common.DispatcherProvider
import com.example.studenthelper.core.common.Subject
import com.example.studenthelper.data.local.dao.FavoriteDao
import com.example.studenthelper.data.local.dao.FavoriteWithMessage
import com.example.studenthelper.data.local.entity.FavoriteEntity
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

@Singleton
class FavoriteRepository @Inject constructor(
    private val dao: FavoriteDao,
    private val dispatchers: DispatcherProvider,
) {
    fun observeAll(): Flow<List<FavoriteWithMessage>> = dao.observeAllWithMessage()

    fun observeBySubject(subject: Subject): Flow<List<FavoriteWithMessage>> =
        dao.observeBySubject(subject.apiValue)

    suspend fun isFavorited(messageId: Long): Boolean =
        withContext(dispatchers.io) { dao.isFavorited(messageId) }

    /** 某学科全部已收藏的消息 id，供聊天页星标图标态初始化。 */
    suspend fun favoritedMessageIds(subject: Subject): Set<Long> =
        withContext(dispatchers.io) { dao.favoritedMessageIds(subject.apiValue).toSet() }

    /** 切换收藏状态，返回切换后是否为收藏。 */
    suspend fun toggle(messageId: Long, subject: Subject, note: String = ""): Boolean =
        withContext(dispatchers.io) {
            if (dao.isFavorited(messageId)) {
                dao.deleteByMessageId(messageId)
                false
            } else {
                dao.insert(FavoriteEntity(message_id = messageId, subject = subject.apiValue, note = note))
                true
            }
        }

    suspend fun clearAll() = withContext(dispatchers.io) { dao.clearAll() }
}
