package com.marinahotel.kotlin.notes

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.FragmentNotesListBinding

class NotesListFragment : Fragment() {
    private var _binding: FragmentNotesListBinding? = null
    private val binding get() = _binding!!
    private val adapter = NotesAdapter()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentNotesListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.notesRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.notesRecycler.adapter = adapter
        val filter = arguments?.getSerializable(ARG_FILTER) as? NoteFilter ?: NoteFilter.ALL
        adapter.submitList(sampleNotes().filter { note ->
            when (filter) {
                NoteFilter.ALL -> true
                NoteFilter.UNREAD -> !note.read
                NoteFilter.HIGH -> note.priority == "عالي"
            }
        })
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun sampleNotes(): List<NoteItem> {
        return listOf(
            NoteItem("تنبيه تنظيف", "تأكد من تنظيف الغرفة 205", "وردية صباحية", "عالي", false),
            NoteItem("مخزون", "تحقق من مخزون المناشف", "وردية مسائية", "متوسط", true),
            NoteItem("صيانة", "بلاغ تسريب في الحمام", "وردية صباحية", "عالي", false)
        )
    }

    companion object {
        private const val ARG_FILTER = "arg_filter"
        fun newInstance(filter: NoteFilter): NotesListFragment {
            val fragment = NotesListFragment()
            fragment.arguments = Bundle().apply { putSerializable(ARG_FILTER, filter) }
            return fragment
        }
    }
}

enum class NoteFilter {
    ALL,
    UNREAD,
    HIGH
}

data class NoteItem(
    val title: String,
    val body: String,
    val meta: String,
    val priority: String,
    val read: Boolean
)
