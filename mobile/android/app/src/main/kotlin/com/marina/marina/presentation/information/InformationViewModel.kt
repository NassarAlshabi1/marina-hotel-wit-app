package com.marina.marina.presentation.information

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.GuestInfo
import com.marina.marina.domain.repository.GuestInfosRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.presentation.common.AppSnackbar
import com.marina.marina.presentation.common.SnackColors
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
 * حالة شاشة سجل المعلومية — نظير guestInfoListProvider في
 * information_screen.dart + مزامنة الخروج (SyncOnExitMixin).
 */
data class InformationUiState(
    val isLoading: Boolean = true,
    val entries: List<GuestInfo> = emptyList(),
    val loadError: String? = null,
    val hasUnsyncedChanges: Boolean = false,
    val snackbar: AppSnackbar? = null
)

@HiltViewModel
class InformationViewModel @Inject constructor(
    private val guestInfosRepository: GuestInfosRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val _state = MutableStateFlow(InformationUiState())
    val state: StateFlow<InformationUiState> = _state.asStateFlow()

    private var observeJob: Job? = null

    init {
        observe()
    }

    private fun observe() {
        observeJob?.cancel()
        observeJob = guestInfosRepository.getAll()
            .onEach { entries ->
                _state.value = _state.value.copy(isLoading = false, entries = entries, loadError = null)
            }
            .catch { e ->
                _state.value = _state.value.copy(isLoading = false, loadError = e.toString())
            }
            .launchIn(viewModelScope)
    }

    fun retry() {
        _state.value = _state.value.copy(isLoading = true, loadError = null)
        observe()
    }

    fun consumeSnackbar() {
        _state.value = _state.value.copy(snackbar = null)
    }

    /** نظير repo.create(...) — الحقول النصية كما أدخلها المستخدم حرفياً. */
    fun create(
        roomNumber: String,
        guestName: String,
        nationality: String,
        idNumber: String,
        idType: String,
        issueDate: String,
        issuePlace: String,
        governorate: String,
        notes: String
    ) {
        viewModelScope.launch {
            try {
                guestInfosRepository.insert(
                    GuestInfo(
                        roomNumber = roomNumber,
                        guestName = guestName,
                        nationality = nationality,
                        idNumber = idNumber,
                        idType = idType,
                        issueDate = issueDate.ifEmpty { null },
                        issuePlace = issuePlace,
                        governorate = governorate,
                        notes = notes
                    )
                )
                _state.value = _state.value.copy(
                    hasUnsyncedChanges = true,
                    snackbar = AppSnackbar("تم حفظ السجل بنجاح")
                )
                pushToCloud()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    snackbar = AppSnackbar("فشل حفظ السجل: ${e.message}", SnackColors.red900)
                )
            }
        }
    }

    /** نظير repo.update(existing.id, ...) — يحفظ الحقول على السجل الحي. */
    fun update(
        existing: GuestInfo,
        roomNumber: String,
        guestName: String,
        nationality: String,
        idNumber: String,
        idType: String,
        issueDate: String,
        issuePlace: String,
        governorate: String,
        notes: String
    ) {
        viewModelScope.launch {
            try {
                val current = guestInfosRepository.getById(existing.id) ?: existing
                guestInfosRepository.update(
                    current.copy(
                        roomNumber = roomNumber,
                        guestName = guestName,
                        nationality = nationality,
                        idNumber = idNumber,
                        idType = idType,
                        issueDate = issueDate,
                        issuePlace = issuePlace,
                        governorate = governorate,
                        notes = notes
                    )
                )
                _state.value = _state.value.copy(
                    hasUnsyncedChanges = true,
                    snackbar = AppSnackbar("تم تحديث السجل بنجاح")
                )
                pushToCloud()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    snackbar = AppSnackbar("فشل حفظ السجل: ${e.message}", SnackColors.red900)
                )
            }
        }
    }

    /** نظير _confirmDelete: حذف السجل مع مزامنة فورية. */
    fun delete(info: GuestInfo) {
        viewModelScope.launch {
            try {
                guestInfosRepository.softDelete(info.id)
                _state.value = _state.value.copy(
                    hasUnsyncedChanges = true,
                    snackbar = AppSnackbar("تم حذف السجل")
                )
                pushToCloud()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    snackbar = AppSnackbar("فشل حذف السجل: ${e.message}", SnackColors.red900)
                )
            }
        }
    }

    /**
     * نظير _pushToAppwrite (information_screen.dart l.806-813): مزامنة فورية
     * بعد كل عملية CRUD — رفع فقط بدون سحب، والفشل صامت (سجل فقط).
     */
    private fun pushToCloud() {
        viewModelScope.launch {
            try {
                syncRepository.pushOnly()
                _state.value = _state.value.copy(hasUnsyncedChanges = false)
            } catch (_: Exception) {
                // نظير dlog: فشلت المزامنة الفورية — لا نزعج المستخدم.
            }
        }
    }

    companion object {
        /**
         * مقارنة تصاعدية لأرقام الغرف: القيم الرقمية أولاً (تصاعدياً)، ثم
         * القيم النصية أبجدياً — نظير
         * InformationScreen.compareByRoomNumber (information_screen.dart
         * l.28-41) الذي يختبره information_screen_sort_test.dart.
         */
        fun compareByRoomNumber(a: GuestInfo, b: GuestInfo): Int {
            val aNum = a.roomNumber.toIntOrNull()
            val bNum = b.roomNumber.toIntOrNull()
            if (aNum != null && bNum != null) return aNum.compareTo(bNum)
            if (aNum != null) return -1
            if (bNum != null) return 1
            return a.roomNumber.compareTo(b.roomNumber)
        }

        /** نسخة جديدة مرتّبة تصاعدياً حسب رقم الغرفة دون تعديل الأصل. */
        fun sortedByRoomNumber(entries: List<GuestInfo>): List<GuestInfo> =
            entries.sortedWith { a, b -> compareByRoomNumber(a, b) }
    }
}
