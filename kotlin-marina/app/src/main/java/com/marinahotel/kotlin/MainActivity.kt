package com.marinahotel.kotlin

import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.View
import androidx.appcompat.app.ActionBarDrawerToggle
import com.marinahotel.kotlin.BuildConfig
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GravityCompat
import com.marinahotel.kotlin.bookings.BookingsListActivity
import com.marinahotel.kotlin.dashboard.DashboardActivity
import com.marinahotel.kotlin.databinding.ActivityMainBinding
import com.marinahotel.kotlin.employees.EmployeesListActivity
import com.marinahotel.kotlin.expenses.ExpensesListActivity
import com.marinahotel.kotlin.notes.NotesActivity
import com.marinahotel.kotlin.payments.PaymentsMainActivity
import com.marinahotel.kotlin.reports.ReportsActivity
import com.marinahotel.kotlin.rooms.RoomsMainActivity
import com.marinahotel.kotlin.settings.SettingsMainActivity

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        val toggle = ActionBarDrawerToggle(
            this,
            binding.drawerLayout,
            binding.toolbar,
            R.string.navigation_drawer_open,
            R.string.navigation_drawer_close
        )
        binding.drawerLayout.addDrawerListener(toggle)
        toggle.syncState()
        binding.drawerLayout.layoutDirection = View.LAYOUT_DIRECTION_RTL
        binding.navigationView.layoutDirection = View.LAYOUT_DIRECTION_RTL
        binding.navigationView.setNavigationItemSelectedListener { item ->
            binding.drawerLayout.closeDrawers()
            when (item.itemId) {
                R.id.nav_dashboard -> startActivity(Intent(this, DashboardActivity::class.java))
                R.id.nav_bookings -> startActivity(Intent(this, BookingsListActivity::class.java))
                R.id.nav_rooms -> startActivity(Intent(this, RoomsMainActivity::class.java))
                R.id.nav_payments -> startActivity(Intent(this, PaymentsMainActivity::class.java))
                R.id.nav_reports -> startActivity(Intent(this, ReportsActivity::class.java))
                R.id.nav_employees -> startActivity(Intent(this, EmployeesListActivity::class.java))
                R.id.nav_expenses -> startActivity(Intent(this, ExpensesListActivity::class.java))
                R.id.nav_notes -> startActivity(Intent(this, NotesActivity::class.java))
                R.id.nav_settings -> startActivity(Intent(this, SettingsMainActivity::class.java))
            }
            true
        }
        binding.actionBookings.setOnClickListener {
            startActivity(Intent(this, BookingsListActivity::class.java))
        }
        binding.actionRooms.setOnClickListener {
            startActivity(Intent(this, RoomsMainActivity::class.java))
        }
        binding.actionPayments.setOnClickListener {
            startActivity(Intent(this, PaymentsMainActivity::class.java))
        }
        binding.actionReports.setOnClickListener {
            startActivity(Intent(this, ReportsActivity::class.java))
        }
        binding.versionText.text = getString(
            R.string.version_format,
            BuildConfig.VERSION_NAME,
            BuildConfig.VERSION_CODE
        )
    }

    override fun onBackPressed() {
        if (binding.drawerLayout.isDrawerOpen(GravityCompat.START) || binding.drawerLayout.isDrawerOpen(Gravity.RIGHT)) {
            binding.drawerLayout.closeDrawers()
        } else {
            super.onBackPressed()
        }
    }
}
