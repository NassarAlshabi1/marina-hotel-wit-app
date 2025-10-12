package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemPaymentTransactionBinding

class BookingPaymentAdapter : RecyclerView.Adapter<BookingPaymentAdapter.PaymentViewHolder>() {
    private val items = mutableListOf<PaymentTransaction>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PaymentViewHolder {
        val binding = ItemPaymentTransactionBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PaymentViewHolder(binding)
    }

    override fun onBindViewHolder(holder: PaymentViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    fun submitList(data: List<PaymentTransaction>) {
        items.clear()
        items.addAll(data)
        notifyDataSetChanged()
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
