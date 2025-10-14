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
import com.marinahotel.kotlin.databinding.FragmentPaymentsOverviewBinding

class PaymentsOverviewFragment : Fragment() {
    private var _binding: FragmentPaymentsOverviewBinding? = null
    private val binding get() = _binding!!
    private val adapter = RecentPaymentsAdapter()
    private lateinit var viewModel: PaymentsViewModel

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentPaymentsOverviewBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.recentPaymentsRecycler.layoutManager = LinearLayoutManager(requireContext())
        binding.recentPaymentsRecycler.adapter = adapter
        viewModel = ViewModelProvider(this)[PaymentsViewModel::class.java]
        viewLifecycleOwner.lifecycleScope.launchWhenStarted {
            viewLifecycleOwner.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.recentPayments.collect { list -> adapter.submitList(list) }
            }
        }
        binding.collectionProgress.progress = 0
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class PaymentItem(val title: String, val method: String, val amount: String)
