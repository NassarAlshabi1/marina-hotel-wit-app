package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemChargeBinding

class ChargesAdapter : ListAdapter<ChargeItem, ChargesAdapter.ChargeViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<ChargeItem>() {
        override fun areItemsTheSame(oldItem: ChargeItem, newItem: ChargeItem): Boolean = oldItem.title == newItem.title && oldItem.description == newItem.description
        override fun areContentsTheSame(oldItem: ChargeItem, newItem: ChargeItem): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ChargeViewHolder {
        val binding = ItemChargeBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ChargeViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ChargeViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class ChargeViewHolder(private val binding: ItemChargeBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: ChargeItem) {
            binding.chargeTitle.text = item.title
            binding.chargeDescription.text = item.description
            binding.chargeAmount.text = item.amount
            binding.chargeStatus.text = item.status
        }
    }
}