package com.marinahotel.kotlin.payments

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.ActivityPaymentsListBinding

class PaymentsListActivity : AppCompatActivity() {
    private lateinit var binding: ActivityPaymentsListBinding
    private val adapter = RecentPaymentsAdapter()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPaymentsListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.paymentsRecycler.layoutManager = LinearLayoutManager(this)
        binding.paymentsRecycler.adapter = adapter
        adapter.submitList(
            listOf(
                PaymentItem("BKG-1001", "بطاقة", "1500 ر.س"),
                PaymentItem("BKG-1002", "نقدي", "900 ر.س"),
                PaymentItem("BKG-1003", "تحويل", "1800 ر.س"),
                PaymentItem("BKG-1004", "بطاقة", "650 ر.س")
            )
        )
    }
}
