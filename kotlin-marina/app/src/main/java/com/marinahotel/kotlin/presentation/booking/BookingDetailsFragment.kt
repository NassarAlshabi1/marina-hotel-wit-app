package com.marinahotel.kotlin.presentation.booking

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import androidx.core.widget.doOnTextChanged
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.snackbar.Snackbar
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.FragmentBookingDetailsBinding
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.presentation.HotelViewModelFactory
import com.marinahotel.kotlin.presentation.common.hotelRepository
import kotlinx.coroutines.launch

class BookingDetailsFragment : Fragment() {

    private var _binding: FragmentBookingDetailsBinding? = null
    private val binding: FragmentBookingDetailsBinding get() = _binding!!

    private val bookingId: Int by lazy { arguments?.getInt("bookingId") ?: 0 }

    private val viewModel: BookingDetailsViewModel by viewModels {
        HotelViewModelFactory { BookingDetailsViewModel(hotelRepository(), bookingId) }
    }

    private val paymentsAdapter = BookingPaymentsAdapter { timestamp -> viewModel.formatDateTime(timestamp) }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentBookingDetailsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupRecyclerView()
        setupInputs()
        observeState()
        observeEvents()
    }

    private fun setupRecyclerView() {
        binding.paymentsRecyclerView.adapter = paymentsAdapter
    }

    private fun setupInputs() {
        binding.paymentAmountInput.doOnTextChanged { text, _, _, _ ->
            viewModel.onPaymentAmountChanged(text?.toString().orEmpty())
        }
        binding.paymentMethodInput.setSimpleItems(resources.getStringArray(R.array.payment_methods_array))
        binding.paymentMethodInput.doOnTextChanged { text, _, _, _ ->
            viewModel.onPaymentMethodChanged(text?.toString().orEmpty())
        }
        binding.paymentNotesInput.doOnTextChanged { text, _, _, _ ->
            viewModel.onPaymentNotesChanged(text?.toString().orEmpty())
        }
        binding.addPaymentButton.setOnClickListener { viewModel.onAddPaymentClicked() }
        binding.checkoutButton.setOnClickListener { viewModel.onCheckoutClicked() }
    }

    private fun observeState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.state.collect { state ->
                    renderState(state)
                }
            }
        }
    }

    private fun renderState(state: BookingDetailsViewModel.BookingDetailsUiState) {
        val context = requireContext()

        binding.guestNameText.text = state.guestName
        val phone = if (state.guestPhone.isNotBlank()) state.guestPhone else getString(R.string.label_not_set)
        binding.guestPhoneText.text = getString(R.string.label_guest_phone_value, phone)
        val idNumber = state.guestIdNumber.ifBlank { getString(R.string.label_not_set) }
        val idType = state.guestIdType.ifBlank { getString(R.string.label_not_set) }
        binding.guestIdText.text = getString(R.string.label_guest_id_value, idNumber, idType)
        val nationality = state.guestNationality?.takeIf { it.isNotBlank() } ?: getString(R.string.label_not_set)
        binding.guestNationalityText.text = getString(R.string.label_guest_nationality_value, nationality)

        val roomNumber = state.roomNumber.ifBlank { getString(R.string.label_not_set) }
        binding.roomNumberText.text = getString(R.string.label_room_number, roomNumber)
        val roomType = state.roomType.ifBlank { getString(R.string.label_not_set) }
        binding.roomTypeText.text = getString(R.string.label_room_type_value, roomType)
        val statusLabelRes = when (state.status) {
            BookingStatus.RESERVED -> R.string.label_booking_status_reserved
            BookingStatus.COMPLETED -> R.string.label_booking_status_completed
            BookingStatus.CANCELLED -> R.string.label_booking_status_cancelled
        }
        binding.bookingStatusText.text = getString(R.string.label_booking_status_value, getString(statusLabelRes))

        binding.checkinDateText.text = getString(R.string.label_checkin, viewModel.formatDate(state.checkinDate))
        val checkoutText = state.checkoutDate?.let { viewModel.formatDate(it) } ?: getString(R.string.label_not_set)
        binding.checkoutDateText.text = getString(R.string.label_checkout, checkoutText)
        binding.nightsText.text = getString(R.string.label_nights, state.nights)

        val totalFormatted = getString(R.string.label_amount_format, state.totalAmount)
        val paidFormatted = getString(R.string.label_amount_format, state.paidAmount)
        val remainingFormatted = getString(R.string.label_amount_format, state.remainingAmount)
        binding.totalAmountText.text = getString(R.string.label_value_format, getString(R.string.label_total_amount), totalFormatted)
        binding.paidAmountText.text = getString(R.string.label_value_format, getString(R.string.label_paid_amount), paidFormatted)
        binding.remainingAmountText.text = getString(R.string.label_value_format, getString(R.string.label_remaining_amount), remainingFormatted)
        val remainingColor = if (state.remainingAmount > 0) R.color.color_error else R.color.color_success
        binding.remainingAmountText.setTextColor(ContextCompat.getColor(context, remainingColor))

        binding.notesText.text = state.notes?.takeIf { it.isNotBlank() } ?: getString(R.string.label_no_notes)

        if (binding.paymentAmountInput.text?.toString() != state.paymentAmountInput) {
            binding.paymentAmountInput.setText(state.paymentAmountInput)
            binding.paymentAmountInput.setSelection(state.paymentAmountInput.length)
        }
        if (binding.paymentMethodInput.text?.toString() != state.paymentMethodInput) {
            binding.paymentMethodInput.setText(state.paymentMethodInput, false)
        }
        if (binding.paymentNotesInput.text?.toString() != state.paymentNotesInput) {
            binding.paymentNotesInput.setText(state.paymentNotesInput)
            binding.paymentNotesInput.setSelection(state.paymentNotesInput.length)
        }

        binding.paymentAmountLayout.error = state.paymentAmountError?.let { getString(it) }
        binding.paymentMethodLayout.error = state.paymentMethodError?.let { getString(it) }

        binding.addPaymentButton.isEnabled = !state.isAddingPayment
        binding.checkoutButton.isEnabled = state.isCheckoutEnabled && !state.isCheckoutInProgress
        binding.checkoutButton.alpha = if (binding.checkoutButton.isEnabled) 1f else 0.6f

        paymentsAdapter.submitList(state.payments)
        binding.paymentsEmptyText.isVisible = state.payments.isEmpty()
        binding.paymentsRecyclerView.isVisible = state.payments.isNotEmpty()
    }

    private fun observeEvents() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.events.collect { event ->
                    when (event) {
                        is BookingDetailsViewModel.BookingDetailsEvent.ShowMessage -> {
                            Snackbar.make(binding.root, event.messageRes, Snackbar.LENGTH_SHORT).show()
                        }
                        BookingDetailsViewModel.BookingDetailsEvent.ConfirmCheckout -> {
                            showCheckoutConfirmation()
                        }
                    }
                }
            }
        }
    }

    private fun showCheckoutConfirmation() {
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.dialog_checkout_title)
            .setMessage(R.string.dialog_checkout_message)
            .setPositiveButton(R.string.action_confirm) { dialog, _ ->
                viewModel.onCheckoutConfirmed()
                dialog.dismiss()
            }
            .setNegativeButton(R.string.action_cancel) { dialog, _ -> dialog.dismiss() }
            .show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
