package com.marinahotel.kotlin.settings.users

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.marinahotel.kotlin.databinding.ActivitySettingsUsersBinding
import com.marinahotel.kotlin.databinding.DialogUserFormBinding

class SettingsUsersActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsUsersBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsUsersBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.changePasswordButton.setOnClickListener { showPasswordDialog() }
        binding.manageUsersButton.setOnClickListener { showUserDialog() }
        binding.biometricSwitch.setOnCheckedChangeListener { _, isChecked ->
            Toast.makeText(this, if (isChecked) "تم تفعيل البصمة" else "تم إيقاف البصمة", Toast.LENGTH_SHORT).show()
        }
        binding.emailSwitch.setOnCheckedChangeListener { _, isChecked ->
            Toast.makeText(this, if (isChecked) "سيتم إرسال التنبيهات" else "تم إيقاف التنبيهات", Toast.LENGTH_SHORT).show()
        }
    }

    private fun showPasswordDialog() {
        val dialogBinding = DialogUserFormBinding.inflate(layoutInflater)
        dialogBinding.titleInput.hint = "كلمة المرور الحالية"
        dialogBinding.roleInput.hint = "كلمة المرور الجديدة"
        dialogBinding.emailInput.hint = "تأكيد كلمة المرور"
        dialogBinding.roleDropDownLayout.visibility = android.view.View.GONE
        AlertDialog.Builder(this)
            .setTitle("تغيير كلمة المرور")
            .setView(dialogBinding.root)
            .setPositiveButton("حفظ") { dialog, _ ->
                Toast.makeText(this, "تم تحديث كلمة المرور", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton("إلغاء") { dialog, _ -> dialog.dismiss() }
            .show()
    }

    private fun showUserDialog() {
        val dialogBinding = DialogUserFormBinding.inflate(layoutInflater)
        val roles = listOf("مدير", "محاسب", "موظف استقبال")
        val adapter = android.widget.ArrayAdapter(this, android.R.layout.simple_list_item_1, roles)
        dialogBinding.roleInput.setAdapter(adapter)
        AlertDialog.Builder(this)
            .setTitle("مستخدم جديد")
            .setView(dialogBinding.root)
            .setPositiveButton("حفظ") { dialog, _ ->
                Toast.makeText(this, "تم إضافة المستخدم", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton("إلغاء") { dialog, _ -> dialog.dismiss() }
            .show()
    }
}
