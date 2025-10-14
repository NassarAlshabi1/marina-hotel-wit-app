package com.marinahotel.kotlin.payments

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.ActivityBookingCheckoutBinding

class BookingCheckoutActivity : AppCompatActivity() {
    private lateinit var binding: ActivityBookingCheckoutBinding
    private val adapter = ChargesAdapter()
    private val charges = mutableListOf(
        ChargeItem("إقامة", "ليلتان", "2500 ر.س", "مدفوع جزئياً"),
        ChargeItem("مطعم", "وجبة العشاء", "180 ر.س", "غير مدفوع"),
        ChargeItem("خدمات", "تنظيف إضافي", "120 ر.س", "مدفوع")
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookingCheckoutBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.bookingCode.text = intent.getStringExtra(EXTRA_BOOKING_ID) ?: "BKG-1001"
        binding.chargesRecycler.layoutManager = LinearLayoutManager(this)
        binding.chargesRecycler.adapter = adapter
        adapter.submitList(charges.toList())
        binding.addPaymentButton.setOnClickListener {
            startActivity(android.content.Intent(this, BookingPaymentActivity::class.java).apply {
                putExtra(BookingPaymentActivity.EXTRA_BOOKING_ID, binding.bookingCode.text.toString())
            })
        }
        binding.completeCheckoutButton.setOnClickListener {
            Toast.makeText(this, "تم إكمال تسجيل الخروج", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    companion object {
        const val EXTRA_BOOKING_ID = "extra_booking_id"
    }
}

data class ChargeItem(
    val title: String,
    val description: String,
    val amount: String,
    val status: String
)
