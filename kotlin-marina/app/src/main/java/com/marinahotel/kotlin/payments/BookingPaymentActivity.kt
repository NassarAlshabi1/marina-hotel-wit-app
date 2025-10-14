package com.marinahotel.kotlin.payments

import android.os.Bundle
import android.view.LayoutInflater
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ActivityBookingPaymentBinding
import com.marinahotel.kotlin.databinding.DialogPaymentEntryBinding

class BookingPaymentActivity : AppCompatActivity() {
    private lateinit var binding: ActivityBookingPaymentBinding
    private val adapter = BookingPaymentAdapter()
    private lateinit var viewModel: PaymentsViewModel
    private var bookingId: Int = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookingPaymentBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        val code = intent.getStringExtra(EXTRA_BOOKING_ID) ?: ""
        binding.bookingCode.text = code
        bookingId = code.removePrefix("BKG-").toIntOrNull() ?: -1
        binding.progressIndicator.progress = 0
        binding.paidAmount.text = getString(R.string.paid_amount_format, 0)
        binding.remainingAmount.text = getString(R.string.remaining_amount_format, 0)
        binding.paymentsRecycler.layoutManager = LinearLayoutManager(this)
        binding.paymentsRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[PaymentsViewModel::class.java]
        lifecycleScope.launchWhenStarted {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.paymentsForBooking(bookingId).collect { list ->
                    adapter.submitList(list)
                }
            }
        }
        populatePaymentMethods()
        binding.addPaymentButton.setOnClickListener { showPaymentDialog() }
        binding.historyButton.setOnClickListener {
            startActivity(android.content.Intent(this, PaymentHistoryActivity::class.java).apply {
                putExtra(PaymentHistoryActivity.EXTRA_BOOKING_ID, binding.bookingCode.text.toString())
            })
        }
        binding.completeButton.setOnClickListener {
            Toast.makeText(this, "تم تأكيد المدفوعات", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun populatePaymentMethods() {
        val methods = listOf(
            PaymentMethodItem("نقدي", android.R.drawable.ic_menu_edit),
            PaymentMethodItem("بطاقة", android.R.drawable.ic_menu_send),
            PaymentMethodItem("تحويل", android.R.drawable.ic_menu_upload),
            PaymentMethodItem("فاتورة", android.R.drawable.ic_menu_agenda)
        )
        binding.paymentMethodsGrid.removeAllViews()
        methods.forEach { method ->
            val view = layoutInflater.inflate(R.layout.view_payment_method, binding.paymentMethodsGrid, false)
            val icon = view.findViewById<android.widget.ImageView>(R.id.iconView)
            val title = view.findViewById<android.widget.TextView>(R.id.titleView)
            icon.setImageResource(method.icon)
            title.text = method.title
            view.setOnClickListener {
                Toast.makeText(this, "تم اختيار ${method.title}", Toast.LENGTH_SHORT).show()
            }
            binding.paymentMethodsGrid.addView(view)
        }
    }

    private fun showPaymentDialog() {
        val dialogBinding = DialogPaymentEntryBinding.inflate(LayoutInflater.from(this))
        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.title_payment_new)
            .setView(dialogBinding.root)
            .setPositiveButton(R.string.action_save, null)
            .setNegativeButton(R.string.action_cancel) { d, _ -> d.dismiss() }
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val amountText = dialogBinding.amountInput.text?.toString()?.trim().orEmpty()
                val method = dialogBinding.methodInput.text?.toString()?.trim().orEmpty().ifBlank { getString(R.string.method_cash) }
                val note = dialogBinding.noteInput.text?.toString()?.trim().orEmpty().ifBlank { null }

                val amount = amountText.toIntOrNull()
                if (amount == null || amount <= 0) {
                    dialogBinding.amountLayout.error = getString(R.string.error_positive_amount)
                    return@setOnClickListener
                } else {
                    dialogBinding.amountLayout.error = null
                }

                viewModel.addPayment(bookingId, amount, method, note)
                Toast.makeText(this, R.string.saved_successfully, Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
        }
        dialog.show()
    }

    data class PaymentMethodItem(val title: String, val icon: Int)

    companion object {
        const val EXTRA_BOOKING_ID = "extra_booking_id"
    }
}
