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
import com.google.android.material.datepicker.MaterialDatePicker
import com.google.android.material.snackbar.Snackbar
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.FragmentBookingFormBinding
import com.marinahotel.kotlin.presentation.HotelViewModelFactory
import com.marinahotel.kotlin.presentation.common.hotelRepository
import kotlinx.coroutines.launch

class BookingFormFragment : Fragment() {

    private var _binding: FragmentBookingFormBinding? = null
    private val binding: FragmentBookingFormBinding get() = _binding!!

    private val bookingId: Int by lazy { arguments?.getInt("bookingId") ?: 0 }
    private val preselectedRoom: String by lazy { arguments?.getString("roomNumber").orEmpty() }

    private val viewModel: BookingFormViewModel by viewModels {
        HotelViewModelFactory { BookingFormViewModel(hotelRepository(), bookingId, preselectedRoom) }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentBookingFormBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupListeners()
        observeState()
        observeEvents()
    }

    private fun setupListeners() {
        binding.guestNameInput.doOnTextChanged { text, _, _, _ -> viewModel.onGuestNameChanged(text?.toString().orEmpty()) }
        binding.guestPhoneInput.doOnTextChanged { text, _, _, _ -> viewModel.onGuestPhoneChanged(text?.toString().orEmpty()) }
        binding.idTypeInput.doOnTextChanged { text, _, _, _ -> viewModel.onIdTypeChanged(text?.toString().orEmpty()) }
        binding.idNumberInput.doOnTextChanged { text, _, _, _ -> viewModel.onIdNumberChanged(text?.toString().orEmpty()) }
        binding.nationalityInput.doOnTextChanged { text, _, _, _ -> viewModel.onNationalityChanged(text?.toString().orEmpty()) }
        binding.roomInput.doOnTextChanged { text, _, _, _ -> viewModel.onRoomChanged(text?.toString().orEmpty()) }
        binding.notesInput.doOnTextChanged { text, _, _, _ -> viewModel.onNotesChanged(text?.toString().orEmpty()) }

        binding.checkinInput.setOnClickListener { showDatePicker(isCheckin = true) }
        binding.checkoutInput.setOnClickListener { showDatePicker(isCheckin = false) }
        binding.saveButton.setOnClickListener { viewModel.saveBooking() }
    }

    private fun observeState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { state ->
                    if (binding.guestNameInput.text?.toString() != state.guestName) {
                        binding.guestNameInput.setText(state.guestName)
                    }
                    if (binding.guestPhoneInput.text?.toString() != state.guestPhone) {
                        binding.guestPhoneInput.setText(state.guestPhone)
                    }
                    if (binding.idTypeInput.text?.toString() != state.idType) {
                        binding.idTypeInput.setText(state.idType, false)
                    }
                    if (binding.idNumberInput.text?.toString() != state.idNumber) {
                        binding.idNumberInput.setText(state.idNumber)
                    }
                    if (binding.nationalityInput.text?.toString() != state.nationality) {
                        binding.nationalityInput.setText(state.nationality, false)
                    }
                    if (binding.roomInput.text?.toString() != state.roomNumber) {
                        binding.roomInput.setText(state.roomNumber, false)
                    }
                    binding.checkinInput.setText(viewModel.formatDate(state.checkinDate))
                    binding.checkoutInput.setText(viewModel.formatDate(state.checkoutDate))

                    binding.roomInput.setSimpleItems(state.roomOptions.toTypedArray())
                    binding.idTypeInput.setSimpleItems(BookingFormViewModel.DEFAULT_ID_TYPES.toTypedArray())
                    binding.nationalityInput.setSimpleItems(BookingFormViewModel.DEFAULT_NATIONALITIES.toTypedArray())

                    binding.saveButton.isEnabled = !state.isSaving
                    binding.saveButton.text = getString(if (state.isUpdate) R.string.action_update_booking else R.string.action_save_booking)
                }
            }
        }
    }

    private fun observeEvents() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.events.collect { event ->
                    when (event) {
                        is BookingFormViewModel.BookingFormEvent.ShowMessage -> {
                            Snackbar.make(binding.root, event.messageRes, Snackbar.LENGTH_SHORT).show()
                        }
                        is BookingFormViewModel.BookingFormEvent.BookingSaved -> {
                            val args = Bundle().apply { putInt("bookingId", event.bookingId) }
                            findNavController().navigate(R.id.action_bookingFormFragment_to_bookingDetailsFragment, args)
                        }
                    }
                }
            }
        }
    }

    private fun showDatePicker(isCheckin: Boolean) {
        val currentState = viewModel.state.value
        val selection = if (isCheckin) currentState.checkinDate else currentState.checkoutDate
        val picker = MaterialDatePicker.Builder.datePicker()
            .setTitleText(if (isCheckin) R.string.hint_checkin_date else R.string.hint_checkout_date)
            .setSelection(selection ?: System.currentTimeMillis())
            .build()
        picker.addOnPositiveButtonClickListener { timestamp ->
            if (isCheckin) {
                viewModel.onCheckinSelected(timestamp)
            } else {
                viewModel.onCheckoutSelected(timestamp)
            }
        }
        picker.addOnNegativeButtonClickListener {
            if (!isCheckin) viewModel.onCheckoutSelected(null)
        }
        picker.show(childFragmentManager, if (isCheckin) "checkin_picker" else "checkout_picker")
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
