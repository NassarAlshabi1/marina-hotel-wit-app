package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.EmployeeDao
import com.marinahotel.kotlin.data.entities.EmployeeEntity
import kotlinx.coroutines.flow.Flow

class EmployeesRepository(private val employeeDao: EmployeeDao) {
    fun flowAllEmployees(): Flow<List<EmployeeEntity>> = employeeDao.flowAll()
    suspend fun getAll(): List<EmployeeEntity> = employeeDao.getAll()
    suspend fun save(employee: EmployeeEntity) { employeeDao.insert(employee) }
}