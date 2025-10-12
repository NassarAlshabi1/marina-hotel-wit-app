package com.marinahotel.kotlin.payments

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.databinding.ItemChargeBinding

class ChargesAdapter : RecyclerView.Adapter<ChargesAdapter.ChargeViewHolder>() {
    private val items = mutableListOf<ChargeItem>()

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ChargeViewHolder {
        val binding = ItemChargeBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ChargeViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ChargeViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    fun submitList(data: List<ChargeItem>) {
        items.clear()
        items.addAll(data)
        notifyDataSetChanged()
    }

    inner class ChargeViewHolder(private val binding: ItemChargeBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: ChargeItem) {
            binding.chargeTitle.text = item.title
            binding.chargeDescription.text = item.description
            binding.chargeAmount.text = item.amount
            binding.chargeStatus.text = item.status
        }
    }
}
