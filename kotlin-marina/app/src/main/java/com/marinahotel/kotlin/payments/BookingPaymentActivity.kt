package com.marinahotel.kotlin.payments

import android.os.Bundle
import android.view.LayoutInflater
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ActivityBookingPaymentBinding
import com.marinahotel.kotlin.databinding.DialogPaymentEntryBinding

class BookingPaymentActivity : AppCompatActivity() {
    private lateinit var binding: ActivityBookingPaymentBinding
    private val adapter = BookingPaymentAdapter()
    private val payments = mutableListOf(
        PaymentTransaction("دفعة نقدية", "نقدي", "10 يناير 10:45", "1200 ر.س"),
        PaymentTransaction("دفعة بالبطاقة", "بطاقة", "9 يناير 18:20", "800 ر.س")
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityBookingPaymentBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.bookingCode.text = intent.getStringExtra(EXTRA_BOOKING_ID) ?: "BKG-1001"
        binding.progressIndicator.progress = 70
        binding.paidAmount.text = "مدفوع: 2000"
        binding.remainingAmount.text = "متبقي: 500"
        binding.paymentsRecycler.layoutManager = LinearLayoutManager(this)
        binding.paymentsRecycler.adapter = adapter
        adapter.submitList(payments.toList())
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
        AlertDialog.Builder(this)
            .setTitle("دفعة جديدة")
            .setView(dialogBinding.root)
            .setPositiveButton("حفظ") { dialog, _ ->
                val amount = dialogBinding.amountInput.text.toString().ifBlank { "0" }
                val method = dialogBinding.methodInput.text.toString().ifBlank { "نقدي" }
                val note = dialogBinding.noteInput.text.toString()
                payments.add(0, PaymentTransaction("$method", method, "الآن", "$amount ر.س"))
                adapter.submitList(payments.toList())
                Toast.makeText(this, "تمت إضافة الدفعة", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton("إلغاء") { dialog, _ -> dialog.dismiss() }
            .show()
    }

    data class PaymentMethodItem(val title: String, val icon: Int)

    companion object {
        const val EXTRA_BOOKING_ID = "extra_booking_id"
    }
}
