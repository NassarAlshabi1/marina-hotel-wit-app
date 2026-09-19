package com.marina.marina.data.ai

import com.marina.marina.data.remote.GeminiService
import com.marina.marina.domain.repository.AiAssistantRepository
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AiAssistantRepositoryImpl @Inject constructor(
    private val geminiService: GeminiService
) : AiAssistantRepository {

    override fun isConfigured(): Boolean = geminiService.isConfigured()

    override fun getApiKey(): String? = geminiService.getApiKey()

    override fun saveApiKey(key: String) = geminiService.saveApiKey(key)

    override suspend fun chat(history: List<Pair<String, Boolean>>): Result<String> =
        geminiService.chat(history)
}
