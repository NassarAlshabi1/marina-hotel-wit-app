package com.marina.marina.data.remote

import com.google.gson.annotations.SerializedName
import com.marina.marina.di.EncryptedSharedPreferencesManager
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.POST
import retrofit2.http.Query

// ---------------------------------------------------------------------------
// Gemini REST contract (v1beta generateContent)
// ---------------------------------------------------------------------------

data class GeminiContent(
    @SerializedName("role") val role: String? = null,
    @SerializedName("parts") val parts: List<GeminiPart>
)

data class GeminiPart(
    @SerializedName("text") val text: String
)

data class GeminiRequest(
    @SerializedName("contents") val contents: List<GeminiContent>,
    @SerializedName("systemInstruction") val systemInstruction: GeminiContent? = null
)

data class GeminiResponse(
    @SerializedName("candidates") val candidates: List<GeminiCandidate>?
)

data class GeminiCandidate(
    @SerializedName("content") val content: GeminiContent?
)

interface GeminiApi {
    @POST("v1beta/models/gemini-2.5-flash:generateContent")
    suspend fun generateContent(
        @Query("key") apiKey: String,
        @Body request: GeminiRequest
    ): retrofit2.Response<GeminiResponse>
}

/**
 * Thin client for the Gemini AI assistant — the Kotlin counterpart of the
 * Flutter `GeminiService`. The API key is stored locally (SharedPreferences)
 * and editable from the chat screen.
 */
@Singleton
class GeminiService @Inject constructor(
    private val preferencesManager: EncryptedSharedPreferencesManager
) {
    companion object {
        private const val PREFS_KEY = "gemini_api_key"
        private const val BASE_URL = "https://generativelanguage.googleapis.com/"
        private val SYSTEM_INSTRUCTION = GeminiContent(
            role = "user",
            parts = listOf(
                GeminiPart(
                    "أنت مساعد ذكي لنظام إدارة فندق مارينا. أجب دائماً باللغة العربية بإيجاز ووضوح، " +
                        "وساعد الموظفين في إدارة الحجوزات والمدفوعات والغرف والمصروفات والتقارير اليومية."
                )
            )
        )
    }

    private val api: GeminiApi by lazy {
        Retrofit.Builder()
            .baseUrl(BASE_URL)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(GeminiApi::class.java)
    }

    fun getApiKey(): String? = preferencesManager.getString(PREFS_KEY)

    fun saveApiKey(key: String) = preferencesManager.saveString(PREFS_KEY, key.trim())

    fun isConfigured(): Boolean = !getApiKey().isNullOrBlank()

    /**
     * Sends the full conversation and returns the assistant reply text.
     * Returns null when the key is missing or the call fails.
     */
    suspend fun chat(history: List<Pair<String, Boolean>>): Result<String> = withContext(Dispatchers.IO) {
        val apiKey = getApiKey()
        if (apiKey.isNullOrBlank()) {
            return@withContext Result.failure(IllegalStateException("مفتاح API غير مضبوط"))
        }
        val contents = history.map { (text, isFromUser) ->
            GeminiContent(
                role = if (isFromUser) "user" else "model",
                parts = listOf(GeminiPart(text))
            )
        }
        try {
            val response = api.generateContent(apiKey, GeminiRequest(contents, SYSTEM_INSTRUCTION))
            if (response.isSuccessful) {
                val reply = response.body()?.candidates
                    ?.firstOrNull()
                    ?.content?.parts
                    ?.joinToString("\n") { it.text }
                    .orEmpty()
                if (reply.isBlank()) {
                    Result.failure(IllegalStateException("لم يرد المساعد بأي نص"))
                } else {
                    Result.success(reply)
                }
            } else {
                Result.failure(IllegalStateException("خطأ من الخدمة: HTTP ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
