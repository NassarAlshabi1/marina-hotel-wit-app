package com.marina.marina.presentation.employees

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.model.SalaryCycle
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.SalaryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class EntitlementRow(
    val employee: Employee,
    val cycle: SalaryCycle?,
    val entitled: Double,
    val paid: Long,
    val remaining: Double
)

data class SalaryEntitlementsUiState(
    val isLoading: Boolean = true,
    val rows: List<EntitlementRow> = emptyList(),
    val cycleKey: String = "",
    val error: String? = null,
    val message: String? = null
)

@HiltViewModel
class SalaryEntitlementsViewModel @Inject constructor(
    private val employeesRepository: EmployeesRepository,
    private val salaryRepository: SalaryRepository
) : ViewModel() {

    private val _state = MutableStateFlow(SalaryEntitlementsUiState())
    val state: StateFlow<SalaryEntitlementsUiState> = _state.asStateFlow()

    init {
        employeesRepository.getAll().onEach { employees ->
            lastEmployees = employees
            rebuild(employees)
        }.launchIn(viewModelScope)
    }

    private var lastEmployees: List<Employee> = emptyList()

    fun setCycleKey(key: String) {
        _state.value = _state.value.copy(cycleKey = key)
        rebuild(lastEmployees)
    }

    private fun rebuild(employees: List<Employee>) {
        viewModelScope.launch {
            try {
                val key = _state.value.cycleKey
                val rows = employees.map { employee ->
                    val cycles = salaryRepository.getCycles(employee.id).first()
                    val cycle = if (key.isBlank()) cycles.firstOrNull()
                    else cycles.firstOrNull { it.cycleKey == key }
                    val paid = cycle?.actualPaid ?: 0L
                    EntitlementRow(
                        employee = employee,
                        cycle = cycle,
                        entitled = employee.basicSalary,
                        paid = paid,
                        remaining = employee.basicSalary - paid
                    )
                }
                _state.value = _state.value.copy(isLoading = false, rows = rows, error = null)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun openCycle(employee: Employee, cycleKey: String) {
        viewModelScope.launch {
            try {
                salaryRepository.insertCycle(
                    SalaryCycle(
                        employeeId = employee.id,
                        cycleKey = cycleKey,
                        expectedAmount = employee.basicSalary.toLong()
                    )
                )
                _state.value = _state.value.copy(message = "تم فتح الدورة")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun consumeMessage() { _state.value = _state.value.copy(message = null, error = null) }
}
