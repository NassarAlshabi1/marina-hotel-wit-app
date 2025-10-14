package com.marinahotel.kotlin.presentation.reports

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemReportsSummaryBinding

class ReportsSummaryAdapter :
    ListAdapter<ReportsViewModel.DailySummary, ReportsSummaryAdapter.SummaryViewHolder>(DiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SummaryViewHolder {
        val binding = ItemReportsSummaryBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return SummaryViewHolder(binding)
    }

    override fun onBindViewHolder(holder: SummaryViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class SummaryViewHolder(
        private val binding: ItemReportsSummaryBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(item: ReportsViewModel.DailySummary) {
            val context = binding.root.context
            binding.summaryDate.text = item.label
            binding.summaryOccupancy.text = context.getString(R.string.label_occupancy_percent, item.occupancyPercent)
            val revenueFormatted = context.getString(R.string.label_amount_format, item.revenue)
            binding.summaryRevenue.text = context.getString(R.string.label_revenue_amount, revenueFormatted)
            val expensesFormatted = context.getString(R.string.label_amount_format, item.expenses)
            binding.summaryExpenses.text = context.getString(R.string.label_expense_amount, expensesFormatted)
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<ReportsViewModel.DailySummary>() {
        override fun areItemsTheSame(oldItem: ReportsViewModel.DailySummary, newItem: ReportsViewModel.DailySummary): Boolean =
            oldItem.date == newItem.date

        override fun areContentsTheSame(oldItem: ReportsViewModel.DailySummary, newItem: ReportsViewModel.DailySummary): Boolean =
            oldItem == newItem
    }
}
