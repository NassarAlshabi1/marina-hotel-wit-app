package com.marinahotel.kotlin.settings.guests

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemGuestBinding

class GuestsAdapter : RecyclerView.Adapter<GuestsAdapter.GuestViewHolder>() {
    private val items = mutableListOf<GuestItem>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): GuestViewHolder {
        val binding = ItemGuestBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return GuestViewHolder(binding)
    }

    override fun onBindViewHolder(holder: GuestViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    fun submitList(data: List<GuestItem>) {
        items.clear()
        items.addAll(data)
        notifyDataSetChanged()
    }

    inner class GuestViewHolder(private val binding: ItemGuestBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: GuestItem) {
            binding.guestName.text = item.name
            binding.guestContact.text = item.contact
            binding.guestHistory.text = "عدد الزيارات: ${item.visits}"
        }
    }
}
