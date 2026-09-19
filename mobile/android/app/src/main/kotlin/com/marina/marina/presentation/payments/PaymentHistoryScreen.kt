package com.marina.marina.presentation.payments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentHistoryScreen(
    viewModel: PaymentHistoryViewModel = hiltViewModel(),
    bookingId: Long? = null,
    onBack: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    if (bookingId != null && state.bookingFilter != bookingId) viewModel.filterBooking(bookingId)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("سجل المدفوعات") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "رجوع") } }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = state.showVoidedOnly,
                    onClick = viewModel::toggleVoidedOnly,
                    label = { Text("الملغاة فقط") }
                )
                Text("الإجمالي: ${state.visible.sumOf { it.amount }}", modifier = Modifier.padding(12.dp))
            }
            if (state.isLoading) {
                CircularProgressIndicator(modifier = Modifier.padding(32.dp))
            } else if (state.visible.isEmpty()) {
                Text("لا توجد مدفوعات", modifier = Modifier.padding(24.dp))
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 8.dp)) {
                    items(state.visible, key = { it.id }) { payment ->
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text("${payment.amount}")
                                    Text(payment.paymentMethod, color = Color.Gray)
                                }
                                Text("غرفة: ${payment.roomNumber ?: "-"} • ${payment.paymentDate}")
                                payment.notes?.let { Text(it, color = Color.Gray) }
                                if (payment.isVoided) Text("ملغاة: ${payment.voidReason.orEmpty()}", color = Color.Red)
                            }
                        }
                    }
                }
            }
        }
    }
}
