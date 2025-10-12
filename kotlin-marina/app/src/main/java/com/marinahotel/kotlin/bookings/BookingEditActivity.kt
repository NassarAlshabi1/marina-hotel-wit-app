package com.marinahotel.kotlin.bookings

import android.app.DatePickerDialog
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.marinahotel.kotlin.databinding.ActivityBookingEditBinding
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class BookingEditActivity : AppCompatActivity() {
    private lateinit var binding: ActivityBookingEditBinding
    private val calendar = Calendar.getInstance()
    private var dateTarget = DateTarget.ARRIVAL

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookingEditBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        setupDropdowns()
        setupDatePickers()
        val bookingId = intent.getStringExtra(EXTRA_BOOKING_ID)
        if (!bookingId.isNullOrEmpty()) {
            binding.guestNameInput.setText("أحمد علي")
            binding.roomNumberInput.setText("101")
            binding.notesInput.setText("تم الحجز عبر التطبيق")
        }
        binding.saveButton.setOnClickListener {
            Toast.makeText(this, "تم حفظ الحجز", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun setupDropdowns() {
        val idTypes = listOf("هوية وطنية", "جواز سفر", "رخصة")
        val status = listOf("نشط", "مؤكد", "مكتمل", "ملغى")
        val idAdapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, idTypes)
        val statusAdapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, status)
        binding.idTypeInput.setAdapter(idAdapter)
        binding.statusInput.setAdapter(statusAdapter)
    }

    private fun setupDatePickers() {
        val listener = DatePickerDialog.OnDateSetListener { _, year, month, dayOfMonth ->
            calendar.set(Calendar.YEAR, year)
            calendar.set(Calendar.MONTH, month)
            calendar.set(Calendar.DAY_OF_MONTH, dayOfMonth)
            val formatter = SimpleDateFormat("dd MMMM", Locale("ar"))
            val formatted = formatter.format(calendar.time)
            when (dateTarget) {
                DateTarget.ARRIVAL -> binding.arrivalInput.setText(formatted)
                DateTarget.DEPARTURE -> binding.departureInput.setText(formatted)
            }
        }
        binding.arrivalInput.setOnFocusChangeListener { v, hasFocus ->
            if (hasFocus) {
                dateTarget = DateTarget.ARRIVAL
                showDatePicker(listener)
                v.clearFocus()
            }
        }
        binding.departureInput.setOnFocusChangeListener { v, hasFocus ->
            if (hasFocus) {
                dateTarget = DateTarget.DEPARTURE
                showDatePicker(listener)
                v.clearFocus()
            }
        }
        binding.arrivalLayout.setEndIconOnClickListener {
            dateTarget = DateTarget.ARRIVAL
            showDatePicker(listener)
        }
        binding.departureLayout.setEndIconOnClickListener {
            dateTarget = DateTarget.DEPARTURE
            showDatePicker(listener)
        }
    }

    private fun showDatePicker(listener: DatePickerDialog.OnDateSetListener) {
        DatePickerDialog(
            this,
            listener,
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH),
            calendar.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    companion object {
        const val EXTRA_BOOKING_ID = "extra_booking_id"
    }

    enum class DateTarget {
        ARRIVAL,
        DEPARTURE
    }
}
