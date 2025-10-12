package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemPaymentBinding

class RecentPaymentsAdapter : RecyclerView.Adapter<RecentPaymentsAdapter.PaymentViewHolder>() {
    private val items = mutableListOf<PaymentItem>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PaymentViewHolder {
        val binding = ItemPaymentBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PaymentViewHolder(binding)
    }

    override fun onBindViewHolder(holder: PaymentViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    fun submitList(data: List<PaymentItem>) {
        items.clear()
        items.addAll(data)
        notifyDataSetChanged()
    }

    inner class PaymentViewHolder(private val binding: ItemPaymentBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: PaymentItem) {
            binding.paymentTitle.text = item.title
            binding.paymentSubtitle.text = item.method
            binding.paymentAmount.text = item.amount
        }
    }
}
