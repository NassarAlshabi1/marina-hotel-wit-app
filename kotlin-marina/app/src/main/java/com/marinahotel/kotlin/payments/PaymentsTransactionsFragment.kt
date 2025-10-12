package com.marinahotel.kotlin.payments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.chip.Chip
import com.marinahotel.kotlin.databinding.FragmentPaymentsTransactionsBinding

class PaymentsTransactionsFragment : Fragment() {
    private var _binding: FragmentPaymentsTransactionsBinding? = null
    private val binding get() = _binding!!
    private val adapter = PaymentTransactionsAdapter()
    private val transactions = listOf(
        PaymentTransaction("BKG-1001", "نقدي", "10 يناير 10:45", "1500 ر.س"),
        PaymentTransaction("BKG-1002", "بطاقة", "10 يناير 12:10", "2200 ر.س"),
        PaymentTransaction("BKG-1003", "تحويل", "9 يناير 09:00", "1800 ر.س"),
        PaymentTransaction("BKG-1004", "بطاقة", "9 يناير 15:30", "950 ر.س")
    )

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPaymentsTransactionsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.transactionsRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.transactionsRecycler.adapter = adapter
        adapter.submitList(transactions)
        binding.methodChipGroup.setOnCheckedStateChangeListener { group, _ ->
            val checked = group.checkedChipIds.firstOrNull()?.let { id -> group.findViewById<Chip>(id)?.text?.toString() }
            val filtered = if (checked == null || checked == "الكل") transactions else transactions.filter { it.method == checked }
            adapter.submitList(filtered)
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class PaymentTransaction(val title: String, val method: String, val date: String, val amount: String)
