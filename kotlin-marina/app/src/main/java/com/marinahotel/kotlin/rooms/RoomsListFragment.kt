package com.marinahotel.kotlin.rooms

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.FragmentRoomsListBinding

class RoomsListFragment : Fragment(), RoomsAdapter.RoomListener {
    private var _binding: FragmentRoomsListBinding? = null
    private val binding get() = _binding!!
    private val adapter = RoomsAdapter(this)
    private val allRooms = listOf(
        RoomItem("101", "شاغرة", "مفردة"),
        RoomItem("102", "محجوزة", "مزدوجة"),
        RoomItem("103", "صيانة", "جناح"),
        RoomItem("201", "شاغرة", "مزدوجة"),
        RoomItem("202", "محجوزة", "مفردة"),
        RoomItem("203", "شاغرة", "جناح")
    )

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentRoomsListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.roomsRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.roomsRecycler.adapter = adapter
        adapter.submitList(allRooms)
        binding.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val query = s?.toString().orEmpty()
                adapter.submitList(allRooms.filter { it.number.contains(query) || it.status.contains(query) })
            }
        })
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
