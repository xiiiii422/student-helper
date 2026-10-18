package com.example.studenthelper.data.local.dao

import androidx.room.Dao
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.studenthelper.data.local.entity.FavoriteEntity
import kotlinx.coroutines.flow.Flow

/** 收藏 + 关联消息的联表视图。 */
data class FavoriteWithMessage(
    @Embedded val favorite: FavoriteEntity,
    val msgTextContent: String,
    val msgImageUri: String?,
    val msgCreatedAt: Long,
)

@Dao
interface FavoriteDao {
    @Query(
        """
        SELECT f.*, 
               m.textContent AS msgTextContent,
               m.imageUri AS msgImageUri,
               m.created_at AS msgCreatedAt
        FROM favorites f
        INNER JOIN messages m ON f.message_id = m.id
        ORDER BY f.created_at DESC
        """
    )
    fun observeAllWithMessage(): Flow<List<FavoriteWithMessage>>

    @Query(
        """
        SELECT f.*, 
               m.textContent AS msgTextContent,
               m.imageUri AS msgImageUri,
               m.created_at AS msgCreatedAt
        FROM favorites f
        INNER JOIN messages m ON f.message_id = m.id
        WHERE f.subject = :subject
        ORDER BY f.created_at DESC
        """
    )
    fun observeBySubject(subject: String): Flow<List<FavoriteWithMessage>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(f: FavoriteEntity): Long

    @Query("DELETE FROM favorites WHERE message_id = :msgId")
    suspend fun deleteByMessageId(msgId: Long)

    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE message_id = :msgId)")
    suspend fun isFavorited(msgId: Long): Boolean

    @Query("SELECT message_id FROM favorites WHERE subject = :subject")
    suspend fun favoritedMessageIds(subject: String): List<Long>

    @Query("DELETE FROM favorites")
    suspend fun clearAll()
}
