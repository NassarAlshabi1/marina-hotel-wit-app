package com.marina.marina.presentation.employees

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.model.SalaryWithdrawal
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.SalaryWithdrawalsRepository
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class EmployeeWithWithdrawals(
    val employee: Employee,
    val withdrawals: List<SalaryWithdrawal>,
    val totalWithdrawn: Double
)

data class EmployeesUiState(
    val isLoading: Boolean = false,
    val employees: List<EmployeeWithWithdrawals> = emptyList(),
    val searchQuery: String = "",
    val statusFilter: String = "active", // active | terminated | all
    val error: String? = null,
    val message: String? = null
) {
    val filtered: List<EmployeeWithWithdrawals>
        get() {
            var list = employees
            when (statusFilter) {
                "active" -> list = list.filter { StatusUtils.isEmployeeActive(it.employee.status) }
                "terminated" -> list = list.filter { StatusUtils.isEmployeeTerminated(it.employee.status) }
            }
            val q = searchQuery.trim()
            if (q.isNotBlank()) {
                list = list.filter {
                    it.employee.name.contains(q, ignoreCase = true) ||
                        it.employee.position.contains(q, ignoreCase = true) ||
                        it.employee.phone.contains(q)
                }
            }
            return list
        }

    val activeCount: Int get() = employees.count { StatusUtils.isEmployeeActive(it.employee.status) }
    val totalSalaries: Double get() = employees.filter { StatusUtils.isEmployeeActive(it.employee.status) }.sumOf { it.employee.basicSalary }
}

@HiltViewModel
class EmployeesViewModel @Inject constructor(
    private val employeesRepository: EmployeesRepository,
    private val salaryWithdrawalsRepository: SalaryWithdrawalsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(EmployeesUiState(isLoading = true))
    val state: StateFlow<EmployeesUiState> = _state.asStateFlow()

    init {
        combine(employeesRepository.getAll(), salaryWithdrawalsRepository.getAll()) { employees, withdrawals ->
            employees.map { employee ->
                val own = withdrawals.filter { it.employeeId == employee.id }
                EmployeeWithWithdrawals(
                    employee = employee,
                    withdrawals = own,
                    totalWithdrawn = own.sumOf { it.amount }
                )
            }
        }.onEach { combined ->
            _state.value = _state.value.copy(isLoading = false, employees = combined, error = null)
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun setStatusFilter(filter: String) {
        _state.value = _state.value.copy(statusFilter = filter)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    fun saveEmployee(employee: Employee) {
        viewModelScope.launch {
            try {
                if (employee.id == 0L) {
                    employeesRepository.insert(employee.copy(status = employee.status.ifBlank { "نشط" }))
                    _state.value = _state.value.copy(message = "تمت إضافة الموظف")
                } else {
                    employeesRepository.update(employee)
                    _state.value = _state.value.copy(message = "تم تحديث الموظف")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun terminateEmployee(employee: Employee, reason: String) {
        viewModelScope.launch {
            try {
                employeesRepository.terminate(employee.id, reason.ifBlank { null })
                _state.value = _state.value.copy(message = "تم إنهاء خدمة الموظف")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun reactivateEmployee(employee: Employee) {
        viewModelScope.launch {
            try {
                employeesRepository.update(employee.copy(status = "نشط", terminationDate = null, terminationReason = null))
                _state.value = _state.value.copy(message = "تمت إعادة تنشيط الموظف")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    /** Records a salary withdrawal (سلفة / سحب راتب / خصم). */
    fun addWithdrawal(employee: Employee, amount: Double, type: String, reason: String?) {
        viewModelScope.launch {
            try {
                if (amount <= 0) {
                    _state.value = _state.value.copy(message = "المبلغ غير صالح")
                    return@launch
                }
                salaryWithdrawalsRepository.insert(
                    SalaryWithdrawal(
                        employeeId = employee.id,
                        employeeName = employee.name,
                        amount = amount,
                        withdrawalType = type,
                        reason = reason
                    )
                )
                _state.value = _state.value.copy(message = "تم تسجيل $type")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
