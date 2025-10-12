package com.marinahotel.kotlin.payments

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.viewpager2.adapter.FragmentStateAdapter
import com.google.android.material.tabs.TabLayoutMediator
import com.marinahotel.kotlin.databinding.ActivityPaymentsMainBinding

class PaymentsMainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityPaymentsMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPaymentsMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        val fragments = listOf(
            PaymentsOverviewFragment(),
            PaymentsTransactionsFragment(),
            PaymentsBookingsFragment()
        )
        val titles = listOf("نظرة عامة", "المعاملات", "الحجوزات النشطة")
        binding.viewPager.adapter = object : FragmentStateAdapter(this) {
            override fun getItemCount(): Int = fragments.size
            override fun createFragment(position: Int): Fragment = fragments[position]
        }
        TabLayoutMediator(binding.tabLayout, binding.viewPager) { tab, position ->
            tab.text = titles[position]
        }.attach()
    }
}
