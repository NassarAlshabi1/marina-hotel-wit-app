package com.marinahotel.kotlin.expenses

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ActivityExpensesListBinding
import com.marinahotel.kotlin.databinding.DialogExpenseFormBinding

class ExpensesListActivity : AppCompatActivity(), ExpensesAdapter.ExpenseListener {
    private lateinit var binding: ActivityExpensesListBinding
    private val adapter = ExpensesAdapter(this)
    private lateinit var viewModel: ExpensesViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityExpensesListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.expensesRecycler.layoutManager = LinearLayoutManager(this)
        binding.expensesRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[ExpensesViewModel::class.java]
        observeExpenses()
        binding.addExpenseFab.setOnClickListener { showExpenseDialog() }
        binding.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val q = s?.toString().orEmpty()
                adapter.submitList(viewModel.expenses.value.filter { it.description.contains(q) || it.type.contains(q) })
            }
        })
    }

    private fun showExpenseDialog(expense: ExpenseUi? = null) {
        val dialogBinding = DialogExpenseFormBinding.inflate(LayoutInflater.from(this))
        if (expense != null) {
            dialogBinding.descriptionInput.setText(expense.description)
            dialogBinding.typeInput.setText(expense.type)
            dialogBinding.amountInput.setText(expense.amount.toString())
            dialogBinding.dateInput.setText(expense.date)
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(if (expense == null) getString(R.string.title_expense_new) else getString(R.string.title_expense_edit))
            .setView(dialogBinding.root)
            .setPositiveButton(R.string.action_save, null)
            .setNegativeButton(R.string.action_cancel) { d, _ -> d.dismiss() }
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val description = dialogBinding.descriptionInput.text?.toString()?.trim().orEmpty()
                val type = dialogBinding.typeInput.text?.toString()?.trim().orEmpty()
                val date = dialogBinding.dateInput.text?.toString()?.trim().orEmpty()
                val amountText = dialogBinding.amountInput.text?.toString()?.trim().orEmpty()

                var valid = true
                if (description.isBlank()) { dialogBinding.descriptionLayout.error = getString(R.string.error_required_description); valid = false } else dialogBinding.descriptionLayout.error = null
                val amount = amountText.toDoubleOrNull()
                if (amount == null || amount <= 0.0) { dialogBinding.amountLayout.error = getString(R.string.error_positive_amount); valid = false } else dialogBinding.amountLayout.error = null
                if (date.isBlank()) { dialogBinding.dateLayout.error = getString(R.string.error_required_date); valid = false } else dialogBinding.dateLayout.error = null

                if (!valid) return@setOnClickListener

                viewModel.save(description, type, date, amount!!)
                Toast.makeText(this, R.string.saved_successfully, Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
        }
        dialog.show()
    }

    private fun observeExpenses() {
        lifecycleScope.launchWhenStarted {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.expenses.collect { list -> adapter.submitList(list) }
            }
        }
    }

    override fun onEditExpense(expense: ExpenseUi) {
        showExpenseDialog(expense)
    }
}

data class ExpenseUi(
    val description: String,
    val type: String,
    val date: String,
    val amount: Double
)
