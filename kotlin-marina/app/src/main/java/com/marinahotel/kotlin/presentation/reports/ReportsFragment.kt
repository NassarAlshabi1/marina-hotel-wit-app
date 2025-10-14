package com.marinahotel.kotlin.presentation.reports

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.github.mikephil.charting.components.XAxis
import com.github.mikephil.charting.data.BarData
import com.github.mikephil.charting.data.BarDataSet
import com.github.mikephil.charting.data.BarEntry
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.data.LineData
import com.github.mikephil.charting.data.LineDataSet
import com.github.mikephil.charting.formatter.IndexAxisValueFormatter
import com.google.android.material.datepicker.MaterialDatePicker
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.FragmentReportsBinding
import com.marinahotel.kotlin.presentation.HotelViewModelFactory
import com.marinahotel.kotlin.presentation.common.hotelRepository
import kotlinx.coroutines.launch

class ReportsFragment : Fragment() {

    private var _binding: FragmentReportsBinding? = null
    private val binding: FragmentReportsBinding get() = _binding!!

    private val viewModel: ReportsViewModel by viewModels {
        HotelViewModelFactory { ReportsViewModel(hotelRepository()) }
    }

    private val summaryAdapter = ReportsSummaryAdapter()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentReportsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setupRecyclerView()
        setupCharts()
        setupDateInputs()
        observeState()
    }

    private fun setupRecyclerView() {
        binding.reportsRecyclerView.adapter = summaryAdapter
    }

    private fun setupCharts() {
        binding.occupancyChart.apply {
            description.isEnabled = false
            axisRight.isEnabled = false
            axisLeft.axisMinimum = 0f
            axisLeft.axisMaximum = 100f
            axisLeft.setDrawGridLines(true)
            xAxis.position = XAxis.XAxisPosition.BOTTOM
            xAxis.granularity = 1f
            xAxis.setDrawGridLines(false)
            legend.isEnabled = false
            setTouchEnabled(false)
            setScaleEnabled(false)
            setNoDataText(getString(R.string.text_no_data))
        }
        binding.revenueChart.apply {
            description.isEnabled = false
            axisRight.isEnabled = false
            axisLeft.axisMinimum = 0f
            axisLeft.setDrawGridLines(true)
            xAxis.position = XAxis.XAxisPosition.BOTTOM
            xAxis.granularity = 1f
            xAxis.setDrawGridLines(false)
            legend.isEnabled = true
            setTouchEnabled(false)
            setScaleEnabled(false)
            setNoDataText(getString(R.string.text_no_data))
        }
    }

    private fun setupDateInputs() {
        binding.fromDateInput.setOnClickListener { showDatePicker(isStart = true) }
        binding.fromDateInput.setOnFocusChangeListener { view, hasFocus ->
            if (hasFocus) {
                showDatePicker(isStart = true)
                view.clearFocus()
            }
        }
        binding.fromDateLayout.setOnClickListener { showDatePicker(isStart = true) }
        binding.toDateInput.setOnClickListener { showDatePicker(isStart = false) }
        binding.toDateInput.setOnFocusChangeListener { view, hasFocus ->
            if (hasFocus) {
                showDatePicker(isStart = false)
                view.clearFocus()
            }
        }
        binding.toDateLayout.setOnClickListener { showDatePicker(isStart = false) }
    }

    private fun showDatePicker(isStart: Boolean) {
        val currentState = viewModel.uiState.value
        val currentSelection = if (isStart) currentState.fromDate else currentState.toDate
        val titleRes = if (isStart) R.string.hint_from_date else R.string.hint_to_date
        val picker = MaterialDatePicker.Builder.datePicker()
            .setTitleText(titleRes)
            .setSelection(currentSelection)
            .build()
        picker.addOnPositiveButtonClickListener { timestamp ->
            if (isStart) {
                viewModel.onSelectFromDate(timestamp)
            } else {
                viewModel.onSelectToDate(timestamp)
            }
        }
        picker.show(childFragmentManager, if (isStart) "from_date_picker" else "to_date_picker")
    }

    private fun observeState() {
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.uiState.collect { state ->
                    renderState(state)
                }
            }
        }
    }

    private fun renderState(state: ReportsViewModel.ReportsUiState) {
        val revenueFormatted = getString(R.string.label_amount_format, state.totalRevenue)
        binding.totalRevenueText.text = getString(R.string.label_value_format, getString(R.string.label_total_revenue), revenueFormatted)

        val expensesFormatted = getString(R.string.label_amount_format, state.totalExpenses)
        binding.totalExpensesText.text = getString(R.string.label_value_format, getString(R.string.label_total_expenses), expensesFormatted)

        val netFormatted = getString(R.string.label_amount_format, state.netIncome)
        binding.netIncomeText.text = getString(R.string.label_value_format, getString(R.string.label_net_income), netFormatted)
        val netColorRes = when {
            state.netIncome > 0 -> R.color.color_success
            state.netIncome < 0 -> R.color.color_error
            else -> R.color.color_text_primary
        }
        binding.netIncomeText.setTextColor(ContextCompat.getColor(requireContext(), netColorRes))

        binding.fromDateInput.setText(viewModel.formatDate(state.fromDate))
        binding.toDateInput.setText(viewModel.formatDate(state.toDate))

        summaryAdapter.submitList(state.summaries)
        binding.reportsEmptyText.isVisible = state.summaries.isEmpty()
        binding.reportsRecyclerView.isVisible = state.summaries.isNotEmpty()

        updateOccupancyChart(state)
        updateRevenueChart(state)
    }

    private fun updateOccupancyChart(state: ReportsViewModel.ReportsUiState) {
        val summaries = state.summaries
        if (summaries.isEmpty()) {
            binding.occupancyChart.clear()
            binding.occupancyChart.invalidate()
            return
        }
        val entries = summaries.mapIndexed { index, summary -> Entry(index.toFloat(), summary.occupancyPercent) }
        val dataSet = LineDataSet(entries, "").apply {
            color = ContextCompat.getColor(requireContext(), R.color.color_primary)
            setCircleColor(ContextCompat.getColor(requireContext(), R.color.color_primary))
            lineWidth = 2f
            circleRadius = 4f
            setDrawValues(false)
            mode = LineDataSet.Mode.CUBIC_BEZIER
        }
        binding.occupancyChart.data = LineData(dataSet)
        val labels = summaries.map { it.label }
        binding.occupancyChart.xAxis.apply {
            valueFormatter = IndexAxisValueFormatter(labels)
            labelCount = labels.size
        }
        binding.occupancyChart.invalidate()
    }

    private fun updateRevenueChart(state: ReportsViewModel.ReportsUiState) {
        val summaries = state.summaries
        if (summaries.isEmpty()) {
            binding.revenueChart.clear()
            binding.revenueChart.invalidate()
            return
        }
        val revenueEntries = summaries.mapIndexed { index, summary -> BarEntry(index.toFloat(), summary.revenue.toFloat()) }
        val expensesEntries = summaries.mapIndexed { index, summary -> BarEntry(index.toFloat(), summary.expenses.toFloat()) }

        val revenueSet = BarDataSet(revenueEntries, getString(R.string.label_total_revenue)).apply {
            color = ContextCompat.getColor(requireContext(), R.color.color_success)
            setDrawValues(false)
        }
        val expensesSet = BarDataSet(expensesEntries, getString(R.string.label_total_expenses)).apply {
            color = ContextCompat.getColor(requireContext(), R.color.color_error)
            setDrawValues(false)
        }

        val data = BarData(revenueSet, expensesSet)
        val groupSpace = 0.2f
        val barSpace = 0.03f
        val barWidth = 0.35f
        data.barWidth = barWidth

        binding.revenueChart.data = data
        val labels = summaries.map { it.label }
        val xAxis = binding.revenueChart.xAxis
        xAxis.valueFormatter = IndexAxisValueFormatter(labels)
        xAxis.labelCount = labels.size
        xAxis.axisMinimum = 0f
        xAxis.setCenterAxisLabels(true)
        val groupWidth = data.groupWidth(groupSpace, barSpace)
        xAxis.axisMaximum = groupWidth * summaries.size
        binding.revenueChart.groupBars(0f, groupSpace, barSpace)
        binding.revenueChart.invalidate()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
