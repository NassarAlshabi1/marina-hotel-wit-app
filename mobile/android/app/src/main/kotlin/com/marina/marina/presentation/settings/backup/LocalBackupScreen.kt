package com.marina.marina.presentation.settings.backup

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.hilt.navigation.compose.hiltViewModel
import com.marina.marina.components.MarinaBackButton
import com.marina.marina.components.MarinaTopAppBar
import com.marina.marina.presentation.common.AppSnackbar
import com.marina.marina.presentation.common.showAppSnackbar

/** Local-only entry point: does not instantiate the Cloudflare view model. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun LocalBackupScreen(
    onBack: () -> Unit,
    viewModel: BackupViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    val busy = state.isWorking || state.isExportingExcel
    val snackbar = remember { SnackbarHostState() }
    // These operations belong to this navigation entry, not a background worker.
    BackHandler(enabled = busy) { }
    LaunchedEffect(viewModel) {
        viewModel.snackbars.collect { event ->
            snackbar.showAppSnackbar(
                AppSnackbar(event.text, event.containerColorArgb?.let { Color(it) })
            )
        }
    }
    Scaffold(
        topBar = {
            MarinaTopAppBar(
                title = { Text("النسخ الاحتياطي المحلي والاستعادة") },
                navigationIcon = { MarinaBackButton(onClick = onBack, enabled = !busy) }
            )
        },
        snackbarHost = { SnackbarHost(snackbar) }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            LocalBackupsTab(viewModel)
        }
    }
}
