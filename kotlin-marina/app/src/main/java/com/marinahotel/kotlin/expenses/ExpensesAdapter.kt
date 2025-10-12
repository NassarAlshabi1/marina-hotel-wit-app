package com.marinahotel.kotlin.expenses

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemExpenseBinding

class ExpensesAdapter(private val listener: ExpenseListener) : RecyclerView.Adapter<ExpensesAdapter.ExpenseViewHolder>() {
    private val items = mutableListOf<ExpenseUi>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ExpenseViewHolder {
        val binding = ItemExpenseBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ExpenseViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ExpenseViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    fun submitList(data: List<ExpenseUi>) {
        items.clear()
        items.addAll(data)
        notifyDataSetChanged()
    }

    inner class ExpenseViewHolder(private val binding: ItemExpenseBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: ExpenseUi) {
            binding.expenseDescription.text = item.description
            binding.expenseType.text = item.type
            binding.expenseDate.text = item.date
            binding.expenseAmount.text = "${item.amount} ر.س"
            binding.root.setOnClickListener { listener.onEditExpense(item) }
        }
    }

    interface ExpenseListener {
        fun onEditExpense(expense: ExpenseUi)
    }
}
