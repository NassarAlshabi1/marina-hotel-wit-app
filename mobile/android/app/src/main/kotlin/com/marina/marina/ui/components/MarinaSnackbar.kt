package com.marina.marina.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalAccessibilityManager
import androidx.compose.ui.unit.dp
import com.marina.marina.ui.theme.AppTypography
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class MarinaSnackbarType { SUCCESS, ERROR, WARNING, INFO }

/** Helper messages are plain text; callers opt into an icon (e.g. auto-pull). */
class MarinaSnackbarVisuals(
    override val message: String,
    val type: MarinaSnackbarType? = MarinaSnackbarType.INFO,
    override val actionLabel: String? = null,
    override val withDismissAction: Boolean = false,
    val requestedDuration: SnackbarDuration = SnackbarDuration.Short,
    val icon: ImageVector? = null,
    val floating: Boolean = true,
    val timeoutOverrideMillis: Long? = null,
) : SnackbarVisuals {
    init { require(timeoutOverrideMillis == null || timeoutOverrideMillis > 0L) }

    // The host owns the reference 3s/4s timer, extended for accessibility.
    override val duration: SnackbarDuration = SnackbarDuration.Indefinite
    val timeoutMillis: Long
        get() = when {
            requestedDuration == SnackbarDuration.Indefinite || actionLabel != null -> Long.MAX_VALUE
            timeoutOverrideMillis != null -> timeoutOverrideMillis
            type == MarinaSnackbarType.ERROR || requestedDuration == SnackbarDuration.Long -> 4_000L
            else -> 3_000L
        }
}

/** Darker shades preserve white-label contrast instead of Flutter's weak green/orange. */
internal fun snackbarContainer(type: MarinaSnackbarType): Color = when (type) {
    MarinaSnackbarType.SUCCESS -> Color(0xFF2E7D32)
    MarinaSnackbarType.ERROR -> Color(0xFFC62828)
    MarinaSnackbarType.WARNING -> Color(0xFFAD4B00)
    MarinaSnackbarType.INFO -> Color(0xFF1565C0)
}

fun CoroutineScope.showMarinaSnackbar(
    hostState: SnackbarHostState,
    message: String,
    type: MarinaSnackbarType = MarinaSnackbarType.INFO,
    duration: SnackbarDuration = SnackbarDuration.Short
) = launch {
    hostState.currentSnackbarData?.dismiss()
    hostState.showSnackbar(MarinaSnackbarVisuals(message, type, requestedDuration = duration))
}

@Composable
fun MarinaSnackbarHost(hostState: SnackbarHostState, modifier: Modifier = Modifier) {
    val current = hostState.currentSnackbarData
    val accessibility = LocalAccessibilityManager.current
    LaunchedEffect(current, accessibility) {
        val visuals = current?.visuals as? MarinaSnackbarVisuals ?: return@LaunchedEffect
        if (visuals.timeoutMillis != Long.MAX_VALUE) {
            val timeout = accessibility?.calculateRecommendedTimeoutMillis(
                originalTimeoutMillis = visuals.timeoutMillis,
                containsIcons = visuals.icon != null,
                containsText = true,
                containsControls = visuals.withDismissAction || visuals.actionLabel != null
            ) ?: visuals.timeoutMillis
            delay(timeout)
            current?.dismiss()
        }
    }
    SnackbarHost(hostState, modifier) { data ->
        val visuals = data.visuals
        val typed = visuals as? MarinaSnackbarVisuals
        val container = typed?.type?.let(::snackbarContainer)
            ?: MaterialTheme.colorScheme.inverseSurface
        val foreground = if (typed?.type != null) Color.White else MaterialTheme.colorScheme.inverseOnSurface
        ProvideTextStyle(AppTypography.bodyMedium) {
            Snackbar(
                modifier = Modifier.padding(if (typed?.floating == false) 0.dp else 16.dp),
                shape = RoundedCornerShape(when {
                    typed?.floating == false -> 0.dp
                    typed?.icon != null -> 10.dp
                    else -> 8.dp
                }),
                containerColor = container,
                contentColor = foreground,
                actionOnNewLine = visuals.actionLabel != null,
                action = visuals.actionLabel?.let { label ->
                    { TextButton(onClick = data::performAction) { Text(label, color = foreground) } }
                },
                dismissAction = if (visuals.withDismissAction) {
                    { IconButton(onClick = data::dismiss) {
                        Icon(Icons.Default.Close, contentDescription = "إغلاق الرسالة", tint = foreground)
                    } }
                } else null
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    typed?.icon?.let {
                        Icon(it, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(12.dp))
                    }
                    Text(visuals.message, style = AppTypography.bodyMedium, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}
