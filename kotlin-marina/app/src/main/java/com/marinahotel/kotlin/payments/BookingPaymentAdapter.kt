package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemPaymentTransactionBinding

class BookingPaymentAdapter : ListAdapter<PaymentTransaction, BookingPaymentAdapter.PaymentViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<PaymentTransaction>() {
        override fun areItemsTheSame(oldItem: PaymentTransaction, newItem: PaymentTransaction): Boolean = oldItem.title == newItem.title && oldItem.date == newItem.date
        override fun areContentsTheSame(oldItem: PaymentTransaction, newItem: PaymentTransaction): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PaymentViewHolder {
        val binding = ItemPaymentTransactionBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PaymentViewHolder(binding)
    }

    override fun onBindViewHolder(holder: PaymentViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class PaymentViewHolder(private val binding: ItemPaymentTransactionBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: PaymentTransaction) {
            binding.transactionTitle.text = item.title
            binding.transactionMethod.text = item.method
            binding.transactionDate.text = item.date
            binding.transactionAmount.text = item.amount
        }
    }
}