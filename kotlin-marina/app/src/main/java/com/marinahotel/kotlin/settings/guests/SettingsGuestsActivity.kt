package com.marinahotel.kotlin.settings.guests

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.ActivitySettingsGuestsBinding

class SettingsGuestsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsGuestsBinding
    private val adapter = GuestsAdapter()
    private val guests = listOf(
        GuestItem("أحمد علي", "0501234567", 5),
        GuestItem("نورة السبيعي", "0509876543", 2),
        GuestItem("يوسف الغامدي", "0543219876", 4)
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsGuestsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.guestsRecycler.layoutManager = LinearLayoutManager(this)
        binding.guestsRecycler.adapter = adapter
        adapter.submitList(guests)
        binding.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val query = s?.toString().orEmpty()
                adapter.submitList(guests.filter { it.name.contains(query) || it.contact.contains(query) })
            }
        })
    }
}

data class GuestItem(
    val name: String,
    val contact: String,
    val visits: Int
)
