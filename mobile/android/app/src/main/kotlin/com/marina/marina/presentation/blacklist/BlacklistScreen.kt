package com.marina.marina.presentation.blacklist

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.components.SidebarMenuButton
import com.marina.marina.domain.model.BlacklistEntry

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BlacklistScreen(
    viewModel: BlacklistViewModel = hiltViewModel(),
    onBack: () -> Unit = {}
) {
    val state by viewModel.state.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    var showEditor by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<BlacklistEntry?>(null) }

    LaunchedEffect(state.message, state.error) {
        (state.message ?: state.error)?.let { snackbar.showSnackbar(it) }
        viewModel.consumeMessage()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("القائمة السوداء") },
                navigationIcon = { SidebarMenuButton() }
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        floatingActionButton = {
            FloatingActionButton(onClick = { editing = null; showEditor = true }) {
                Icon(Icons.Default.Add, contentDescription = "إضافة")
            }
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            OutlinedTextField(
                value = state.query,
                onValueChange = viewModel::setQuery,
                label = { Text("بحث بالاسم أو الهوية أو الهاتف") },
                modifier = Modifier.fillMaxWidth()
            )
            if (state.isLoading) {
                CircularProgressIndicator(modifier = Modifier.padding(32.dp))
            } else if (state.entries.isEmpty()) {
                Text("لا توجد أسماء في القائمة السوداء", modifier = Modifier.padding(24.dp))
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 12.dp)) {
                    items(state.entries, key = { it.id }) { entry ->
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = if (entry.active) Color(0xFFFDECEA) else Color(0xFFF1F1F1)
                            ),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(modifier = Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(entry.name)
                                    Text(
                                        listOfNotNull(entry.nationalId, entry.phone).joinToString(" • "),
                                        color = Color.Gray
                                    )
                                    entry.reason?.let { Text(it, color = Color(0xFFB71C1C)) }
                                }
                                Row {
                                    IconButton(onClick = { viewModel.toggleActive(entry) }) {
                                        Icon(
                                            if (entry.active) Icons.Default.Block else Icons.Default.CheckCircle,
                                            contentDescription = "تفعيل/تعطيل"
                                        )
                                    }
                                    IconButton(onClick = { editing = entry; showEditor = true }) {
                                        Text("تعديل")
                                    }
                                    IconButton(onClick = { viewModel.delete(entry) }) {
                                        Icon(Icons.Default.Delete, contentDescription = "حذف")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showEditor) {
        BlacklistEditorDialog(
            initial = editing,
            onDismiss = { showEditor = false },
            onSave = { viewModel.save(it); showEditor = false }
        )
    }
}

@Composable
private fun BlacklistEditorDialog(
    initial: BlacklistEntry?,
    onDismiss: () -> Unit,
    onSave: (BlacklistEntry) -> Unit
) {
    var name by remember { mutableStateOf(initial?.name.orEmpty()) }
    var nationalId by remember { mutableStateOf(initial?.nationalId.orEmpty()) }
    var phone by remember { mutableStateOf(initial?.phone.orEmpty()) }
    var reason by remember { mutableStateOf(initial?.reason.orEmpty()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (initial == null) "إضافة للقائمة السوداء" else "تعديل") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("الاسم *") })
                OutlinedTextField(value = nationalId, onValueChange = { nationalId = it }, label = { Text("رقم الهوية") })
                OutlinedTextField(value = phone, onValueChange = { phone = it }, label = { Text("الهاتف") })
                OutlinedTextField(value = reason, onValueChange = { reason = it }, label = { Text("السبب") })
            }
        },
        confirmButton = {
            TextButton(
                enabled = name.isNotBlank(),
                onClick = {
                    onSave(
                        (initial ?: BlacklistEntry()).copy(
                            name = name.trim(),
                            nationalId = nationalId.trim().ifBlank { null },
                            phone = phone.trim().ifBlank { null },
                            reason = reason.trim().ifBlank { null }
                        )
                    )
                }
            ) { Text("حفظ") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("إلغاء") } }
    )
}
