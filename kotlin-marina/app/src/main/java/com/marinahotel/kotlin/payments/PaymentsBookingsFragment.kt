package com.marinahotel.kotlin.payments

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.FragmentPaymentsBookingsBinding

class PaymentsBookingsFragment : Fragment(), PendingBookingsAdapter.PendingBookingListener {
    private var _binding: FragmentPaymentsBookingsBinding? = null
    private val binding get() = _binding!!
    private val adapter = PendingBookingsAdapter(this)
    private val bookings = listOf(
        PendingBookingItem("BKG-1001", "أحمد علي", "غرفة 101", "2000", "500"),
        PendingBookingItem("BKG-1006", "سارة محمد", "جناح 305", "3400", "1200"),
        PendingBookingItem("BKG-1008", "ليلى ناصر", "غرفة 212", "2800", "400")
    )

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPaymentsBookingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.bookingsRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.bookingsRecycler.adapter = adapter
        adapter.submitList(bookings)
    }

    override fun onManagePayments(item: PendingBookingItem) {
        startActivity(Intent(requireContext(), BookingPaymentActivity::class.java).apply {
            putExtra(BookingPaymentActivity.EXTRA_BOOKING_ID, item.code)
        })
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class PendingBookingItem(
    val code: String,
    val guestName: String,
    val room: String,
    val paid: String,
    val remaining: String
)
