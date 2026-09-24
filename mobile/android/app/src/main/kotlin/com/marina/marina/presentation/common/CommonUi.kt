package com.marina.marina.presentation.common

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
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
    val green = Color(0xFF4CAF50)   // Colors.green
    val orange = Color(0xFFFF9800)  // Colors.orange
    val red = Color(0xFFF44336)     // Colors.red
    val red900 = Color(0xFFB71C1C)  // Colors.red.shade900
    val blue = Color(0xFF2196F3)    // Colors.blue
}

/**
 * ظلال لوحة Flutter المستخدمة في شاشات المجموعة — نظائر مباشرة لـ
 * Colors.grey.shade200 وغيرها حتى تبقى الألوان مطابقة للحرف.
 */
object DartPalette {
    val blue = Color(0xFF2196F3)      // Colors.blue
    val grey = Color(0xFF9E9E9E)      // Colors.grey
    val grey200 = Color(0xFFEEEEEE)   // Colors.grey.shade200
    val grey300 = Color(0xFFE0E0E0)   // Colors.grey.shade300
    val grey600 = Color(0xFF757575)   // Colors.grey.shade600
    val red = Color(0xFFF44336)       // Colors.red
    val red50 = Color(0xFFFFEBEE)     // Colors.red.shade50
    val red100 = Color(0xFFFFCDD2)    // Colors.red.shade100
    val red400 = Color(0xFFEF5350)    // Colors.red.shade400
    val orange = Color(0xFFFF9800)    // Colors.orange
    val orange50 = Color(0xFFFFF3E0)  // Colors.orange.shade50
    val orange400 = Color(0xFFFFA726) // Colors.orange.shade400
    val orange800 = Color(0xFFEF6C00) // Colors.orange.shade800
    val green700 = Color(0xFF388E3C)  // Colors.green.shade700
    val blue50 = Color(0xFFE3F2FD)    // Colors.blue.shade50
    val redAccent = Color(0xFFFF5252) // Colors.redAccent
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

    IconButton(
        onClick = {
            if (isSyncing) return@IconButton
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
        enabled = !isSyncing
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
                tint = if (lastError != null) DartPalette.redAccent else LocalContentColor.current
            )
        }
    }
}

/** تنسيق الكميات كما يعرضها Dart (أعداد صحيحة بلا فاصلة عشرية). */
fun formatQuantity(value: Double): String =
    if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
