package com.marina.marina.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.Icon
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarData
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarVisuals
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Marina snackbar system — styled after the Flutter app's colored snackbars
 * (green sync success / red errors / orange warnings) with the soft,
 * floating aesthetic of the serenity & syncforge reference designs:
 * rounded 16dp, elevated, leading status icon, RTL-friendly.
 */

enum class MarinaSnackbarType {
    SUCCESS,
    ERROR,
    WARNING,
    INFO
}

/**
 * Custom [SnackbarVisuals] carrying the Marina type so it can travel through
 * the standard [SnackbarHostState] pipeline.
 */
class MarinaSnackbarVisuals(
    override val message: String,
    val type: MarinaSnackbarType = MarinaSnackbarType.INFO,
    override val actionLabel: String? = null,
    override val withDismissAction: Boolean = false,
    override val duration: SnackbarDuration = SnackbarDuration.Short,
) : SnackbarVisuals

/** Typed palette for each snackbar flavor. */
private data class SnackbarStyle(
    val container: Color,
    val content: Color,
    val icon: ImageVector
)

private fun styleFor(type: MarinaSnackbarType): SnackbarStyle = when (type) {
    MarinaSnackbarType.SUCCESS -> SnackbarStyle(
        container = Color(0xFF2E7D32),
        content = Color.White,
        icon = Icons.Filled.CloudDone
    )
    MarinaSnackbarType.ERROR -> SnackbarStyle(
        container = Color(0xFFC62828),
        content = Color.White,
        icon = Icons.Filled.ErrorOutline
    )
    MarinaSnackbarType.WARNING -> SnackbarStyle(
        container = Color(0xFFEF6C00),
        content = Color.White,
        icon = Icons.Filled.WarningAmber
    )
    MarinaSnackbarType.INFO -> SnackbarStyle(
        container = Color(0xFF1E88E5),
        content = Color.White,
        icon = Icons.Filled.CloudDownload
    )
}

/**
 * Shows a typed Marina snackbar through the standard host state.
 * Safe to call from any coroutine scope (usually rememberedCoroutineScope).
 */
fun CoroutineScope.showMarinaSnackbar(
    hostState: SnackbarHostState,
    message: String,
    type: MarinaSnackbarType = MarinaSnackbarType.INFO,
    duration: SnackbarDuration = SnackbarDuration.Short
) = launch {
    hostState.showSnackbar(
        MarinaSnackbarVisuals(
            message = message,
            type = type,
            duration = duration
        )
    )
}

/**
 * Floating snackbar host — rounded 16dp, color-coded by type with a leading
 * status icon. Falls back to a neutral container for visuals that are not
 * [MarinaSnackbarVisuals].
 */
@Composable
fun MarinaSnackbarHost(
    hostState: SnackbarHostState,
    modifier: Modifier = Modifier
) {
    SnackbarHost(
        hostState = hostState,
        modifier = modifier
    ) { data ->
        MarinaSnackbarRow(data = data)
    }
}

@Composable
private fun MarinaSnackbarRow(data: SnackbarData) {
    val visuals = data.visuals
    val marinaType = (visuals as? MarinaSnackbarVisuals)?.type ?: MarinaSnackbarType.INFO
    val style = styleFor(marinaType)

    Snackbar(
        containerColor = style.container,
        contentColor = style.content,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = style.icon,
                contentDescription = null,
                tint = style.content.copy(alpha = 0.95f),
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = visuals.message,
                fontSize = 13.sp,
                lineHeight = 18.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.weight(1f, fill = false)
            )
        }
    }
}
