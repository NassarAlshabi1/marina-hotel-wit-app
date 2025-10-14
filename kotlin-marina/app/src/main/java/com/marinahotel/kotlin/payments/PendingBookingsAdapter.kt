package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemBookingBalanceBinding

class PendingBookingsAdapter(private val listener: PendingBookingListener) : ListAdapter<PendingBookingItem, PendingBookingsAdapter.PendingViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<PendingBookingItem>() {
        override fun areItemsTheSame(oldItem: PendingBookingItem, newItem: PendingBookingItem): Boolean = oldItem.code == newItem.code
        override fun areContentsTheSame(oldItem: PendingBookingItem, newItem: PendingBookingItem): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PendingViewHolder {
        val binding = ItemBookingBalanceBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PendingViewHolder(binding)
    }

    override fun onBindViewHolder(holder: PendingViewHolder, position: Int) {
        holder.bind(getItem(position))
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