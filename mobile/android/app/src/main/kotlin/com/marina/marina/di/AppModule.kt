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

    /**
     * Worker JWT auth: the Cloudflare Worker requires
     * `Authorization: Bearer <jwt>` on every authenticated endpoint
     * (worker/src/auth.ts l.250-262 — requireAuth). The token is produced by
     * /api/auth/login and persisted by SyncPreferences; this interceptor
     * attaches it to EVERY outgoing request so push/pull/d1 calls pass the
     * 401 gate. Without it none of the sync استدعائات ever authenticate.
     */
    @Provides
    @Singleton
    fun provideAuthInterceptor(preferences: com.marina.marina.data.remote.SyncPreferences): okhttp3.Interceptor {
        return okhttp3.Interceptor { chain ->
            val token = runCatching { preferences.getAuthToken() }.getOrNull()
            val request = if (!token.isNullOrBlank() && chain.request().header("Authorization") == null) {
                chain.request().newBuilder()
                    .header("Authorization", "Bearer $token")
                    .header("X-Device-Id", preferences.getDeviceId() ?: "")
                    .build()
            } else {
                chain.request()
            }
            chain.proceed(request)
        }
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(authInterceptor: okhttp3.Interceptor): okhttp3.OkHttpClient {
        return okhttp3.OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .connectTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .writeTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
            .build()
    }

    @Provides
    @Singleton
    fun provideRetrofit(client: okhttp3.OkHttpClient): Retrofit {
        return Retrofit.Builder()
            .baseUrl("https://marina-hotel-api.adenmarina2.workers.dev/")
            .client(client)
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
