package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemBookingBalanceBinding

class PendingBookingsAdapter(private val listener: PendingBookingListener) : RecyclerView.Adapter<PendingBookingsAdapter.PendingViewHolder>() {
    private val items = mutableListOf<PendingBookingItem>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PendingViewHolder {
        val binding = ItemBookingBalanceBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PendingViewHolder(binding)
    }

    override fun onBindViewHolder(holder: PendingViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    fun submitList(data: List<PendingBookingItem>) {
        items.clear()
        items.addAll(data)
        notifyDataSetChanged()
    }

    inner class PendingViewHolder(private val binding: ItemBookingBalanceBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: PendingBookingItem) {
            binding.bookingTitle.text = item.room
            binding.guestName.text = item.guestName
            binding.paidAmount.text = "مدفوع: ${item.paid}"
            binding.pendingAmount.text = "متبقي: ${item.remaining}"
            binding.manageButton.setOnClickListener { listener.onManagePayments(item) }
        }
    }

    interface PendingBookingListener {
        fun onManagePayments(item: PendingBookingItem)
    }
}
