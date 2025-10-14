package com.marinahotel.kotlin.settings.guests

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemGuestBinding

class GuestsAdapter : ListAdapter<GuestItem, GuestsAdapter.GuestViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<GuestItem>() {
        override fun areItemsTheSame(oldItem: GuestItem, newItem: GuestItem): Boolean = oldItem.name == newItem.name
        override fun areContentsTheSame(oldItem: GuestItem, newItem: GuestItem): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): GuestViewHolder {
        val binding = ItemGuestBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return GuestViewHolder(binding)
    }

    override fun onBindViewHolder(holder: GuestViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class GuestViewHolder(private val binding: ItemGuestBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: GuestItem) {
            binding.guestName.text = item.name
            binding.guestContact.text = item.contact
            binding.guestHistory.text = "عدد الزيارات: ${item.visits}"
        }
    }
}