package com.marinahotel.kotlin.payments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.marinahotel.kotlin.databinding.FragmentPaymentsOverviewBinding

class PaymentsOverviewFragment : Fragment() {
    private var _binding: FragmentPaymentsOverviewBinding? = null
    private val binding get() = _binding!!
    private val adapter = RecentPaymentsAdapter()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPaymentsOverviewBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.recentPaymentsRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.recentPaymentsRecycler.adapter = adapter
        adapter.submitList(
            listOf(
                PaymentItem("BKG-1001", "نقدي", "1500 ر.س"),
                PaymentItem("BKG-1002", "بطاقة", "2200 ر.س"),
                PaymentItem("BKG-1003", "تحويل", "1800 ر.س")
            )
        )
        binding.collectionProgress.progress = 70
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class PaymentItem(val title: String, val method: String, val amount: String)
