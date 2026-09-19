package com.marina.marina.presentation.aichat

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.remote.GeminiService
import com.marina.marina.domain.model.ChatMessage
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AiChatUiState(
    val messages: List<ChatMessage> = emptyList(),
    val isThinking: Boolean = false,
    val apiKey: String = "",
    val isConfigured: Boolean = false,
    val error: String? = null
) {
    val suggestions: List<String> = listOf(
        "ملخص تقرير اليوم",
        "الغرف الشاغرة حالياً",
        "حجوزات اليوم الجديدة",
        "ديون العملاء المعلقة"
    )
}

@HiltViewModel
class AIChatViewModel @Inject constructor(
    private val geminiService: GeminiService
) : ViewModel() {

    private val _state = MutableStateFlow(
        AiChatUiState(
            messages = listOf(
                ChatMessage(
                    text = "مرحباً! أنا المساعد الذكي لفندق مارينا 🏨\nاسألني عن الحجوزات والمدفوعات والتقارير.",
                    isFromUser = false
                )
            ),
            isConfigured = geminiService.isConfigured()
        )
    )
    val state: StateFlow<AiChatUiState> = _state.asStateFlow()

    fun updateApiKeyDraft(key: String) {
        _state.value = _state.value.copy(apiKey = key)
    }

    fun saveApiKey() {
        val key = _state.value.apiKey.trim()
        if (key.isBlank()) return
        geminiService.saveApiKey(key)
        _state.value = _state.value.copy(isConfigured = true, error = null)
    }

    fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isBlank() || _state.value.isThinking) return

        val history = _state.value.messages
        val userMessage = ChatMessage(text = trimmed, isFromUser = true)
        _state.value = _state.value.copy(messages = history + userMessage, isThinking = true, error = null)

        viewModelScope.launch {
            val conversation = (_state.value.messages)
                .filter { !it.isThinking }
                .map { it.text to it.isFromUser }
            val result = geminiService.chat(conversation)
            result.fold(
                onSuccess = { reply ->
                    _state.value = _state.value.copy(
                        messages = _state.value.messages + ChatMessage(text = reply, isFromUser = false),
                        isThinking = false
                    )
                },
                onFailure = { e ->
                    _state.value = _state.value.copy(
                        messages = _state.value.messages + ChatMessage(
                            text = "تعذر الاتصال بالمساعد: ${e.message}",
                            isFromUser = false
                        ),
                        isThinking = false,
                        error = e.message
                    )
                }
            )
        }
    }

    fun clearChat() {
        _state.value = _state.value.copy(
            messages = listOf(
                ChatMessage(
                    text = "بدأت محادثة جديدة. كيف أساعدك؟",
                    isFromUser = false
                )
            )
        )
    }
}
