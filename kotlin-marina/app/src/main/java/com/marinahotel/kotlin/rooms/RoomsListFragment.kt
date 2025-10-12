package com.marinahotel.kotlin.rooms

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.FragmentRoomsListBinding

class RoomsListFragment : Fragment(), RoomsAdapter.RoomListener {
    private var _binding: FragmentRoomsListBinding? = null
    private val binding get() = _binding!!
    private val adapter = RoomsAdapter(this)
    private lateinit var viewModel: RoomsViewModel

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentRoomsListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.roomsRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.roomsRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[RoomsViewModel::class.java]
        observeRooms()
        binding.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val query = s?.toString().orEmpty()
                viewModel.setQuery(query)
            }
        })
    }

    private fun observeRooms() {
        viewLifecycleOwner.lifecycleScope.launchWhenStarted {
            viewLifecycleOwner.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.rooms.collect { list -> adapter.submitList(list) }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    override fun onRoomSelected(room: RoomItem) {
        val dialog = RoomDetailsDialog.newInstance(room)
        dialog.show(parentFragmentManager, "room_details")
    }
}
