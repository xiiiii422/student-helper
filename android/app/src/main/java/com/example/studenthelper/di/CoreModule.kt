package com.example.studenthelper.di

import android.content.Context
import com.example.studenthelper.core.common.DefaultDispatcherProvider
import com.example.studenthelper.core.common.DispatcherProvider
import com.example.studenthelper.core.network.SettingsRepository
import com.example.studenthelper.core.util.FileStorage
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object CoreModule {

    @Provides
    @Singleton
    fun fileStorage(@ApplicationContext ctx: Context): FileStorage = FileStorage(ctx)

    @Provides
    @Singleton
    fun settingsRepository(@ApplicationContext ctx: Context): SettingsRepository =
        SettingsRepository(ctx)
}

@Module
@InstallIn(SingletonComponent::class)
abstract class DispatcherModule {
    @Binds
    @Singleton
    abstract fun dispatcher(impl: DefaultDispatcherProvider): DispatcherProvider
}
