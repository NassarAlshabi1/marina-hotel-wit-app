package com.marinahotel.kotlin.bookings

import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import android.view.Menu
import android.view.MenuItem
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.chip.Chip
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ActivityBookingsListBinding
import com.marinahotel.kotlin.payments.BookingCheckoutActivity
import com.marinahotel.kotlin.payments.BookingPaymentActivity
import com.marinahotel.kotlin.payments.PaymentsMainActivity

class BookingsListActivity : AppCompatActivity(), BookingsAdapter.BookingListener {
    private lateinit var binding: ActivityBookingsListBinding
    private val adapter = BookingsAdapter(this)
    private lateinit var viewModel: BookingsViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookingsListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.bookingsRecycler.layoutManager = LinearLayoutManager(this)
        binding.bookingsRecycler.adapter = adapter
        binding.filterChipGroup.isSingleSelection = false
        viewModel = ViewModelProvider(this)[BookingsViewModel::class.java]
        observeBookings()
        binding.addBookingFab.setOnClickListener {
            startActivity(Intent(this, BookingEditActivity::class.java))
        }
        binding.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                viewModel.setQuery(s?.toString().orEmpty())
            }
        })
        binding.filterChipGroup.setOnCheckedStateChangeListener { group, _ ->
            val selected = group.checkedChipIds.mapNotNull { id -> group.findViewById<Chip>(id)?.text?.toString() }
            viewModel.setStatusFilters(selected.toSet())
        }
    }

    override fun onCreateOptionsMenu(menu: Menu?): Boolean {
        menuInflater.inflate(R.menu.menu_bookings, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_refresh -> {
                binding.bookingsRecycler.isVisible = false
                binding.bookingsRecycler.postDelayed({
                    binding.bookingsRecycler.isVisible = true
                }, 600)
                true
            }
            R.id.action_payments -> {
                startActivity(Intent(this, PaymentsMainActivity::class.java))
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    override fun onBookingSelected(booking: BookingUi) {
        startActivity(Intent(this, BookingEditActivity::class.java).apply {
            putExtra(BookingEditActivity.EXTRA_BOOKING_ID, booking.code)
        })
    }

    override fun onPaymentRequested(booking: BookingUi) {
        startActivity(Intent(this, BookingPaymentActivity::class.java).apply {
            putExtra(BookingPaymentActivity.EXTRA_BOOKING_ID, booking.code)
        })
    }

    override fun onCheckoutRequested(booking: BookingUi) {
        startActivity(Intent(this, BookingCheckoutActivity::class.java).apply {
            putExtra(BookingCheckoutActivity.EXTRA_BOOKING_ID, booking.code)
        })
    }

    private fun observeBookings() {
        lifecycleScope.launchWhenStarted {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.bookings.collect { list ->
                    adapter.submitList(list)
                }
            }
        }
    }
}

data class BookingUi(
    val code: String,
    val guestName: String,
    val roomNumber: String,
    val status: String,
    val arrivalDate: String,
    val departureDate: String
)
