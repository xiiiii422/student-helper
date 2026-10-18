package com.example.studenthelper.data.local.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import com.example.studenthelper.data.local.entity.CompositionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface CompositionDao {
    @Query("SELECT * FROM compositions ORDER BY created_at DESC")
    fun observeAll(): Flow<List<CompositionEntity>>

    @Insert
    suspend fun insert(c: CompositionEntity): Long

    @Query("SELECT * FROM compositions WHERE id = :id")
    suspend fun getById(id: Long): CompositionEntity?

    @Delete
    suspend fun delete(c: CompositionEntity)

    @Query("DELETE FROM compositions")
    suspend fun clearAll()
}
