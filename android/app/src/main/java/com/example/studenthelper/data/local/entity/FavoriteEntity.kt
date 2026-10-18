package com.example.studenthelper.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "favorites",
    foreignKeys = [ForeignKey(
        entity = MessageEntity::class,
        parentColumns = ["id"],
        childColumns = ["message_id"],
        onDelete = ForeignKey.CASCADE
    )],
    indices = [Index("message_id", unique = true), Index("subject")]
)
data class FavoriteEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val message_id: Long,
    val subject: String,
    val note: String = "",
    val created_at: Long = System.currentTimeMillis(),
)
