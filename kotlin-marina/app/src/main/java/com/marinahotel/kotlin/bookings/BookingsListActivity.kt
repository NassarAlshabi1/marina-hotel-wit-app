package com.marinahotel.kotlin.bookings

import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
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
    private val allBookings = mutableListOf<BookingUi>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookingsListBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.bookingsRecycler.layoutManager = LinearLayoutManager(this)
        binding.bookingsRecycler.adapter = adapter
        binding.filterChipGroup.isSingleSelection = false
        initSampleData()
        binding.addBookingFab.setOnClickListener {
            startActivity(Intent(this, BookingEditActivity::class.java))
        }
        binding.searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                applyFilters()
            }
        })
        binding.filterChipGroup.setOnCheckedStateChangeListener { _, _ -> applyFilters() }
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

    private fun initSampleData() {
        allBookings.clear()
        allBookings.addAll(
            listOf(
                BookingUi("BKG-1001", "أحمد علي", "101", "نشط", "10 يناير", "12 يناير"),
                BookingUi("BKG-1002", "سارة محمد", "205", "مؤكد", "8 يناير", "11 يناير"),
                BookingUi("BKG-1003", "يوسف خالد", "303", "ملغى", "1 يناير", "3 يناير"),
                BookingUi("BKG-1004", "ليلى عبد الله", "407", "مكتمل", "2 يناير", "6 يناير"),
                BookingUi("BKG-1005", "مها ناصر", "110", "نشط", "11 يناير", "13 يناير")
            )
        )
        applyFilters()
    }

    private fun applyFilters() {
        val query = binding.searchInput.text?.toString().orEmpty()
        val activeChips = binding.filterChipGroup.checkedChipIds.mapNotNull { id ->
            binding.filterChipGroup.findViewById<Chip>(id)?.text?.toString()
        }
        val filtered = allBookings.filter { booking ->
            val matchesQuery = query.isBlank() || booking.guestName.contains(query) || booking.code.contains(query)
            val matchesStatus = if (activeChips.isEmpty()) true else activeChips.any { chip ->
                booking.status.contains(chip)
            }
            matchesQuery && matchesStatus
        }
        adapter.submitList(filtered)
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
