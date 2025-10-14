package com.marinahotel.kotlin.presentation.booking

import android.graphics.drawable.Drawable
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemBookingListBinding

class BookingListAdapter(
    private val onBookingClick: (BookingListViewModel.BookingListItem) -> Unit
) : ListAdapter<BookingListViewModel.BookingListItem, BookingListAdapter.BookingViewHolder>(BookingDiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): BookingViewHolder {
        val binding = ItemBookingListBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return BookingViewHolder(binding, onBookingClick)
    }

    override fun onBindViewHolder(holder: BookingViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class BookingViewHolder(
        private val binding: ItemBookingListBinding,
        private val onBookingClick: (BookingListViewModel.BookingListItem) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(item: BookingListViewModel.BookingListItem) {
            val context = binding.root.context
            binding.guestName.text = item.guestName
            binding.roomNumber.text = context.getString(R.string.label_room_number, item.roomNumber)
            binding.nightsText.text = context.getString(R.string.label_nights, item.nights)
            binding.checkinDate.text = context.getString(R.string.label_checkin, item.checkinDateText)
            binding.checkoutDate.text = item.checkoutDateText?.let {
                context.getString(R.string.label_checkout, it)
            } ?: context.getString(R.string.label_checkout, context.getString(R.string.label_not_set))
            binding.totalAmount.text = context.getString(
                R.string.label_value_format,
                context.getString(R.string.label_total_amount),
                context.getString(R.string.label_amount_format, item.totalAmount)
            )
            binding.remainingAmount.text = context.getString(
                R.string.label_value_format,
                context.getString(R.string.label_remaining_amount),
                context.getString(R.string.label_amount_format, item.remainingAmount)
            )
            val remainingColor = if (item.remainingAmount > 0) R.color.color_error else R.color.color_success
            binding.remainingAmount.setTextColor(ContextCompat.getColor(context, remainingColor))

            val chipDrawable: Drawable = DrawableCompat.wrap(binding.statusChip.background)
            DrawableCompat.setTint(
                chipDrawable,
                ContextCompat.getColor(context, item.status.colorRes)
            )
            binding.statusChip.background = chipDrawable
            binding.statusChip.text = context.getString(item.status.labelRes)

            binding.root.setOnClickListener { onBookingClick(item) }
        }
    }

    private object BookingDiffCallback : DiffUtil.ItemCallback<BookingListViewModel.BookingListItem>() {
        override fun areItemsTheSame(
            oldItem: BookingListViewModel.BookingListItem,
            newItem: BookingListViewModel.BookingListItem
        ): Boolean = oldItem.id == newItem.id

        override fun areContentsTheSame(
            oldItem: BookingListViewModel.BookingListItem,
            newItem: BookingListViewModel.BookingListItem
        ): Boolean = oldItem == newItem
    }
}
