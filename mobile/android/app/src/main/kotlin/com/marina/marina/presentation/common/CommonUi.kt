package com.marina.marina.presentation.common

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarVisuals
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.components.MarinaToolbarActionButton
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * عناصر UI مشتركة بين شاشات المجموعة الصغيرة (المخزون/المعلومية/الملاحظات/
 * القائمة السوداء) — منفصلة هنا لأن components/ خارج نطاق التعديل.
 */

/** حدث سناك-بار يحمل لون الخلفية الصريح متى حدّده Dart صراحةً. */
data class AppSnackbar(val text: String, val containerColor: Color? = null)

/** [SnackbarVisuals] يحمل لون الحاوية عبر خط الأنابيب القياسي. */
class ColoredSnackbarVisuals(
    override val message: String,
    val containerColor: Color? = null,
    override val actionLabel: String? = null,
    override val withDismissAction: Boolean = false,
    override val duration: SnackbarDuration = SnackbarDuration.Short
) : SnackbarVisuals

/** سناك-بار: يلوّن الحاوية متى تحدد اللون، وإلا يستخدم نمط M3 الافتراضي. */
@Composable
fun AppSnackbarHost(
    hostState: SnackbarHostState,
    modifier: Modifier = Modifier
) {
    SnackbarHost(hostState = hostState, modifier = modifier) { data ->
        val color = (data.visuals as? ColoredSnackbarVisuals)?.containerColor
        if (color == null) {
            Snackbar(snackbarData = data)
        } else {
            Snackbar(
                snackbarData = data,
                containerColor = color,
                contentColor = Color.White
            )
        }
    }
}

suspend fun SnackbarHostState.showAppSnackbar(event: AppSnackbar) {
    showSnackbar(ColoredSnackbarVisuals(event.text, event.containerColor))
}

/**
 * لوحة ألوان Dart المستخدمة حرفياً في سناك-بارات شاشات المجموعة
 * (Colors.green/orange/red/red.shade900/blue من Flutter).
 */
object SnackColors {
    val green = AppColors.SuccessActionColor   // Colors.green
    val orange = AppColors.WarningActionColor  // Colors.orange
    val red = AppColors.DangerActionColor     // Colors.red
    val red900 = AppColors.DangerActionColor  // Colors.red.shade900
    val blue = AppColors.PrimaryActionColor    // Colors.blue
}

/** Semantic status colors aligned with the active light/dark Material scheme. */
object DartPalette {
    val blue: Color
        @Composable get() = MaterialTheme.colorScheme.primary
    val grey: Color
        @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
    val grey200: Color
        @Composable get() = MaterialTheme.colorScheme.surfaceVariant
    val grey300: Color
        @Composable get() = MaterialTheme.colorScheme.outlineVariant
    val grey600: Color
        @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
    val red: Color
        @Composable get() = MaterialTheme.colorScheme.error
    val red50: Color
        @Composable get() = MaterialTheme.colorScheme.errorContainer
    val red100: Color
        @Composable get() = MaterialTheme.colorScheme.errorContainer
    val red400: Color
        @Composable get() = MaterialTheme.colorScheme.error
    val orange: Color
        @Composable get() = MaterialTheme.colorScheme.secondary
    val orange50: Color
        @Composable get() = MaterialTheme.colorScheme.secondaryContainer
    val orange400: Color
        @Composable get() = MaterialTheme.colorScheme.secondary
    val orange800: Color
        @Composable get() = MaterialTheme.colorScheme.secondary
    val green700: Color
        @Composable get() = MaterialTheme.colorScheme.tertiary
    val blue50: Color
        @Composable get() = MaterialTheme.colorScheme.primaryContainer
    val redAccent: Color
        @Composable get() = MaterialTheme.colorScheme.error
}

/**
 * نظير `SyncActionButton` في Dart AppScaffold (app_scaffold.dart) — زر
 * المزامنة الذي يظهر في شريط عنوان كل شاشات AdminLayout: دوران أثناء
 * المزامنة، أحمر عند آخر خطأ، ورسائل المزامنة نفسها.
 */
@HiltViewModel
class AppBarSyncViewModel @Inject constructor(
    val syncRepository: SyncRepository
) : ViewModel()

@Composable
fun AppBarSyncIconButton(
    syncViewModel: AppBarSyncViewModel,
    snackbarHostState: SnackbarHostState
) {
    var isSyncing by remember { mutableStateOf(false) }
    var lastError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    MarinaToolbarActionButton(
        onClick = {
            if (isSyncing) return@MarinaToolbarActionButton
            scope.launch {
                isSyncing = true
                lastError = null
                try {
                    val result = syncViewModel.syncRepository.syncNow()
                    if (result.isError) {
                        lastError = result.lastMessage
                        snackbarHostState.showAppSnackbar(
                            AppSnackbar("فشل في المزامنة: ${result.lastMessage ?: "سبب غير معروف"}")
                        )
                    } else {
                        snackbarHostState.showAppSnackbar(
                            AppSnackbar(
                                if (result.pushedCount == 0 && result.pulledCount == 0) {
                                    "لا توجد تغييرات جديدة"
                                } else {
                                    "تمت المزامنة: رفع ${result.pushedCount} / سحب ${result.pulledCount}"
                                }
                            )
                        )
                    }
                } catch (e: Exception) {
                    lastError = e.toString()
                    snackbarHostState.showAppSnackbar(AppSnackbar("فشل في المزامنة: $e"))
                }
                isSyncing = false
            }
        },
        enabled = !isSyncing,
        containerColor = if (lastError != null) AppColors.DangerActionColor else AppColors.PrimaryActionColor,
        contentColor = Color.White
    ) {
        if (isSyncing) {
            Box(modifier = Modifier.size(20.dp)) {
                CircularProgressIndicator(
                    modifier = Modifier.fillMaxSize(),
                    strokeWidth = 2.dp
                )
            }
        } else {
            Icon(
                imageVector = Icons.Filled.Sync,
                contentDescription = when {
                    lastError != null -> "حدث خطأ في آخر مزامنة، اضغط لإعادة المحاولة"
                    else -> "مزامنة مع Cloudflare"
                },
                tint = Color.White
            )
        }
    }
}

/** تنسيق الكميات كما يعرضها Dart (أعداد صحيحة بلا فاصلة عشرية). */
fun formatQuantity(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
