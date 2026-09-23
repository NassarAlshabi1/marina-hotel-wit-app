package com.marina.marina.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.WorkerAuthInterceptor
import com.marina.marina.data.remote.WorkerEndpoints
import com.marina.marina.data.remote.WorkerFailoverInterceptor
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(
    name = "marina_sync_prefs"
)

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    /**
     * ✅ (2026-09-24) عميل HTTP بطبقتين فوق Retrofit:
     *  • [WorkerAuthInterceptor] — Authorization: Bearer <JWT> لكل مسارات
     *    المزامنة (التوكن من SyncPreferences؛ التوكن المحلي لا يُرسل) +
     *    X-Device-Id للتشخيص الخادمي.
     *  • [WorkerFailoverInterceptor] — تبديل تلقائي بين النطاق المخصّص
     *    وworkers.dev عند فشل الشبكة (حجب SNI اليمني) مع تثبيت الناجح.
     *
     * مهلة القراءة 60 ثانية (نفس ترقية Flutter 2026-09-17: المسار
     * الاحتياطي قد ينفق حتى 36 ثانية على الشبكات المتدهورة) والاتصال
     * 30 ثانية (عتبة الدخول الكسول على شبكات ضعيفة).
     */
    @Provides
    @Singleton
    fun provideOkHttpClient(
        endpoints: WorkerEndpoints,
        preferences: com.marina.marina.data.remote.SyncPreferences
    ): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .addInterceptor(
                WorkerAuthInterceptor(
                    tokenProvider = { preferences.getAuthToken() },
                    deviceIdProvider = { preferences.getDeviceId() }
                )
            )
            .addInterceptor(WorkerFailoverInterceptor(endpoints))
            .build()
    }

    /**
     * Retrofit مبني على النقطة المدمجة — [WorkerFailoverInterceptor] يُعيد
     * كتابة كل طلب worker إلى النقطة الفعّالة (نطاق مخصّص إن وُضع) قبل
     * الإرسال، فالتبديل شفاف تماماً لكل بُناة الروابط.
     */
    @Provides
    @Singleton
    fun provideRetrofit(client: OkHttpClient): Retrofit {
        return Retrofit.Builder()
            .baseUrl(CloudflareConfig.BUILTIN_WORKER_URL + "/")
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
 * auth tokens / device ids. [com.marina.marina.data.remote.CloudflareSyncService]
 * and [com.marina.marina.data.remote.SyncPreferences] declare their own
 * `@Inject constructor`, so they are NOT provided here — doing so would
 * create a duplicate Hilt binding.
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
