package com.marina.marina.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.marina.marina.domain.model.SyncUiState
import kotlinx.coroutines.flow.StateFlow

/** Real engine state, not a timed toast or an invented completion percentage. */
@Composable
fun SyncProgressBanner(state: StateFlow<SyncUiState>) {
    val sync by state.collectAsStateWithLifecycle()
    if (!sync.isSyncing && !sync.isError) return
    val scheme = MaterialTheme.colorScheme
    Surface(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        shape = MaterialTheme.shapes.small,
        color = if (sync.isError) scheme.errorContainer else scheme.primaryContainer,
        contentColor = if (sync.isError) scheme.onErrorContainer else scheme.onPrimaryContainer
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(sync.lastMessage.ifBlank { "المزامنة جارية…" }, style = MaterialTheme.typography.bodyMedium)
            if (sync.isSyncing) LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
    }
}
