package com.marinahotel.kotlin.rooms

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.GridLayoutManager
import com.marinahotel.kotlin.databinding.FragmentRoomsDashboardBinding

class RoomsDashboardFragment : Fragment(), RoomsAdapter.RoomListener {
    private var _binding: FragmentRoomsDashboardBinding? = null
    private val binding get() = _binding!!
    private val adapter = RoomsAdapter(this)
    private lateinit var viewModel: RoomsViewModel

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentRoomsDashboardBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.roomsRecycler.layoutManager = GridLayoutManager(requireContext(), 3)
        binding.roomsRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[RoomsViewModel::class.java]
        viewLifecycleOwner.lifecycleScope.launchWhenStarted {
            viewLifecycleOwner.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.rooms.collect { list -> adapter.submitList(list) }
            }
        }
        binding.floorLabel.text = ""
    }

    override fun onRoomSelected(room: RoomItem) {
        val dialog = RoomDetailsDialog.newInstance(room)
        dialog.show(parentFragmentManager, "room_details")
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
