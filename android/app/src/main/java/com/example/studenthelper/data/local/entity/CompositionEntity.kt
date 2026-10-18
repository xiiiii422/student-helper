package com.example.studenthelper.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "compositions",
    indices = [Index("created_at")]
)
data class CompositionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val content: String,              // 识别后的作文文字（可编辑）
    val imageUris: String,            // JSON 数组字符串（本地图片路径）
    val aiFeedback: String,           // JSON 字符串（AI 完整批改），解析失败时存原文
    val score: Int = 0,
    val created_at: Long = System.currentTimeMillis(),
)
