package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Employee
import kotlinx.coroutines.flow.Flow

interface EmployeesRepository {
    fun getAll(): Flow<List<Employee>>
    suspend fun insert(employee: Employee): Long
    suspend fun update(employee: Employee)
    suspend fun terminate(id: Long, reason: String? = null)
}
