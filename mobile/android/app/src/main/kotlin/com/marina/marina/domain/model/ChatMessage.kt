package com.marina.marina.domain.model

/**
 * A single message in the AI assistant chat.
 * UI-only model — not persisted to Room (chat history is session-scoped,
 * matching the Flutter app's in-memory chat list).
 */
data class ChatMessage(
    val id: Long = System.currentTimeMillis(),
    val text: String = "",
    val isFromUser: Boolean = true,
    val timestamp: Long = System.currentTimeMillis(),
    val isThinking: Boolean = false
)
