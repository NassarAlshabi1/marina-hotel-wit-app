package com.marinahotel.kotlin.notes

import android.graphics.PorterDuff
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ItemNoteBinding

class NotesAdapter : ListAdapter<NoteItem, NotesAdapter.NoteViewHolder>(Diff) {

    object Diff : DiffUtil.ItemCallback<NoteItem>() {
        override fun areItemsTheSame(oldItem: NoteItem, newItem: NoteItem): Boolean = oldItem.title == newItem.title && oldItem.meta == newItem.meta
        override fun areContentsTheSame(oldItem: NoteItem, newItem: NoteItem): Boolean = oldItem == newItem
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): NoteViewHolder {
        val binding = ItemNoteBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return NoteViewHolder(binding)
    }

    override fun onBindViewHolder(holder: NoteViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class NoteViewHolder(private val binding: ItemNoteBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: NoteItem) {
            binding.noteTitle.text = item.title
            binding.noteBody.text = item.body
            binding.noteMeta.text = item.meta
            binding.noteStatus.text = item.priority
            val color = if (item.priority == "عالي") R.color.secondaryColor else R.color.textSecondary
            val resolved = ContextCompat.getColor(binding.root.context, color)
            binding.noteStatus.setTextColor(resolved)
            binding.noteStatus.background.setColorFilter(resolved, PorterDuff.Mode.SRC_ATOP)
        }
    }
}