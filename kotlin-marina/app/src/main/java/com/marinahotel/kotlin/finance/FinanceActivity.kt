package com.marinahotel.kotlin.finance

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.viewpager2.adapter.FragmentStateAdapter
import com.google.android.material.tabs.TabLayoutMediator
import com.marinahotel.kotlin.databinding.ActivityFinanceBinding
import com.marinahotel.kotlin.payments.PaymentsBookingsFragment
import com.marinahotel.kotlin.payments.PaymentsOverviewFragment
import com.marinahotel.kotlin.payments.PaymentsTransactionsFragment

class FinanceActivity : AppCompatActivity() {
    private lateinit var binding: ActivityFinanceBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityFinanceBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        val fragments = listOf(
            PaymentsOverviewFragment(),
            PaymentsTransactionsFragment(),
            PaymentsBookingsFragment()
        )
        val titles = listOf("نظرة عامة", "الحركات", "الحجوزات")
        binding.viewPager.adapter = object : FragmentStateAdapter(this) {
            override fun getItemCount(): Int = fragments.size
            override fun createFragment(position: Int): Fragment = fragments[position]
        }
        TabLayoutMediator(binding.tabLayout, binding.viewPager) { tab, position ->
            tab.text = titles[position]
        }.attach()
    }
}
