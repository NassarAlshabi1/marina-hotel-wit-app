package com.marina.marina.presentation.aichat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.domain.model.ChatMessage
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.MarinaTheme
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val chatTimeFormat = SimpleDateFormat("HH:mm", Locale.US)

@Composable
fun AIChatScreen(
    viewModel: AIChatViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    var input by remember { mutableStateOf("") }
    var showSettings by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    // Auto-scroll to the latest message.
    LaunchedEffect(state.messages.size, state.isThinking) {
        if (state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.size - 1)
        }
    }

    MarinaTheme {
        Scaffold(
            containerColor = AppColors.BackgroundColor,
            topBar = {
                TopAppBar(
                    title = { Text("المساعد الذكي", style = AppTypography.titleLarge) },
                    navigationIcon = {
                        TextButton(onClick = viewModel::clearChat) {
                            Text("مسح", color = AppColors.DangerColor, fontSize = 13.sp)
                        }
                    },
                    actions = {
                        TextButton(onClick = { showSettings = true }) {
                            Text("⚙ الإعدادات", color = AppColors.PrimaryColor, fontSize = 13.sp)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = AppColors.SurfaceColor,
                        titleContentColor = AppColors.TextPrimary
                    )
                )
            },
            bottomBar = {
                Column(modifier = Modifier.padding(12.dp)) {
                    // Quick suggestion chips (Flutter parity).
                    if (state.messages.size <= 1) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)
                        ) {
                            state.suggestions.take(2).forEach { suggestion ->
                                AssistChip(
                                    onClick = { viewModel.send(suggestion) },
                                    label = { Text(suggestion, fontSize = 11.sp) }
                                )
                            }
                        }
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp)
                        ) {
                            state.suggestions.drop(2).forEach { suggestion ->
                                AssistChip(
                                    onClick = { viewModel.send(suggestion) },
                                    label = { Text(suggestion, fontSize = 11.sp) }
                                )
                            }
                        }
                    }

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(AppColors.SurfaceColor, RoundedCornerShape(24.dp))
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = input,
                            onValueChange = { input = it },
                            modifier = Modifier.weight(1f),
                            placeholder = { Text("اكتب سؤالك...") },
                            maxLines = 3,
                            shape = RoundedCornerShape(20.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                unfocusedBorderColor = Color.Transparent,
                                focusedBorderColor = Color.Transparent
                            )
                        )
                        FloatingActionButton(
                            onClick = {
                                viewModel.send(input)
                                input = ""
                            },
                            containerColor = AppColors.PrimaryColor,
                            contentColor = Color.White,
                            modifier = Modifier.size(44.dp)
                        ) {
                            Text("➤", fontSize = 16.sp)
                        }
                    }
                }
            }
        ) { padding ->
            if (!state.isConfigured && !showSettings) {
                // First-run configuration prompt.
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text("🤖", style = AppTypography.headlineLarge)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        "المساعد الذكي غير مضبوط",
                        style = AppTypography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "أضف مفتاح Gemini API لتفعيل المحادثة الذكية.",
                        style = AppTypography.bodyMedium,
                        color = AppColors.TextSecondary
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Button(
                        onClick = { showSettings = true },
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.PrimaryColor),
                        shape = RoundedCornerShape(10.dp)
                    ) {
                        Text("ضبط المفتاح", color = Color.White)
                    }
                }
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    contentPadding = PaddingValues(vertical = 12.dp)
                ) {
                    items(state.messages, key = { it.id }) { message ->
                        ChatBubble(message)
                    }
                    if (state.isThinking) {
                        item(key = "thinking") {
                            ThinkingBubble()
                        }
                    }
                }
            }
        }
    }

    if (showSettings) {
        AlertDialog(
            onDismissRequest = { showSettings = false },
            title = { Text("إعدادات المساعد الذكي") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "Gemini 2.5 Flash — احصل على مفتاح مجاني من Google AI Studio",
                        style = AppTypography.bodySmall,
                        color = AppColors.TextSecondary
                    )
                    OutlinedTextField(
                        value = state.apiKey,
                        onValueChange = viewModel::updateApiKeyDraft,
                        label = { Text("مفتاح API") },
                        singleLine = true
                    )
                    if (state.isConfigured) {
                        Text("✓ المفتاح مضبوط", style = AppTypography.bodySmall, color = AppColors.SuccessColor)
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.saveApiKey()
                    showSettings = false
                }) { Text("حفظ", color = AppColors.PrimaryColor, fontWeight = FontWeight.Bold) }
            },
            dismissButton = {
                TextButton(onClick = { showSettings = false }) { Text("إغلاق") }
            }
        )
    }
}

@Composable
private fun ChatBubble(message: ChatMessage) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (message.isFromUser) Arrangement.Start else Arrangement.End
    ) {
        Column(
            horizontalAlignment = if (message.isFromUser) Alignment.Start else Alignment.End,
            modifier = Modifier.widthIn(max = 300.dp)
        ) {
            Box(
                modifier = Modifier
                    .background(
                        if (message.isFromUser) AppColors.PrimaryColor else AppColors.SurfaceColor,
                        RoundedCornerShape(
                            topStart = 16.dp,
                            topEnd = 16.dp,
                            bottomStart = if (message.isFromUser) 4.dp else 16.dp,
                            bottomEnd = if (message.isFromUser) 16.dp else 4.dp
                        )
                    )
                    .padding(12.dp)
            ) {
                Text(
                    message.text,
                    style = AppTypography.bodyMedium,
                    color = if (message.isFromUser) Color.White else AppColors.TextPrimary
                )
            }
            Text(
                chatTimeFormat.format(Date(message.timestamp)),
                style = AppTypography.labelSmall,
                color = AppColors.TextSecondary,
                modifier = Modifier.padding(horizontal = 4.dp)
            )
        }
    }
}

@Composable
private fun ThinkingBubble() {
    Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
        Box(
            modifier = Modifier
                .background(AppColors.SurfaceColor, RoundedCornerShape(16.dp))
                .padding(12.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("يفكر", style = AppTypography.bodySmall, color = AppColors.TextSecondary)
                repeat(3) { index ->
                    Box(
                        modifier = Modifier
                            .size(5.dp)
                            .alpha(0.4f + index * 0.25f)
                            .background(AppColors.TextSecondary, CircleShape)
                    )
                }
            }
        }
    }
}
