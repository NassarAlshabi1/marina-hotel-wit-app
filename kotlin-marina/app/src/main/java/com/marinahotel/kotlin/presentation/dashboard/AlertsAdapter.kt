package com.marinahotel.kotlin.presentation.dashboard

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemDashboardAlertBinding

class AlertsAdapter : ListAdapter<AlertUiModel, AlertsAdapter.AlertViewHolder>(AlertDiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): AlertViewHolder {
        val binding = ItemDashboardAlertBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return AlertViewHolder(binding)
    }

    override fun onBindViewHolder(holder: AlertViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class AlertViewHolder(
        private val binding: ItemDashboardAlertBinding
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(item: AlertUiModel) {
            binding.alertText.text = item.text
            binding.alertMeta.text = item.meta
            binding.alertMeta.visibility = if (item.meta.isNullOrEmpty()) android.view.View.GONE else android.view.View.VISIBLE
            val color = ContextCompat.getColor(binding.root.context, item.accentColorRes)
            binding.root.strokeColor = color
        }
    }

    private object AlertDiffCallback : DiffUtil.ItemCallback<AlertUiModel>() {
        override fun areItemsTheSame(oldItem: AlertUiModel, newItem: AlertUiModel): Boolean = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: AlertUiModel, newItem: AlertUiModel): Boolean = oldItem == newItem
    }
}
