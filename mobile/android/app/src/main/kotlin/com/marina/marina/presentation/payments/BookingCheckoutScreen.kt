package com.marina.marina.presentation.payments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookingCheckoutScreen(
    viewModel: BookingCheckoutViewModel = hiltViewModel(),
    bookingId: Long,
    onBack: () -> Unit = {},
    onCheckedOut: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(bookingId) { viewModel.load(bookingId) }
    LaunchedEffect(state.checkedOut) { if (state.checkedOut) onCheckedOut() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("تسجيل المغادرة") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "رجوع") } }
            )
        }
    ) { padding ->
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.padding(32.dp))
        } else if (state.booking == null) {
            Text("الحجز غير موجود", modifier = Modifier.padding(24.dp))
        } else {
            Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("${state.booking!!.guestName} • غرفة ${state.booking!!.roomNumber}")
                        Text("الليالي (${state.nights.size}): ${state.nightsTotal}")
                        Text("التعديلات: ${state.adjustmentsTotal}")
                        Text("الإجمالي المستحق: ${state.grandTotal}")
                        Text("المدفوع: ${state.paidTotal}")
                        Text("المتبقي: ${state.remaining}")
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { viewModel.checkout(null) },
                        enabled = state.remaining <= 0.0
                    ) { Text("تأكيد المغادرة") }
                    if (state.remaining > 0.0) Text("لا يمكن المغادرة قبل سداد المتبقي", modifier = Modifier.padding(12.dp))
                }
                state.error?.let { Text(it) }
            }
        }
    }
}
