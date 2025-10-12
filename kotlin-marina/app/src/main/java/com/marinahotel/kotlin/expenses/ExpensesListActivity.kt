package com.marinahotel.kotlin.expenses

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.ActivityExpensesListBinding
import com.marinahotel.kotlin.databinding.DialogExpenseFormBinding

class ExpensesListActivity : AppCompatActivity(), ExpensesAdapter.ExpenseListener {
    private lateinit var binding: ActivityExpensesListBinding
    private val adapter = ExpensesAdapter(this)
    private val expenses = mutableListOf(
        ExpenseUi("صيانة مصعد", "صيانة", "10 يناير", 1500.0),
        ExpenseUi("خدمات تنظيف", "تشغيل", "9 يناير", 800.0),
        ExpenseUi("معدات مطبخ", "استثمار", "5 يناير", 4200.0)
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityExpensesListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.expensesRecycler.layoutManager = LinearLayoutManager(this)
        binding.expensesRecycler.adapter = adapter
        adapter.submitList(expenses.toList())
        binding.addExpenseFab.setOnClickListener { showExpenseDialog() }
        binding.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                applyFilter()
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
        AlertDialog.Builder(this)
            .setTitle(if (expense == null) "مصروف جديد" else "تعديل المصروف")
            .setView(dialogBinding.root)
            .setPositiveButton("حفظ") { dialog, _ ->
                val description = dialogBinding.descriptionInput.text.toString()
                val type = dialogBinding.typeInput.text.toString()
                val amount = dialogBinding.amountInput.text.toString().toDoubleOrNull() ?: 0.0
                val date = dialogBinding.dateInput.text.toString()
                if (expense == null) {
                    expenses.add(ExpenseUi(description, type, date, amount))
                } else {
                    val index = expenses.indexOf(expense)
                    if (index >= 0) {
                        expenses[index] = expense.copy(description = description, type = type, date = date, amount = amount)
                    }
                }
                adapter.submitList(expenses.toList())
                applyFilter()
                Toast.makeText(this, "تم الحفظ", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton("إلغاء") { dialog, _ -> dialog.dismiss() }
            .show()
    }

    private fun applyFilter() {
        val query = binding.searchInput.text?.toString().orEmpty()
        val filtered = expenses.filter { it.description.contains(query) || it.type.contains(query) }
        adapter.submitList(filtered)
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
