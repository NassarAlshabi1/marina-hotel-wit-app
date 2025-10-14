package com.marinahotel.kotlin.presentation.booking

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemBookingPaymentBinding

class BookingPaymentsAdapter(
    private val formatDateTime: (Long) -> String
) : ListAdapter<BookingDetailsViewModel.PaymentItem, BookingPaymentsAdapter.PaymentViewHolder>(DiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PaymentViewHolder {
        val binding = ItemBookingPaymentBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return PaymentViewHolder(binding, formatDateTime)
    }

    override fun onBindViewHolder(holder: PaymentViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class PaymentViewHolder(
        private val binding: ItemBookingPaymentBinding,
        private val formatDateTime: (Long) -> String
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(item: BookingDetailsViewModel.PaymentItem) {
            val context = binding.root.context
            binding.paymentAmount.text = context.getString(R.string.label_amount_format, item.amount)
            binding.paymentMethod.text = context.getString(R.string.label_payment_method_value, item.method)
            binding.paymentDate.text = context.getString(R.string.label_payment_date_value, formatDateTime(item.paymentDate))
            if (item.notes.isBlank()) {
                binding.paymentNotes.isVisible = false
            } else {
                binding.paymentNotes.isVisible = true
                binding.paymentNotes.text = context.getString(R.string.label_payment_notes_value, item.notes)
            }
        }
    }

    private object DiffCallback : DiffUtil.ItemCallback<BookingDetailsViewModel.PaymentItem>() {
        override fun areItemsTheSame(
            oldItem: BookingDetailsViewModel.PaymentItem,
            newItem: BookingDetailsViewModel.PaymentItem
        ): Boolean = oldItem.id == newItem.id

        override fun areContentsTheSame(
            oldItem: BookingDetailsViewModel.PaymentItem,
            newItem: BookingDetailsViewModel.PaymentItem
        ): Boolean = oldItem == newItem
    }
}
