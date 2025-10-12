package com.marinahotel.kotlin.settings.employees

import android.os.Bundle
import android.view.LayoutInflater
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ActivitySettingsEmployeesBinding
import com.marinahotel.kotlin.databinding.DialogEmployeeFormBinding
import com.marinahotel.kotlin.employees.EmployeeUi
import com.marinahotel.kotlin.employees.EmployeesAdapter
import com.marinahotel.kotlin.employees.EmployeesViewModel

class SettingsEmployeesActivity : AppCompatActivity(), EmployeesAdapter.EmployeeListener {
    private lateinit var binding: ActivitySettingsEmployeesBinding
    private val adapter = EmployeesAdapter(this)
    private lateinit var viewModel: EmployeesViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsEmployeesBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.employeesRecycler.layoutManager = LinearLayoutManager(this)
        binding.employeesRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[EmployeesViewModel::class.java]
        observeEmployees()
        binding.addEmployeeFab.setOnClickListener { showEmployeeDialog() }
    }

    private fun refreshSummary(list: List<EmployeeUi>) {
        val active = list.count { it.isActive }
        val total = list.sumOf { it.salary }
        binding.activeCount.text = getString(R.string.active_employees_format, active)
        binding.monthlySalaries.text = getString(R.string.total_salaries_format, total.toInt())
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
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (employee == null) getString(R.string.title_employee_new) else getString(R.string.title_employee_edit))
            .setView(dialogBinding.root)
            .setPositiveButton(R.string.action_save, null)
            .setNegativeButton(R.string.action_cancel) { d, _ -> d.dismiss() }
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = dialogBinding.nameInput.text?.toString()?.trim().orEmpty()
                val position = dialogBinding.positionInput.text?.toString()?.trim().orEmpty()
                val phone = dialogBinding.phoneInput.text?.toString()?.trim().orEmpty()
                val salaryText = dialogBinding.salaryInput.text?.toString()?.trim().orEmpty()

                var valid = true
                if (name.isBlank()) { dialogBinding.nameLayout.error = getString(R.string.error_required_name); valid = false } else dialogBinding.nameLayout.error = null
                if (phone.isBlank()) { dialogBinding.phoneLayout.error = getString(R.string.error_required_phone); valid = false } else dialogBinding.phoneLayout.error = null
                val salary = salaryText.toDoubleOrNull()
                if (salary == null || salary <= 0.0) { dialogBinding.salaryLayout.error = getString(R.string.error_positive_amount); valid = false } else dialogBinding.salaryLayout.error = null

                if (!valid) return@setOnClickListener

                val active = dialogBinding.activeSwitch.isChecked
                viewModel.save(name, position, phone, salary!!, active)
                Toast.makeText(this, R.string.saved_successfully, Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
        }
        dialog.show()
    }

    override fun onEditRequested(employee: EmployeeUi) {
        showEmployeeDialog(employee)
    }

    override fun onSalaryRequested(employee: EmployeeUi) {
        Toast.makeText(this, getString(R.string.salary_withdrawal_success, employee.salary.toInt()), Toast.LENGTH_SHORT).show()
    }

    private fun observeEmployees() {
        lifecycleScope.launchWhenStarted {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.employees.collect { list ->
                    adapter.submitList(list)
                    refreshSummary(list)
                }
            }
        }
    }
}
