package com.marinahotel.kotlin.bookings

import android.app.DatePickerDialog
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.databinding.ActivityBookingEditBinding
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.Calendar
import java.util.Locale
import kotlinx.coroutines.launch

class BookingEditActivity : AppCompatActivity() {
    private lateinit var binding: ActivityBookingEditBinding
    private lateinit var viewModel: BookingViewModel
    private var dateTarget = DateTarget.ARRIVAL
    private var currentBookingId: Int = 0
    private var currentBooking: BookingEntity? = null

    private val locale = Locale("ar")
    private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy", locale)
    private val timestampFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm", locale)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookingEditBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }

        viewModel = ViewModelProvider(this)[BookingViewModel::class.java]

        observeBookingUpdates()
        setupDropdowns()
        setupDatePickers()

        val bookingIdExtra = intent.getStringExtra(EXTRA_BOOKING_ID)
        bookingIdExtra?.toIntOrNull()?.let {
            currentBookingId = it
            viewModel.loadBooking(it)
        }

        binding.saveButton.setOnClickListener {
            val entity = buildBookingEntity() ?: return@setOnClickListener
            lifecycleScope.launch {
                val savedId = viewModel.saveBooking(entity)
                currentBookingId = savedId
                Toast.makeText(this@BookingEditActivity, "تم حفظ الحجز", Toast.LENGTH_SHORT).show()
                finish()
            }
        }
    }

    private fun observeBookingUpdates() {
        lifecycleScope.launch {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.booking.collect { entity ->
                    entity?.let {
                        currentBookingId = it.bookingId
                        currentBooking = it
                        populateForm(it)
                    }
                }
            }
        }
    }

    private fun populateForm(entity: BookingEntity) {
        binding.guestNameInput.setText(entity.guestName)
        binding.phoneInput.setText(entity.guestPhone)
        binding.idTypeInput.setText(entity.guestIdType, false)
        binding.idNumberInput.setText(entity.guestIdNumber)
        binding.emailInput.setText(entity.guestEmail ?: "")
        binding.addressInput.setText(entity.guestAddress ?: "")
        binding.roomNumberInput.setText(entity.roomNumber)
        binding.statusInput.setText(entity.status, false)
        binding.arrivalInput.setText(entity.checkinDate)
        binding.departureInput.setText(entity.checkoutDate ?: "")
        binding.nightsInput.setText(entity.expectedNights.toString())
        binding.notesInput.setText(entity.notes ?: "")
        updateNightCount()
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
            val selectedDate = LocalDate.of(year, month + 1, dayOfMonth)
            val formatted = selectedDate.format(dateFormatter)
            when (dateTarget) {
                DateTarget.ARRIVAL -> {
                    binding.arrivalLayout.error = null
                    binding.arrivalInput.setText(formatted)
                }
                DateTarget.DEPARTURE -> {
                    binding.departureLayout.error = null
                    binding.departureInput.setText(formatted)
                }
            }
            updateNightCount()
        }

        binding.arrivalInput.setOnClickListener {
            dateTarget = DateTarget.ARRIVAL
            showDatePicker(listener, binding.arrivalInput.text?.toString())
        }
        binding.departureInput.setOnClickListener {
            dateTarget = DateTarget.DEPARTURE
            showDatePicker(listener, binding.departureInput.text?.toString())
        }
        binding.arrivalInput.setOnFocusChangeListener { v, hasFocus ->
            if (hasFocus) {
                dateTarget = DateTarget.ARRIVAL
                showDatePicker(listener, binding.arrivalInput.text?.toString())
                v.clearFocus()
            }
        }
        binding.departureInput.setOnFocusChangeListener { v, hasFocus ->
            if (hasFocus) {
                dateTarget = DateTarget.DEPARTURE
                showDatePicker(listener, binding.departureInput.text?.toString())
                v.clearFocus()
            }
        }
        binding.arrivalLayout.setEndIconOnClickListener {
            dateTarget = DateTarget.ARRIVAL
            showDatePicker(listener, binding.arrivalInput.text?.toString())
        }
        binding.departureLayout.setEndIconOnClickListener {
            dateTarget = DateTarget.DEPARTURE
            showDatePicker(listener, binding.departureInput.text?.toString())
        }
    }

    private fun showDatePicker(listener: DatePickerDialog.OnDateSetListener, currentValue: String?) {
        val calendar = Calendar.getInstance()
        parseDateOrNull(currentValue)?.let { date ->
            calendar.set(Calendar.YEAR, date.year)
            calendar.set(Calendar.MONTH, date.monthValue - 1)
            calendar.set(Calendar.DAY_OF_MONTH, date.dayOfMonth)
        }
        DatePickerDialog(
            this,
            listener,
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH),
            calendar.get(Calendar.DAY_OF_MONTH)
        ).show()
    }

    private fun parseDateOrNull(value: String?): LocalDate? {
        if (value.isNullOrBlank()) return null
        return try {
            LocalDate.parse(value, dateFormatter)
        } catch (ex: DateTimeParseException) {
            null
        }
    }

    private fun updateNightCount() {
        val arrival = parseDateOrNull(binding.arrivalInput.text?.toString())
        val departure = parseDateOrNull(binding.departureInput.text?.toString())
        if (arrival != null && departure != null) {
            val nights = ChronoUnit.DAYS.between(arrival, departure).toInt()
            if (nights > 0) {
                binding.nightsInput.setText(nights.toString())
            }
        }
    }

    private fun buildBookingEntity(): BookingEntity? {
        var valid = true

        val guestName = binding.guestNameInput.text?.toString()?.trim().orEmpty()
        if (guestName.isEmpty()) {
            binding.guestNameLayout.error = "يرجى إدخال اسم النزيل"
            valid = false
        } else {
            binding.guestNameLayout.error = null
        }

        val phone = binding.phoneInput.text?.toString()?.trim().orEmpty()
        if (phone.isEmpty()) {
            binding.phoneLayout.error = "يرجى إدخال رقم الهاتف"
            valid = false
        } else {
            binding.phoneLayout.error = null
        }

        val roomNumber = binding.roomNumberInput.text?.toString()?.trim().orEmpty()
        if (roomNumber.isEmpty()) {
            binding.roomNumberLayout.error = "يرجى إدخال رقم الغرفة"
            valid = false
        } else {
            binding.roomNumberLayout.error = null
        }

        val arrivalText = binding.arrivalInput.text?.toString()?.trim().orEmpty()
        val arrivalDate = parseDateOrNull(arrivalText)
        if (arrivalDate == null) {
            binding.arrivalLayout.error = "صيغة التاريخ غير صحيحة"
            valid = false
        } else {
            binding.arrivalLayout.error = null
        }

        val departureText = binding.departureInput.text?.toString()?.trim().orEmpty()
        val departureDate = parseDateOrNull(departureText)
        if (departureText.isNotEmpty() && departureDate == null) {
            binding.departureLayout.error = "صيغة التاريخ غير صحيحة"
            valid = false
        } else if (arrivalDate != null && departureDate != null && departureDate.isBefore(arrivalDate)) {
            binding.departureLayout.error = "تاريخ المغادرة يجب أن يكون بعد الوصول"
            valid = false
        } else {
            binding.departureLayout.error = null
        }

        if (!valid || arrivalDate == null) {
            return null
        }

        val nightsInputValue = binding.nightsInput.text?.toString()?.trim()
        val nightsFromInput = nightsInputValue?.toIntOrNull()?.takeIf { it > 0 }
        val computedNights = nightsFromInput
            ?: departureDate?.let { ChronoUnit.DAYS.between(arrivalDate, it).toInt() }?.takeIf { it > 0 }
            ?: 1

        val now = LocalDateTime.now()
        val timestamp = timestampFormatter.format(now)
        val existing = currentBooking
        val createdAt = existing?.createdAt ?: timestamp
        val guestCreatedAt = existing?.guestCreatedAt ?: timestamp
        val checkoutDateString = departureDate?.format(dateFormatter)
        val status = binding.statusInput.text?.toString()?.trim().takeUnless { it.isNullOrBlank() } ?: "نشط"
        val idType = binding.idTypeInput.text?.toString()?.trim().takeUnless { it.isNullOrBlank() } ?: "هوية وطنية"

        return BookingEntity(
            bookingId = existing?.bookingId ?: currentBookingId,
            guestId = existing?.guestId,
            guestName = guestName,
            guestIdType = idType,
            guestIdNumber = binding.idNumberInput.text?.toString()?.trim().orEmpty(),
            guestIdIssueDate = existing?.guestIdIssueDate,
            guestIdIssuePlace = existing?.guestIdIssuePlace,
            guestPhone = phone,
            guestNationality = existing?.guestNationality,
            guestEmail = binding.emailInput.text?.toString()?.trim().takeUnless { it.isNullOrBlank() },
            guestAddress = binding.addressInput.text?.toString()?.trim().takeUnless { it.isNullOrBlank() },
            guestCreatedAt = guestCreatedAt,
            roomNumber = roomNumber,
            checkinDate = arrivalText,
            checkoutDate = checkoutDateString,
            status = status,
            notes = binding.notesInput.text?.toString()?.trim().takeUnless { it.isNullOrBlank() },
            createdAt = createdAt,
            expectedNights = computedNights,
            actualCheckout = checkoutDateString,
            calculatedNights = computedNights,
            lastCalculation = timestamp
        )
    }

    companion object {
        const val EXTRA_BOOKING_ID = "extra_booking_id"
    }

    private enum class DateTarget {
        ARRIVAL,
        DEPARTURE
    }
}
