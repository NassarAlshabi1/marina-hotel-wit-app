package com.marina.marina.presentation.inventory

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.repository.InventoryRepository
import com.marina.marina.domain.session.UserSessionManager
import com.marina.marina.presentation.common.AppSnackbar
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * حالة شاشة المخزون — نظير inventoryItemsProvider + authProvider.canPerform
 * في inventory_screen.dart.
 */
data class InventoryUiState(
    val isLoading: Boolean = true,
    val items: List<InventoryItem> = emptyList(),
    val loadError: String? = null,
    val canCreate: Boolean = false,
    val canUpdate: Boolean = false,
    val snackbar: AppSnackbar? = null
)

@HiltViewModel
class InventoryViewModel @Inject constructor(
    private val inventoryRepository: InventoryRepository,
    private val userSessionManager: UserSessionManager
) : ViewModel() {

    private val _state = MutableStateFlow(InventoryUiState())
    val state: StateFlow<InventoryUiState> = _state.asStateFlow()

    private var observeJob: Job? = null

    init {
        observe()
        viewModelScope.launch {
            userSessionManager.currentUser.collect { user ->
                _state.value = _state.value.copy(
                    canCreate = user?.canPerform("inventory", "create") ?: false,
                    canUpdate = user?.canPerform("inventory", "update") ?: false
                )
            }
        }
    }

    private fun observe() {
        observeJob?.cancel()
        observeJob = inventoryRepository.getAllItems()
            .onEach { items ->
                _state.value = _state.value.copy(isLoading = false, items = items, loadError = null)
            }
            .catch { e ->
                _state.value = _state.value.copy(isLoading = false, loadError = e.toString())
            }
            .launchIn(viewModelScope)
    }

    /** نظير ref.invalidate(inventoryItemsProvider) — إعادة تحميل القائمة. */
    fun retry() {
        _state.value = _state.value.copy(isLoading = true, loadError = null)
        observe()
    }

    fun consumeSnackbar() {
        _state.value = _state.value.copy(snackbar = null)
    }

    /** نظير _showAddItemDialog: الإنشاء محصور بصلاحية inventory.create. */
    fun addItem(name: String, unit: String, category: String, initialQuantity: Int, minimumQuantity: Int) {
        viewModelScope.launch {
            try {
                inventoryRepository.addItem(
                    InventoryItem(
                        name = name,
                        unit = unit,
                        category = category,
                        currentQuantity = initialQuantity.toDouble(),
                        minimumQuantity = minimumQuantity.toDouble()
                    )
                )
                _state.value = _state.value.copy(snackbar = AppSnackbar("تمت إضافة الصنف"))
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    snackbar = AppSnackbar("تعذر إضافة الصنف: ${friendlyErrorMessage(e)}")
                )
            }
        }
    }

    /** نظير recordMovement: حركة وارد/صرف على الرصيد. */
    fun recordMovement(item: InventoryItem, movementType: String, quantity: Int, note: String?) {
        viewModelScope.launch {
            inventoryRepository.recordMovement(item.id, movementType, quantity.toDouble(), note)
                .fold(
                    onSuccess = {
                        _state.value = _state.value.copy(
                            snackbar = AppSnackbar(
                                if (movementType == "in") "تم تسجيل الوارد" else "تم تسجيل الصرف"
                            )
                        )
                    },
                    onFailure = { e ->
                        _state.value = _state.value.copy(
                            snackbar = AppSnackbar("تعذر تسجيل الحركة: ${e.message}")
                        )
                    }
                )
        }
    }

    /** نظير setStock: اعتماد جرد برصيد فعلي مطلق. */
    fun setStock(item: InventoryItem, actualQuantity: Int, note: String?) {
        viewModelScope.launch {
            inventoryRepository.recordMovement(item.id, "adjustment", actualQuantity.toDouble(), note)
                .fold(
                    onSuccess = {
                        _state.value = _state.value.copy(snackbar = AppSnackbar("تم اعتماد الجرد"))
                    },
                    onFailure = { e ->
                        _state.value = _state.value.copy(
                            snackbar = AppSnackbar("تعذر اعتماد الجرد: ${e.message}")
                        )
                    }
                )
        }
    }

    companion object {
        /**
         * نظير _friendlyErrorMessage (inventory_screen.dart l.13-25): رسالة
         * ودّية بدل الاستثناء الخام، مع كشف تلف قاعدة البيانات.
         */
        fun friendlyErrorMessage(error: Throwable): String {
            val text = error.toString()
            val isDbCorruption = text.contains("malformed") ||
                text.contains("database disk image") ||
                (text.contains("SqliteException") && text.contains("code 11"))
            return if (isDbCorruption) {
                "قاعدة البيانات المحلية بحاجة إلى إصلاح. أعد تشغيل التطبيق " +
                    "ليتم فحصها وإصلاحها تلقائياً وإعادة مزامنة البيانات من السحابة. " +
                    "إذا استمرت المشكلة تواصل مع الدعم الفني."
            } else {
                "حدث خطأ غير متوقع. حاول مرة أخرى، وإذا تكرر أعد تشغيل التطبيق."
            }
        }

        /** كشف تلف SQLite لنفس أنماط _buildErrorWidget (l.80-83). */
        fun isCorruptionError(text: String): Boolean =
            text.contains("malformed") ||
                text.contains("code 11") ||
                text.contains("SqliteException(11)") ||
                text.contains("database disk image")
    }
}
