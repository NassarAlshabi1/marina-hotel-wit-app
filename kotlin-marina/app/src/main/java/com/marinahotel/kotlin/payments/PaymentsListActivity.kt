package com.marinahotel.kotlin.payments

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.ActivityPaymentsListBinding

class PaymentsListActivity : AppCompatActivity() {
    private lateinit var binding: ActivityPaymentsListBinding
    private val adapter = RecentPaymentsAdapter()
    private lateinit var viewModel: PaymentsViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPaymentsListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.paymentsRecycler.layoutManager = LinearLayoutManager(this)
        binding.paymentsRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[PaymentsViewModel::class.java]
        lifecycleScope.launchWhenStarted {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.recentPayments.collect { list -> adapter.submitList(list) }
            }
        }
    }
}
