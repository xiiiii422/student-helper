package com.example.studenthelper.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import com.example.studenthelper.data.local.entity.MessageEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MessageDao {
    @Query("SELECT * FROM messages WHERE subject = :subject ORDER BY created_at ASC")
    fun observeBySubject(subject: String): Flow<List<MessageEntity>>

    @Insert
    suspend fun insert(msg: MessageEntity): Long

    @Update
    suspend fun update(msg: MessageEntity)

    @Query("DELETE FROM messages WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM messages WHERE subject = :subject")
    suspend fun clearSubject(subject: String)

    @Query("SELECT * FROM messages WHERE subject = :subject ORDER BY created_at DESC LIMIT :limit")
    suspend fun getRecent(subject: String, limit: Int): List<MessageEntity>

    @Query("SELECT * FROM messages WHERE id = :id")
    suspend fun getById(id: Long): MessageEntity?

    /** 启动时清理：删除流式中断留下的空占位消息。 */
    @Query("DELETE FROM messages WHERE subject = :subject AND role = 'assistant' AND textContent = '' AND isStreaming = 1")
    suspend fun deleteEmptyStreamingPlaceholders(subject: String): Int

    /** 启动时清理：把残留的流式消息定稿，保留已落盘的部分回答。 */
    @Query("UPDATE messages SET isStreaming = 0 WHERE subject = :subject AND isStreaming = 1")
    suspend fun finalizeStaleStreaming(subject: String): Int

    @Query("DELETE FROM messages")
    suspend fun clearAll()
}
