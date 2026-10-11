package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.local.entity.CustomListItemEntity
import com.marina.marina.domain.repository.CustomListsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel for SettingsCustomListsScreen — mirrors Flutter `settings_custom_lists.dart`.
 * Manages three tabs: expense_type, id_type, payment_method.
 */
@HiltViewModel
class CustomListsViewModel @Inject constructor(
    private val customListsRepository: CustomListsRepository
) : ViewModel() {

    data class UiState(
        val expenseTypes: List<CustomListItemEntity> = emptyList(),
        val idTypes: List<CustomListItemEntity> = emptyList(),
        val paymentMethods: List<CustomListItemEntity> = emptyList(),
        val isLoading: Boolean = false,
        val error: String? = null,
        val message: String? = null
    )

    private val _state = MutableStateFlow(UiState(isLoading = true))
    val state: StateFlow<UiState> = _state.asStateFlow()

    init {
        loadAll()
    }

    fun loadAll() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true)
            try {
                val expenseTypes = customListsRepository.getAllByListKey("expense_type")
                val idTypes = customListsRepository.getAllByListKey("id_type")
                val paymentMethods = customListsRepository.getAllByListKey("payment_method")
                _state.value = _state.value.copy(
                    expenseTypes = expenseTypes,
                    idTypes = idTypes,
                    paymentMethods = paymentMethods,
                    isLoading = false,
                    error = null
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "فشل تحميل القوائم: ${e.message}"
                )
            }
        }
    }

    fun addItem(listKey: String, name: String, sortOrder: Int = 0, isSystem: Boolean = false) {
        viewModelScope.launch {
            try {
                val entity = CustomListItemEntity(
                    listKey = listKey,
                    name = name.trim(),
                    sortOrder = sortOrder,
                    isActive = true,
                    isSystem = isSystem
                )
                customListsRepository.insert(entity)
                _state.value = _state.value.copy(message = "تم إضافة '$name' بنجاح")
                loadAll()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل الإضافة: ${e.message}")
            }
        }
    }

    fun updateItem(entity: CustomListItemEntity) {
        viewModelScope.launch {
            try {
                customListsRepository.update(entity)
                _state.value = _state.value.copy(message = "تم تحديث '${entity.name}' بنجاح")
                loadAll()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل التحديث: ${e.message}")
            }
        }
    }

    fun deleteItem(id: Long) {
        viewModelScope.launch {
            try {
                customListsRepository.deleteById(id)
                _state.value = _state.value.copy(message = "تم الحذف بنجاح")
                loadAll()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل الحذف: ${e.message}")
            }
        }
    }

    fun toggleActive(entity: CustomListItemEntity) {
        viewModelScope.launch {
            try {
                val updated = entity.copy(isActive = !entity.isActive)
                customListsRepository.update(updated)
                _state.value = _state.value.copy(message = "تم ${if (updated.isActive) "تفعيل" else "تعطيل"} '${entity.name}'")
                loadAll()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل التغيير: ${e.message}")
            }
        }
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }
}