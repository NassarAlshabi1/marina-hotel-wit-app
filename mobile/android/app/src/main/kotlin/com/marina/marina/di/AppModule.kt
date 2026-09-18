package com.marina.marina.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.marina.marina.data.remote.CloudflareWorkerApi
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(
    name = "marina_sync_prefs"
)

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideRetrofit(): Retrofit {
        return Retrofit.Builder()
            .baseUrl("https://marina-hotel-api.adenmarina2.workers.dev/")
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    @Provides
    @Singleton
    fun provideWorkerApi(retrofit: Retrofit): CloudflareWorkerApi =
        retrofit.create(CloudflareWorkerApi::class.java)
}

/**
 * Thin wrapper around [android.content.SharedPreferences] used to persist
 * auth tokens / device ids. [CloudflareSyncService] and [SyncPreferences]
 * declare their own `@Inject constructor`, so they are NOT provided here —
 * doing so would create a duplicate Hilt binding.
 */
@Singleton
class EncryptedSharedPreferencesManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val PREFS_NAME = "marina_secure_prefs"
    }

    private fun prefs() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveString(key: String, value: String) {
        prefs().edit().putString(key, value).apply()
    }

    fun getString(key: String): String? {
        return prefs().getString(key, null)
    }

    fun saveLong(key: String, value: Long) {
        prefs().edit().putLong(key, value).apply()
    }

    fun getLong(key: String, default: Long): Long {
        return prefs().getLong(key, default)
    }

    fun getBoolean(key: String, default: Boolean): Boolean {
        return prefs().getBoolean(key, default)
    }

    fun putBoolean(key: String, value: Boolean) {
        prefs().edit().putBoolean(key, value).apply()
    }
}
