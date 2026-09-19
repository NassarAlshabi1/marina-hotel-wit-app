package com.marina.marina.domain.usecase.ai

import com.marina.marina.domain.repository.AiAssistantRepository
import javax.inject.Inject

class ChatWithAssistantUseCase @Inject constructor(
    private val assistant: AiAssistantRepository
) {
    suspend operator fun invoke(history: List<Pair<String, Boolean>>): Result<String> =
        assistant.chat(history)
}

class SaveAiApiKeyUseCase @Inject constructor(
    private val assistant: AiAssistantRepository
) {
    operator fun invoke(key: String) = assistant.saveApiKey(key.trim())
}
