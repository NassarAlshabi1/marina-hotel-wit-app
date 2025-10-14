package com.marinahotel.kotlin.payments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.chip.Chip
import com.marinahotel.kotlin.databinding.FragmentPaymentsTransactionsBinding

class PaymentsTransactionsFragment : Fragment() {
    private var _binding: FragmentPaymentsTransactionsBinding? = null
    private val binding get() = _binding!!
    private val adapter = PaymentTransactionsAdapter()
    private lateinit var viewModel: PaymentsViewModel
    private var allTransactions: List<PaymentTransaction> = emptyList()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPaymentsTransactionsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.transactionsRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.transactionsRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[PaymentsViewModel::class.java]
        viewLifecycleOwner.lifecycleScope.launchWhenStarted {
            viewLifecycleOwner.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.recentPayments.collect { list ->
                    allTransactions = list.map { PaymentTransaction(it.title, it.method, "", it.amount) }
                    adapter.submitList(allTransactions)
                }
            }
        }
        binding.methodChipGroup.setOnCheckedStateChangeListener { group, _ ->
            val checked = group.checkedChipIds.firstOrNull()?.let { id -> group.findViewById<Chip>(id)?.text?.toString() }
            val filtered = if (checked == null || checked == "الكل") allTransactions else allTransactions.filter { it.method == checked }
            adapter.submitList(filtered)
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class PaymentTransaction(val title: String, val method: String, val date: String, val amount: String)
