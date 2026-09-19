package com.marina.marina.presentation.employees

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
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SalaryEntitlementsScreen(
    viewModel: SalaryEntitlementsViewModel = hiltViewModel(),
    onBack: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(state.message, state.error) {
        (state.message ?: state.error)?.let { snackbar.showSnackbar(it) }
        viewModel.consumeMessage()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("استحقاقات الرواتب") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "رجوع") } }
            )
        },
        snackbarHost = { SnackbarHost(snackbar) }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            OutlinedTextField(
                value = state.cycleKey,
                onValueChange = viewModel::setCycleKey,
                label = { Text("مفتاح الدورة (فارغ = الأحدث)") },
                modifier = Modifier.fillMaxWidth()
            )
            if (state.isLoading) {
                CircularProgressIndicator(modifier = Modifier.padding(32.dp))
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 12.dp)) {
                    items(state.rows, key = { it.employee.id }) { row ->
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text("${row.employee.name} • ${row.employee.position}")
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text("المستحق: ${row.entitled}")
                                    Text("المدفوع: ${row.paid}")
                                    Text("المتبقي: ${row.remaining}", color = if (row.remaining > 0) Color.Red else Color(0xFF2E7D32))
                                }
                                if (row.cycle == null) {
                                    Button(onClick = { viewModel.openCycle(row.employee, state.cycleKey.ifBlank { "cycle" }) }) {
                                        Text("فتح دورة")
                                    }
                                } else {
                                    Text("الدورة: ${row.cycle!!.cycleKey} • ${row.cycle!!.status}", color = Color.Gray)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
