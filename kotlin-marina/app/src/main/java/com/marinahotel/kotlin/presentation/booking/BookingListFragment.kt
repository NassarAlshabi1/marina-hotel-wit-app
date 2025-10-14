package com.marinahotel.kotlin.presentation.booking

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.widget.doOnTextChanged
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.fragment.findNavController
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.FragmentBookingListBinding
import com.marinahotel.kotlin.presentation.HotelViewModelFactory
import com.marinahotel.kotlin.presentation.common.hotelRepository
import kotlinx.coroutines.launch

class BookingListFragment : Fragment() {

    private var _binding: FragmentBookingListBinding? = null
    private val binding: FragmentBookingListBinding get() = _binding!!

    private val adapter = BookingListAdapter { viewModel.onBookingSelected(it) }

    private val viewModel: BookingListViewModel by viewModels {
        HotelViewModelFactory { BookingListViewModel(hotelRepository()) }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentBookingListBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupRecyclerView()
        setupListeners()
        observeState()
        observeEvents()
    }

    private fun setupRecyclerView() {
        binding.bookingsRecyclerView.adapter = adapter
    }

    private fun setupListeners() {
        binding.searchInput.doOnTextChanged { text, _, _, _ ->
            viewModel.onSearchQueryChanged(text?.toString().orEmpty())
        }
        binding.addBookingFab.setOnClickListener {
            viewModel.onAddBooking()
        }
    }

    private fun observeState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    adapter.submitList(state.items)
                    val query = binding.searchInput.text?.toString().orEmpty()
                    binding.searchLayout.error = if (state.items.isEmpty() && query.isNotBlank()) {
                        getString(R.string.text_no_data)
                    } else null
                }
            }
        }
    }

    private fun observeEvents() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.events.collect { event ->
                    when (event) {
                        BookingListViewModel.BookingListEvent.CreateBooking -> {
                            findNavController().navigate(R.id.action_bookingListFragment_to_bookingFormFragment)
                        }
                        is BookingListViewModel.BookingListEvent.OpenBookingDetails -> {
                            val args = Bundle().apply {
                                putInt("bookingId", event.bookingId)
                            }
                            findNavController().navigate(R.id.action_bookingListFragment_to_bookingDetailsFragment, args)
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
