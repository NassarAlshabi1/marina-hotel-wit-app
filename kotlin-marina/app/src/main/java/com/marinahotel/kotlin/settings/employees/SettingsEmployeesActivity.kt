package com.marinahotel.kotlin.settings.employees

import android.os.Bundle
import android.view.LayoutInflater
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.ActivitySettingsEmployeesBinding
import com.marinahotel.kotlin.databinding.DialogEmployeeFormBinding
import com.marinahotel.kotlin.employees.EmployeeUi
import com.marinahotel.kotlin.employees.EmployeesAdapter

class SettingsEmployeesActivity : AppCompatActivity(), EmployeesAdapter.EmployeeListener {
    private lateinit var binding: ActivitySettingsEmployeesBinding
    private val adapter = EmployeesAdapter(this)
    private val employees = mutableListOf(
        EmployeeUi("أحمد العتيبي", "مدير استقبال", "0501234567", true, 5500.0),
        EmployeeUi("نورة السبيعي", "مسؤولة حجوزات", "0507654321", true, 4200.0),
        EmployeeUi("يوسف الغامدي", "خدمة غرف", "0567891234", false, 3200.0)
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsEmployeesBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.employeesRecycler.layoutManager = LinearLayoutManager(this)
        binding.employeesRecycler.adapter = adapter
        adapter.submitList(employees.toList())
        refreshSummary()
        binding.addEmployeeFab.setOnClickListener { showEmployeeDialog() }
    }

    private fun refreshSummary() {
        val active = employees.count { it.isActive }
        val total = employees.sumOf { it.salary }
        binding.activeCount.text = "$active موظف نشط"
        binding.monthlySalaries.text = "إجمالي الرواتب: ${total.toInt()} ر.س"
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
            .setTitle(if (employee == null) "إضافة موظف" else "تعديل الموظف")
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
                Toast.makeText(this, "تم حفظ البيانات", Toast.LENGTH_SHORT).show()
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
