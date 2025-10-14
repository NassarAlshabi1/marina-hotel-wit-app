package com.marinahotel.kotlin.rooms

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.GridLayoutManager
import com.marinahotel.kotlin.R
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
        val message = buildString {
            append(getString(R.string.label_room_type))
            append(": ")
            append(room.type)
            append('\n')
            append(getString(R.string.label_room_status))
            append(": ")
            append(room.status)
            append('\n')
            append(getString(R.string.label_room_price))
            append(": ")
            append(getString(R.string.room_price_format, room.price))
        }
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.room_number_format, room.number))
            .setMessage(message)
            .setPositiveButton(R.string.action_edit_room) { _, _ ->
                startActivity(Intent(requireContext(), RoomAddActivity::class.java).apply {
                    putExtra(RoomAddActivity.EXTRA_ROOM_NUMBER, room.number)
                })
            }
            .setNegativeButton(R.string.action_cancel, null)
            .show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
