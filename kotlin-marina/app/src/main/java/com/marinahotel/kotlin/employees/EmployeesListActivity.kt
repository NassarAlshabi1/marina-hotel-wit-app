package com.marinahotel.kotlin.employees

import android.os.Bundle
import android.view.LayoutInflater
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.ActivityEmployeesListBinding
import com.marinahotel.kotlin.databinding.DialogEmployeeFormBinding

class EmployeesListActivity : AppCompatActivity(), EmployeesAdapter.EmployeeListener {
    private lateinit var binding: ActivityEmployeesListBinding
    private val adapter = EmployeesAdapter(this)
    private val employees = mutableListOf(
        EmployeeUi("أحمد العتيبي", "مدير استقبال", "0501234567", true, 5500.0),
        EmployeeUi("نورة السبيعي", "مسؤولة حجوزات", "0507654321", true, 4200.0),
        EmployeeUi("يوسف الغامدي", "خدمة غرف", "0556789123", false, 3200.0)
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityEmployeesListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.employeesRecycler.layoutManager = LinearLayoutManager(this)
        binding.employeesRecycler.adapter = adapter
        refreshSummary()
        adapter.submitList(employees.toList())
        binding.addEmployeeButton.setOnClickListener { showEmployeeDialog() }
    }

    private fun refreshSummary() {
        val activeCount = employees.count { it.isActive }
        binding.employeeCount.text = "${employees.size} موظف"
        binding.activeEmployees.text = "$activeCount نشط"
    }

    private fun showEmployeeDialog(employee: EmployeeUi? = null) {
        val dialogBinding = DialogEmployeeFormBinding.inflate(LayoutInflater.from(this))
        if (employee != null) {
            dialogBinding.nameInput.setText(employee.name)
            dialogBinding.positionInput.setText(employee.position)
            dialogBinding.phoneInput.setText(employee.phone)
            dialogBinding.salaryInput.setText(employee.salary.toString())
            dialogBinding.activeSwitch.isChecked = employee.isActive
        }
        AlertDialog.Builder(this)
            .setTitle(if (employee == null) "موظف جديد" else "تعديل الموظف")
            .setView(dialogBinding.root)
            .setPositiveButton("حفظ") { dialog, _ ->
                val name = dialogBinding.nameInput.text.toString()
                val position = dialogBinding.positionInput.text.toString()
                val phone = dialogBinding.phoneInput.text.toString()
                val salary = dialogBinding.salaryInput.text.toString().toDoubleOrNull() ?: 0.0
                val active = dialogBinding.activeSwitch.isChecked
                if (employee == null) {
                    employees.add(EmployeeUi(name, position, phone, active, salary))
                } else {
                    val index = employees.indexOfFirst { it.name == employee.name }
                    if (index >= 0) {
                        employees[index] = employee.copy(name = name, position = position, phone = phone, isActive = active, salary = salary)
                    }
                }
                adapter.submitList(employees.toList())
                refreshSummary()
                Toast.makeText(this, "تم الحفظ", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton("إلغاء") { dialog, _ -> dialog.dismiss() }
            .show()
    }

    override fun onEditRequested(employee: EmployeeUi) {
        showEmployeeDialog(employee)
    }

    override fun onSalaryRequested(employee: EmployeeUi) {
        Toast.makeText(this, "تم تسجيل صرف راتب ${employee.salary}", Toast.LENGTH_SHORT).show()
    }
}

data class EmployeeUi(
    val name: String,
    val position: String,
    val phone: String,
    val isActive: Boolean,
    val salary: Double
)
