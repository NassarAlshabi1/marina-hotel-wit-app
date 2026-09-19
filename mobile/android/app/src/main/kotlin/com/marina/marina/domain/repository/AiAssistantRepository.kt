package com.marina.marina.domain.repository

interface AiAssistantRepository {
    fun isConfigured(): Boolean
    fun getApiKey(): String?
    fun saveApiKey(key: String)
    suspend fun chat(history: List<Pair<String, Boolean>>): Result<String>
}
