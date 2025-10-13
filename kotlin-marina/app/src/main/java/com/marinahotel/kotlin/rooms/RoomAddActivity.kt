package com.marinahotel.kotlin.rooms

import android.os.Bundle
import android.view.inputmethod.EditorInfo
import android.widget.ArrayAdapter
import android.widget.AutoCompleteTextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.google.android.material.snackbar.Snackbar
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ActivityRoomAddBinding
import kotlinx.coroutines.launch

class RoomAddActivity : AppCompatActivity() {
    private lateinit var binding: ActivityRoomAddBinding
    private lateinit var viewModel: RoomAddViewModel
    private lateinit var roomTypes: List<String>
    private lateinit var roomStatuses: List<String>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityRoomAddBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }

        viewModel = ViewModelProvider(this)[RoomAddViewModel::class.java]
        roomTypes = resources.getStringArray(R.array.room_types_array).toList()
        roomStatuses = resources.getStringArray(R.array.room_statuses_array).toList()
        setupDropdown(binding.roomTypeInput, roomTypes)
        setupDropdown(binding.statusInput, roomStatuses)

        binding.saveButton.setOnClickListener { submitForm() }
        binding.cancelButton.setOnClickListener { finish() }
        binding.statusInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                submitForm()
                true
            } else {
                false
            }
        }

        lifecycleScope.launch {
            viewModel.state.collect { state ->
                binding.progressIndicator.isVisible = state.isSaving
                binding.saveButton.isEnabled = !state.isSaving
                binding.cancelButton.isEnabled = !state.isSaving
                if (state.error != null) {
                    Snackbar.make(binding.root, state.error, Snackbar.LENGTH_LONG).show()
                    viewModel.clearError()
                }
                if (state.success) {
                    Toast.makeText(this@RoomAddActivity, getString(R.string.message_room_saved), Toast.LENGTH_SHORT).show()
                    viewModel.resetState()
                    setResult(RESULT_OK)
                    finish()
                }
            }
        }
    }

    private fun setupDropdown(view: AutoCompleteTextView, items: List<String>) {
        val adapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, items)
        view.setAdapter(adapter)
        view.keyListener = null
        view.setOnClickListener { view.showDropDown() }
        view.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                view.showDropDown()
            }
        }
    }

    private fun submitForm() {
        val number = binding.roomNumberInput.text?.toString()?.trim().orEmpty()
        val type = binding.roomTypeInput.text?.toString()?.trim().orEmpty()
        val priceText = binding.priceInput.text?.toString()?.trim().orEmpty()
        val status = binding.statusInput.text?.toString()?.trim().orEmpty()

        var valid = true
        if (number.isBlank()) {
            binding.roomNumberLayout.error = getString(R.string.error_required_room_number)
            valid = false
        } else {
            binding.roomNumberLayout.error = null
        }

        if (type.isBlank() || !roomTypes.contains(type)) {
            binding.roomTypeLayout.error = getString(R.string.error_required_room_type)
            valid = false
        } else {
            binding.roomTypeLayout.error = null
        }

        val price = priceText.toDoubleOrNull()
        if (price == null || price < 0.0) {
            binding.priceLayout.error = getString(R.string.error_invalid_room_price)
            valid = false
        } else {
            binding.priceLayout.error = null
        }

        if (status.isBlank() || !roomStatuses.contains(status)) {
            binding.statusLayout.error = getString(R.string.error_required_room_status)
            valid = false
        } else {
            binding.statusLayout.error = null
        }

        if (!valid) {
            return
        }

        viewModel.saveRoom(number, type, price!!, status)
    }
}
