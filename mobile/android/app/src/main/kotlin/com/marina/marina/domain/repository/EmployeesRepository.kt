package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Employee
import kotlinx.coroutines.flow.Flow

interface EmployeesRepository {
    fun getAll(): Flow<List<Employee>>
    suspend fun insert(employee: Employee): Long
    suspend fun update(employee: Employee)

    /**
     * Dart terminate contract: [terminationType] is فصل / استقالة / استغناء
     * (canonicalized into the status field), [terminationDate] is yyyy-MM-dd.
     */
    suspend fun terminate(id: Long, terminationType: String, terminationDate: String, reason: String? = null)

    /** Dart soft-delete flow (employees_list.dart l.567-650). */
    suspend fun softDelete(id: Long)
}
