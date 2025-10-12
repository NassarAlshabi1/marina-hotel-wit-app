package com.marinahotel.kotlin.reports

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.marinahotel.kotlin.databinding.ActivityReportsBinding

class ReportsActivity : AppCompatActivity() {
    private lateinit var binding: ActivityReportsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityReportsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
    }
}
