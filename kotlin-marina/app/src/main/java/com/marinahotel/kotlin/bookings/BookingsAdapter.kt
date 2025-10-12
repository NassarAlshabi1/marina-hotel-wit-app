package com.marinahotel.kotlin.bookings

import android.graphics.PorterDuff
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemBookingBinding

class BookingsAdapter(private val listener: BookingListener) : ListAdapter<BookingUi, BookingsAdapter.BookingViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<BookingUi>() {
        override fun areItemsTheSame(oldItem: BookingUi, newItem: BookingUi): Boolean = oldItem.code == newItem.code
        override fun areContentsTheSame(oldItem: BookingUi, newItem: BookingUi): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): BookingViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        val binding = ItemBookingBinding.inflate(inflater, parent, false)
        return BookingViewHolder(binding)
    }

    override fun onBindViewHolder(holder: BookingViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class BookingViewHolder(private val binding: ItemBookingBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: BookingUi) {
            binding.guestName.text = item.guestName
            binding.bookingCode.text = item.code
            binding.roomInfo.text = binding.root.context.getString(R.string.room_number_format, item.roomNumber)
            binding.statusChip.text = item.status
            binding.dateRange.text = binding.root.context.getString(R.string.date_range_format, item.arrivalDate, item.departureDate)
            val color = when {
                item.status.contains("نشط") -> R.color.primaryColor
                item.status.contains("مؤكد") -> android.R.color.holo_blue_dark
                item.status.contains("مكتمل") -> android.R.color.holo_green_dark
                item.status.contains("ملغى") -> android.R.color.holo_red_dark
                else -> R.color.textSecondary
            }
            val resolved = ContextCompat.getColor(binding.root.context, color)
            binding.statusChip.setTextColor(resolved)
            binding.statusChip.background.setColorFilter(resolved, PorterDuff.Mode.SRC_ATOP)
            binding.root.setOnClickListener { listener.onBookingSelected(item) }
            binding.paymentButton.setOnClickListener { listener.onPaymentRequested(item) }
            binding.checkoutButton.setOnClickListener { listener.onCheckoutRequested(item) }
        }
    }

    interface BookingListener {
        fun onBookingSelected(booking: BookingUi)
        fun onPaymentRequested(booking: BookingUi)
        fun onCheckoutRequested(booking: BookingUi)
    }
}