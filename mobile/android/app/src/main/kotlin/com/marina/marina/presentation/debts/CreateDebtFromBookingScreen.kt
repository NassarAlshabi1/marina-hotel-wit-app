package com.marina.marina.presentation.debts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateDebtFromBookingScreen(
    viewModel: CreateDebtFromBookingViewModel = hiltViewModel(),
    bookingId: Long,
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    var amount by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }
    var paymentDate by remember { mutableStateOf("") }

    LaunchedEffect(bookingId) { viewModel.load(bookingId) }
    LaunchedEffect(state.saved) { if (state.saved) onSaved() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("إنشاء دين من حجز") },
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
                Text("${state.booking!!.guestName} • غرفة ${state.booking!!.roomNumber}")
                Text("المتبقي على الحجز: ${state.booking!!.remainingBalanceCached}", color = Color.Gray)
                OutlinedTextField(
                    value = amount, onValueChange = { amount = it },
                    label = { Text("المبلغ *") }, modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
                OutlinedTextField(
                    value = reason, onValueChange = { reason = it },
                    label = { Text("سبب الدين *") }, modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = paymentDate, onValueChange = { paymentDate = it },
                    label = { Text("تاريخ الاستحقاق") }, modifier = Modifier.fillMaxWidth()
                )
                state.error?.let { Text(it, color = Color.Red) }
                Button(
                    onClick = { viewModel.saveDebt(amount.toDoubleOrNull() ?: 0.0, reason.trim(), paymentDate.trim()) },
                    enabled = (amount.toDoubleOrNull() ?: 0.0) > 0 && reason.isNotBlank(),
                    modifier = Modifier.fillMaxWidth()
                ) { Text("حفظ الدين") }
            }
        }
    }
}
