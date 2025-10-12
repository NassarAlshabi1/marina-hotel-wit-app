package com.marinahotel.kotlin.dashboard

import android.content.Intent
import android.graphics.PorterDuff
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.bookings.BookingEditActivity
import com.marinahotel.kotlin.bookings.BookingsListActivity
import com.marinahotel.kotlin.databinding.ActivityDashboardBinding
import com.marinahotel.kotlin.payments.PaymentsMainActivity
import com.marinahotel.kotlin.reports.ReportsActivity
import com.marinahotel.kotlin.rooms.RoomsMainActivity

class DashboardActivity : AppCompatActivity() {
    private lateinit var binding: ActivityDashboardBinding
    private lateinit var viewModel: DashboardViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityDashboardBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        viewModel = ViewModelProvider(this)[DashboardViewModel::class.java]
        observeStats()
        populateRecentActivity()
        populateQuickActions()
        binding.syncButton.setOnClickListener {
            binding.syncButton.isEnabled = false
            binding.syncButton.postDelayed({ binding.syncButton.isEnabled = true }, 1200)
        }
    }

    private fun observeStats() {
        lifecycleScope.launchWhenStarted {
            repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                viewModel.stats.collect { s ->
                    val stats = listOf(
                        DashboardStat(getString(R.string.stat_total_rooms), s.totalRooms.toString(), android.R.drawable.ic_menu_week, R.color.primaryColor),
                        DashboardStat(getString(R.string.stat_available_rooms), s.availableRooms.toString(), android.R.drawable.ic_menu_myplaces, android.R.color.holo_green_dark),
                        DashboardStat(getString(R.string.stat_booked_rooms), s.bookedRooms.toString(), android.R.drawable.ic_menu_edit, android.R.color.holo_red_dark),
                        DashboardStat(getString(R.string.stat_occupancy), "${s.occupancyPercent}%", android.R.drawable.ic_menu_manage, android.R.color.holo_orange_dark)
                    )
                    binding.statsGrid.removeAllViews()
                    val inflater = layoutInflater
                    stats.forEach { stat ->
                        val view = inflater.inflate(R.layout.view_stat_card, binding.statsGrid, false)
                        val iconView = view.findViewById<android.widget.ImageView>(R.id.iconView)
                        val valueView = view.findViewById<android.widget.TextView>(R.id.valueView)
                        val titleView = view.findViewById<android.widget.TextView>(R.id.titleView)
                        val color = ContextCompat.getColor(this@DashboardActivity, stat.color)
                        iconView.setImageResource(stat.icon)
                        iconView.setColorFilter(color, PorterDuff.Mode.SRC_IN)
                        valueView.text = stat.value
                        valueView.setTextColor(color)
                        titleView.text = stat.title
                        binding.statsGrid.addView(view)
                    }
                }
            }
        }
    }

    private fun populateRecentActivity() {
        val items = listOf(
            ActivityItem("حجوزات جديدة", "تم إضافة 3 حجوزات جديدة اليوم", android.R.drawable.ic_menu_add),
            ActivityItem("مدفوعات مستلمة", "تم استلام دفعات بقيمة 15000 ريال", android.R.drawable.ic_menu_send),
            ActivityItem("غرف تم تسجيل المغادرة", "تم تسجيل مغادرة 2 حجز اليوم", android.R.drawable.ic_menu_revert)
        )
        binding.recentActivityContainer.removeAllViews()
        val inflater = layoutInflater
        items.forEachIndexed { index, item ->
            val view = inflater.inflate(R.layout.view_recent_activity, binding.recentActivityContainer, false)
            val iconView = view.findViewById<android.widget.ImageView>(R.id.iconView)
            val titleView = view.findViewById<android.widget.TextView>(R.id.titleView)
            val subtitleView = view.findViewById<android.widget.TextView>(R.id.subtitleView)
            iconView.setImageResource(item.icon)
            titleView.text = item.title
            subtitleView.text = item.subtitle
            binding.recentActivityContainer.addView(view)
            if (index < items.size - 1) {
                val divider = android.view.View(this)
                divider.layoutParams = android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    1
                ).apply {
                    topMargin = 8
                    bottomMargin = 8
                }
                divider.setBackgroundColor(ContextCompat.getColor(this, R.color.textSecondary))
                binding.recentActivityContainer.addView(divider)
            }
        }
    }

    private fun populateQuickActions() {
        val actions = listOf(
            QuickAction("حجز جديد", android.R.drawable.ic_input_add) {
                startActivity(Intent(this, BookingEditActivity::class.java))
            },
            QuickAction("إدارة الحجوزات", android.R.drawable.ic_menu_agenda) {
                startActivity(Intent(this, BookingsListActivity::class.java))
            },
            QuickAction("إدارة الغرف", android.R.drawable.ic_menu_mapmode) {
                startActivity(Intent(this, RoomsMainActivity::class.java))
            },
            QuickAction("التقارير", android.R.drawable.ic_menu_sort_by_size) {
                startActivity(Intent(this, ReportsActivity::class.java))
            },
            QuickAction("المدفوعات", android.R.drawable.ic_menu_my_calendar) {
                startActivity(Intent(this, PaymentsMainActivity::class.java))
            }
        )
        binding.quickActionsGrid.removeAllViews()
        actions.forEach { action ->
            val view = layoutInflater.inflate(R.layout.view_quick_action, binding.quickActionsGrid, false)
            val iconView = view.findViewById<android.widget.ImageView>(R.id.iconView)
            val titleView = view.findViewById<android.widget.TextView>(R.id.titleView)
            iconView.setImageResource(action.icon)
            titleView.text = action.title
            view.setOnClickListener { action.onClick.invoke() }
            binding.quickActionsGrid.addView(view)
        }
    }

    data class DashboardStat(val title: String, val value: String, val icon: Int, val color: Int)

    data class ActivityItem(val title: String, val subtitle: String, val icon: Int)

    data class QuickAction(val title: String, val icon: Int, val onClick: () -> Unit)
}
