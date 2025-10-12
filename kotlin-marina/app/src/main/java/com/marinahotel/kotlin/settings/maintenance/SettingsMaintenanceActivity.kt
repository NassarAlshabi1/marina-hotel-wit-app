package com.marinahotel.kotlin.settings.maintenance

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.marinahotel.kotlin.databinding.ActivitySettingsMaintenanceBinding

class SettingsMaintenanceActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsMaintenanceBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsMaintenanceBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.resetSyncCard.setOnClickListener { Toast.makeText(this, "سيتم إعادة المزامنة", Toast.LENGTH_SHORT).show() }
        binding.cacheCard.setOnClickListener { Toast.makeText(this, "تم تفريغ الذاكرة المؤقتة", Toast.LENGTH_SHORT).show() }
        binding.exportCard.setOnClickListener { Toast.makeText(this, "تم تصدير النسخة الاحتياطية", Toast.LENGTH_SHORT).show() }
    }
}
