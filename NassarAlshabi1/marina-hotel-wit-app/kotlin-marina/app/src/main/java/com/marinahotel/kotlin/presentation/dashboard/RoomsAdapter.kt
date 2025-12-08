package com.marinahotel.kotlin.presentation.dashboard

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemDashboardRoomBinding
import com.marinahotel.kotlin.domain.model.RoomStatus

class RoomsAdapter(
    private val onRoomSelected: (RoomUiModel) -> Unit
) : ListAdapter<RoomUiModel, RoomsAdapter.RoomViewHolder>(RoomDiffCallback) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RoomViewHolder {
        val binding = ItemDashboardRoomBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return RoomViewHolder(binding, onRoomSelected)
    }

    override fun onBindViewHolder(holder: RoomViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    class RoomViewHolder(
        private val binding: ItemDashboardRoomBinding,
        private val onRoomSelected: (RoomUiModel) -> Unit
    ) : RecyclerView.ViewHolder(binding.root) {

        fun bind(item: RoomUiModel) {
            val context = binding.root.context
            val backgroundColor = ContextCompat.getColor(context, item.backgroundColorRes)
            val strokeColor = ContextCompat.getColor(context, item.strokeColorRes)
            binding.root.setCardBackgroundColor(backgroundColor)
            binding.root.strokeColor = strokeColor

            binding.roomNumber.text = item.roomNumber

            binding.roomFloor.text = context.getString(R.string.label_room_floor, item.floor)

            val statusText = when (item.status) {
                RoomStatus.RESERVED -> item.occupantName?.let {
                    context.getString(R.string.status_booked_with_guest, it)
                } ?: context.getString(item.statusLabelRes)
                else -> context.getString(item.statusLabelRes)
            }
            binding.roomStatus.text = statusText

            binding.root.setOnClickListener { onRoomSelected(item) }
        }
    }

    private object RoomDiffCallback : DiffUtil.ItemCallback<RoomUiModel>() {
        override fun areItemsTheSame(oldItem: RoomUiModel, newItem: RoomUiModel): Boolean = oldItem.roomNumber == newItem.roomNumber
        override fun areContentsTheSame(oldItem: RoomUiModel, newItem: RoomUiModel): Boolean = oldItem == newItem
    }
}
