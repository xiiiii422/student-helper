package com.example.studenthelper.di

import android.content.Context
import androidx.room.Room
import com.example.studenthelper.data.local.AppDatabase
import com.example.studenthelper.data.local.dao.CompositionDao
import com.example.studenthelper.data.local.dao.FavoriteDao
import com.example.studenthelper.data.local.dao.MessageDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun database(@ApplicationContext ctx: Context): AppDatabase =
        Room.databaseBuilder(ctx, AppDatabase::class.java, AppDatabase.DB_NAME)
            .fallbackToDestructiveMigration()
            .build()

    @Provides
    fun messageDao(db: AppDatabase): MessageDao = db.messageDao()

    @Provides
    fun compositionDao(db: AppDatabase): CompositionDao = db.compositionDao()

    @Provides
    fun favoriteDao(db: AppDatabase): FavoriteDao = db.favoriteDao()
}
