package com.marinahotel.kotlin.employees

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.entities.EmployeeEntity
import com.marinahotel.kotlin.data.repository.EmployeesRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class EmployeesViewModel(application: Application) : AndroidViewModel(application) {
    private val repo = EmployeesRepository(HotelDatabase.getInstance(application).employeeDao())

    val employees: StateFlow<List<EmployeeUi>> = repo.flowAllEmployees()
        .map { list ->
            list.map { EmployeeUi(name = it.name, position = "", phone = "", isActive = it.status == "active", salary = it.basicSalary) }
        }
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    fun save(name: String, position: String, phone: String, salary: Double, isActive: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            repo.save(
                EmployeeEntity(
                    name = name,
                    basicSalary = salary,
                    status = if (isActive) "active" else "inactive"
                )
            )
        }
    }
}