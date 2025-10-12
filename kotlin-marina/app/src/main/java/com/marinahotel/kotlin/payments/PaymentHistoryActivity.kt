package com.marinahotel.kotlin.payments

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.chip.Chip
import com.marinahotel.kotlin.databinding.ActivityPaymentHistoryBinding

class PaymentHistoryActivity : AppCompatActivity() {
    private lateinit var binding: ActivityPaymentHistoryBinding
    private val adapter = BookingPaymentAdapter()
    private val history = listOf(
        PaymentTransaction("دفعة نقدية", "إيراد", "10 يناير", "1200 ر.س"),
        PaymentTransaction("دفعة بالبطاقة", "إيراد", "9 يناير", "800 ر.س"),
        PaymentTransaction("إرجاع", "استرجاع", "8 يناير", "300 ر.س")
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPaymentHistoryBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.bookingLabel.text = "الحجز: ${intent.getStringExtra(EXTRA_BOOKING_ID) ?: ""}"
        binding.historyRecycler.layoutManager = LinearLayoutManager(this)
        binding.historyRecycler.adapter = adapter
        adapter.submitList(history)
        binding.typeChipGroup.setOnCheckedStateChangeListener { group, _ ->
            val checked = group.checkedChipIds.firstOrNull()?.let { id -> group.findViewById<Chip>(id)?.text?.toString() }
            val filtered = if (checked == null || checked == "الكل") history else history.filter { it.method == checked }
            adapter.submitList(filtered)
        }
    }

    companion object {
        const val EXTRA_BOOKING_ID = "extra_booking_id"
    }
}
