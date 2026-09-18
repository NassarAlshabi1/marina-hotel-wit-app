package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.repository.EmployeesRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class EmployeesRepositoryImpl @Inject constructor(
    private val employeesDao: EmployeesDao
) : EmployeesRepository {

    override fun getAll(): Flow<List<Employee>> =
        employeesDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(employee: Employee): Long = employeesDao.insert(employee.toEntity())

    override suspend fun update(employee: Employee) = employeesDao.update(employee.toEntity())

    override suspend fun terminate(id: Long, reason: String?) {
        employeesDao.terminate(
            id,
            status = "terminated",
            terminationDate = null,
            terminationReason = reason,
            updatedAt = System.currentTimeMillis()
        )
    }
}
