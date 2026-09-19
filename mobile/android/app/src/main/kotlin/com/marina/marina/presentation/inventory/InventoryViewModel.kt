package com.marina.marina.presentation.inventory

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.repository.InventoryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class InventoryUiState(
    val isLoading: Boolean = false,
    val items: List<InventoryItem> = emptyList(),
    val searchQuery: String = "",
    val error: String? = null,
    val message: String? = null
) {
    val filtered: List<InventoryItem>
        get() {
            val q = searchQuery.trim()
            if (q.isBlank()) return items
            return items.filter {
                it.name.contains(q, ignoreCase = true) ||
                    (it.category ?: "").contains(q, ignoreCase = true)
            }
        }

    val itemCount: Int get() = items.size
    val lowStockCount: Int get() = items.count { it.isLowStock }
}

@HiltViewModel
class InventoryViewModel @Inject constructor(
    private val inventoryRepository: InventoryRepository
) : ViewModel() {

    private val _state = MutableStateFlow(InventoryUiState(isLoading = true))
    val state: StateFlow<InventoryUiState> = _state.asStateFlow()

    init {
        inventoryRepository.getAllItems().onEach { items ->
            _state.value = _state.value.copy(isLoading = false, items = items, error = null)
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    fun addItem(item: InventoryItem) {
        viewModelScope.launch {
            try {
                inventoryRepository.addItem(item)
                _state.value = _state.value.copy(message = "تمت إضافة العنصر")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun updateItem(item: InventoryItem) {
        viewModelScope.launch {
            try {
                inventoryRepository.updateItem(item)
                _state.value = _state.value.copy(message = "تم تحديث العنصر")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    /** Records a movement: in / out / adjustment (stocktaking). */
    fun recordMovement(item: InventoryItem, type: String, quantity: Double, note: String?) {
        viewModelScope.launch {
            val result = inventoryRepository.recordMovement(item.id, type, quantity, note)
            result.fold(
                onSuccess = {
                    _state.value = _state.value.copy(
                        message = when (type) {
                            "in" -> "تم تسجيل الوارد"
                            "out" -> "تم تسجيل الصرف"
                            else -> "تم تسجيل الجرد"
                        }
                    )
                },
                onFailure = { e ->
                    _state.value = _state.value.copy(message = e.message ?: "فشلت العملية")
                }
            )
        }
    }

    fun deleteItem(item: InventoryItem) {
        viewModelScope.launch {
            try {
                inventoryRepository.softDeleteItem(item.id)
                _state.value = _state.value.copy(message = "تم حذف العنصر")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
