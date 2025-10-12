package com.marinahotel.kotlin.rooms

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemRoomBinding

class RoomsAdapter(private val listener: RoomListener) : ListAdapter<RoomItem, RoomsAdapter.RoomViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<RoomItem>() {
        override fun areItemsTheSame(oldItem: RoomItem, newItem: RoomItem): Boolean = oldItem.number == newItem.number
        override fun areContentsTheSame(oldItem: RoomItem, newItem: RoomItem): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RoomViewHolder {
        val binding = ItemRoomBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return RoomViewHolder(binding)
    }

    override fun onBindViewHolder(holder: RoomViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class RoomViewHolder(private val binding: ItemRoomBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: RoomItem) {
            binding.roomNumber.text = item.number
            binding.roomStatus.text = item.status
            binding.roomType.text = item.type
            val color = when {
                item.status.contains("شاغرة") -> R.color.primaryColor
                item.status.contains("محجوزة") -> android.R.color.holo_red_dark
                else -> android.R.color.darker_gray
            }
            val resolved = ContextCompat.getColor(binding.root.context, color)
            binding.roomStatus.setTextColor(resolved)
            binding.roomNumber.setTextColor(resolved)
            binding.root.setOnClickListener { listener.onRoomSelected(item) }
        }
    }

    interface RoomListener {
        fun onRoomSelected(room: RoomItem)
    }
}