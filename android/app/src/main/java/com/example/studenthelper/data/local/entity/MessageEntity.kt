package com.example.studenthelper.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "messages",
    indices = [Index("subject"), Index("created_at")]
)
data class MessageEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val subject: String,          // "chinese" / "math" / "english"
    val role: String,             // "user" / "assistant"
    val textContent: String,
    val imageUri: String? = null, // 本地文件绝对路径
    val ocrConfidence: Float? = null,
    val isStreaming: Boolean = false,
    val created_at: Long = System.currentTimeMillis(),
)
