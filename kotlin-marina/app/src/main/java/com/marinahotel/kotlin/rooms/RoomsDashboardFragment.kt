package com.marinahotel.kotlin.rooms

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.GridLayoutManager
import com.marinahotel.kotlin.databinding.FragmentRoomsDashboardBinding

class RoomsDashboardFragment : Fragment(), RoomsAdapter.RoomListener {
    private var _binding: FragmentRoomsDashboardBinding? = null
    private val binding get() = _binding!!
    private val adapter = RoomsAdapter(this)
    private val rooms = listOf(
        RoomItem("101", "شاغرة", "مفردة"),
        RoomItem("102", "محجوزة", "مزدوجة"),
        RoomItem("103", "تنظيف", "جناح"),
        RoomItem("201", "شاغرة", "مزدوجة"),
        RoomItem("202", "محجوزة", "مفردة"),
        RoomItem("203", "شاغرة", "جناح")
    )

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentRoomsDashboardBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.roomsRecycler.layoutManager = GridLayoutManager(requireContext(), 3)
        binding.roomsRecycler.adapter = adapter
        adapter.submitList(rooms)
        binding.floorLabel.text = "الطابق 1"
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
