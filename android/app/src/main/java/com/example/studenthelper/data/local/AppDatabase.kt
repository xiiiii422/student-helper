package com.example.studenthelper.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.example.studenthelper.data.local.dao.CompositionDao
import com.example.studenthelper.data.local.dao.FavoriteDao
import com.example.studenthelper.data.local.dao.MessageDao
import com.example.studenthelper.data.local.entity.CompositionEntity
import com.example.studenthelper.data.local.entity.FavoriteEntity
import com.example.studenthelper.data.local.entity.MessageEntity

@Database(
    entities = [
        MessageEntity::class,
        CompositionEntity::class,
        FavoriteEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun messageDao(): MessageDao
    abstract fun compositionDao(): CompositionDao
    abstract fun favoriteDao(): FavoriteDao

    companion object {
        const val DB_NAME = "student_helper.db"
    }
}
