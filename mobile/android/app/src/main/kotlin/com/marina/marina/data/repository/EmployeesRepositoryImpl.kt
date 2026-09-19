package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.repository.EmployeesRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class EmployeesRepositoryImpl @Inject constructor(
    private val employeesDao: EmployeesDao,
    private val outboxRepository: OutboxRepository
) : EmployeesRepository {

    override fun getAll(): Flow<List<Employee>> =
        employeesDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insert(employee: Employee): Long {
        val now = System.currentTimeMillis()
        val prepared = employee.copy(
            localUuid = employee.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (employee.createdAt == 0L) now else employee.createdAt,
            updatedAt = now
        )
        val id = employeesDao.insert(prepared.toEntity())
        outboxRepository.enqueueObject("employees", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(employee: Employee) {
        val prepared = employee.copy(updatedAt = System.currentTimeMillis())
        employeesDao.update(prepared.toEntity())
        outboxRepository.enqueueObject("employees", "update", prepared.localUuid, prepared)
    }

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
