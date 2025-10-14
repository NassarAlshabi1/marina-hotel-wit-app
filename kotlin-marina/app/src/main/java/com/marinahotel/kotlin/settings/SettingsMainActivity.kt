package com.marinahotel.kotlin.settings

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.databinding.ActivitySettingsMainBinding
import com.marinahotel.kotlin.settings.employees.SettingsEmployeesActivity
import com.marinahotel.kotlin.settings.guests.SettingsGuestsActivity
import com.marinahotel.kotlin.settings.maintenance.SettingsMaintenanceActivity
import com.marinahotel.kotlin.settings.users.SettingsUsersActivity

class SettingsMainActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsMainBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        populateGrid()
    }

    private fun populateGrid() {
        val items = listOf(
            SettingsItem("الموظفون", "إدارة بيانات الموظفين", android.R.drawable.ic_menu_myplaces, SettingsEmployeesActivity::class.java),
            SettingsItem("النزلاء", "سجل الضيوف", android.R.drawable.ic_menu_recent_history, SettingsGuestsActivity::class.java),
            SettingsItem("المستخدمون", "صلاحيات الدخول", android.R.drawable.ic_menu_manage, SettingsUsersActivity::class.java),
            SettingsItem("الصيانة", "أدوات النظام", android.R.drawable.ic_menu_preferences, SettingsMaintenanceActivity::class.java)
        )
        binding.settingsGrid.removeAllViews()
        items.forEach { item ->
            val view = layoutInflater.inflate(R.layout.view_settings_item, binding.settingsGrid, false)
            val icon = view.findViewById<android.widget.ImageView>(R.id.iconView)
            val title = view.findViewById<android.widget.TextView>(R.id.titleView)
            val subtitle = view.findViewById<android.widget.TextView>(R.id.subtitleView)
            icon.setImageResource(item.icon)
            title.text = item.title
            subtitle.text = item.subtitle
            view.setOnClickListener {
                startActivity(Intent(this, item.target))
            }
            binding.settingsGrid.addView(view)
        }
    }

    data class SettingsItem(
        val title: String,
        val subtitle: String,
        val icon: Int,
        val target: Class<*>
    )
}
