package com.marinahotel.kotlin.presentation.dashboard

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.os.bundleOf
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.fragment.findNavController
import androidx.recyclerview.widget.GridLayoutManager
import com.google.android.material.snackbar.Snackbar
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.FragmentDashboardBinding
import com.marinahotel.kotlin.presentation.HotelViewModelFactory
import com.marinahotel.kotlin.presentation.common.hotelRepository
import kotlinx.coroutines.launch

class DashboardFragment : Fragment() {

    private var _binding: FragmentDashboardBinding? = null
    private val binding: FragmentDashboardBinding get() = _binding!!

    private val alertsAdapter = AlertsAdapter()
    private val roomsAdapter = RoomsAdapter { viewModel.onRoomSelected(it) }

    private val viewModel: DashboardViewModel by viewModels {
        HotelViewModelFactory { DashboardViewModel(hotelRepository()) }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentDashboardBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupRecyclerViews()
        observeState()
        observeEvents()
    }

    private fun setupRecyclerViews() {
        binding.alertsRecyclerView.adapter = alertsAdapter
        val spanCount = if (resources.configuration.smallestScreenWidthDp >= 600) 4 else 3
        binding.roomsRecyclerView.layoutManager = GridLayoutManager(requireContext(), spanCount)
        binding.roomsRecyclerView.adapter = roomsAdapter
    }

    private fun observeState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    alertsAdapter.submitList(state.alerts)
                    roomsAdapter.submitList(state.rooms)
                    binding.alertsEmptyView.visibility = if (state.alerts.isEmpty()) View.VISIBLE else View.GONE
                }
            }
        }
    }

    private fun observeEvents() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.events.collect { event ->
                    when (event) {
                        is DashboardViewModel.DashboardEvent.OpenNewBooking -> {
                            val args = bundleOf(
                                "roomNumber" to event.roomNumber
                            )
                            findNavController().navigate(R.id.action_dashboardFragment_to_bookingFormFragment, args)
                        }
                        is DashboardViewModel.DashboardEvent.OpenBookingDetails -> {
                            val args = bundleOf(
                                "bookingId" to event.bookingId
                            )
                            findNavController().navigate(R.id.action_dashboardFragment_to_bookingDetailsFragment, args)
                        }
                        is DashboardViewModel.DashboardEvent.ShowMessage -> {
                            Snackbar.make(binding.root, event.messageRes, Snackbar.LENGTH_SHORT).show()
                        }
                    }
                }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
