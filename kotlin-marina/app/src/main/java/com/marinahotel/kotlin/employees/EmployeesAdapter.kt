package com.marinahotel.kotlin.employees

import android.graphics.PorterDuff
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemEmployeeBinding

class EmployeesAdapter(private val listener: EmployeeListener) : ListAdapter<EmployeeUi, EmployeesAdapter.EmployeeViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<EmployeeUi>() {
        override fun areItemsTheSame(oldItem: EmployeeUi, newItem: EmployeeUi): Boolean = oldItem.name == newItem.name
        override fun areContentsTheSame(oldItem: EmployeeUi, newItem: EmployeeUi): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): EmployeeViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        val binding = ItemEmployeeBinding.inflate(inflater, parent, false)
        return EmployeeViewHolder(binding)
    }

    override fun onBindViewHolder(holder: EmployeeViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class EmployeeViewHolder(private val binding: ItemEmployeeBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: EmployeeUi) {
            binding.employeeName.text = item.name
            binding.employeePosition.text = item.position
            binding.employeePhone.text = item.phone
            binding.employeeStatus.text = if (item.isActive) binding.root.context.getString(R.string.status_active) else binding.root.context.getString(R.string.status_inactive)
            val colorRes = if (item.isActive) R.color.primaryColor else android.R.color.darker_gray
            val color = ContextCompat.getColor(binding.root.context, colorRes)
            binding.employeeStatus.setTextColor(color)
            binding.employeeStatus.background.setColorFilter(color, PorterDuff.Mode.SRC_ATOP)
            binding.editButton.setOnClickListener { listener.onEditRequested(item) }
            binding.salaryButton.setOnClickListener { listener.onSalaryRequested(item) }
        }
    }

    interface EmployeeListener {
        fun onEditRequested(employee: EmployeeUi)
        fun onSalaryRequested(employee: EmployeeUi)
    }
}