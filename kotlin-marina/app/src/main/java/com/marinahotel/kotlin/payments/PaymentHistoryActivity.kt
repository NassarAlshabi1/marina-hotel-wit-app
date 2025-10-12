package com.marinahotel.kotlin.payments

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.chip.Chip
import com.marinahotel.kotlin.databinding.ActivityPaymentHistoryBinding

class PaymentHistoryActivity : AppCompatActivity() {
    private lateinit var binding: ActivityPaymentHistoryBinding
    private val adapter = BookingPaymentAdapter()
    private lateinit var viewModel: PaymentsViewModel
    private var all: List<PaymentTransaction> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPaymentHistoryBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.bookingLabel.text = "الحجز: ${intent.getStringExtra(EXTRA_BOOKING_ID) ?: ""}"
        binding.historyRecycler.layoutManager = LinearLayoutManager(this)
        binding.historyRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[PaymentsViewModel::class.java]
        val code = intent.getStringExtra(EXTRA_BOOKING_ID)
        val id = code?.removePrefix("BKG-")?.toIntOrNull() ?: -1
        lifecycleScope.launchWhenStarted {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.paymentsForBooking(id).collect { list ->
                    all = list
                    adapter.submitList(list)
                }
            }
        }
        binding.typeChipGroup.setOnCheckedStateChangeListener { group, _ ->
            val checked = group.checkedChipIds.firstOrNull()?.let { idC -> group.findViewById<Chip>(idC)?.text?.toString() }
            val filtered = if (checked == null || checked == "الكل") all else all.filter { it.method == checked }
            adapter.submitList(filtered)
        }
    }

    companion object {
        const val EXTRA_BOOKING_ID = "extra_booking_id"
    }
}
