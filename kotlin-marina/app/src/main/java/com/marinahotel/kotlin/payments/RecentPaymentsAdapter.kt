package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemPaymentBinding

class RecentPaymentsAdapter : ListAdapter<PaymentItem, RecentPaymentsAdapter.PaymentViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<PaymentItem>() {
        override fun areItemsTheSame(oldItem: PaymentItem, newItem: PaymentItem): Boolean = oldItem.title == newItem.title && oldItem.amount == newItem.amount && oldItem.method == newItem.method
        override fun areContentsTheSame(oldItem: PaymentItem, newItem: PaymentItem): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PaymentViewHolder {
        val binding = ItemPaymentBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PaymentViewHolder(binding)
    }

    override fun onBindViewHolder(holder: PaymentViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class PaymentViewHolder(private val binding: ItemPaymentBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: PaymentItem) {
            binding.paymentTitle.text = item.title
            binding.paymentSubtitle.text = item.method
            binding.paymentAmount.text = item.amount
        }
    }
}