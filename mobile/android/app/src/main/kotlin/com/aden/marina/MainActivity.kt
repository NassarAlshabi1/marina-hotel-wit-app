package com.aden.marina

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val MEMORY_CHANNEL = "com.aden.marina/device_memory"
        const val GET_TOTAL_MEMORY_BYTES = "getTotalMemoryBytes"
        const val IS_LOW_RAM_DEVICE = "isLowRamDevice"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEMORY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    GET_TOTAL_MEMORY_BYTES -> result.success(totalMemoryBytes())
                    IS_LOW_RAM_DEVICE -> result.success(isLowRamDevice())
                    else -> result.notImplemented()
                }
            }
    }

    private fun totalMemoryBytes(): Long? {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE)
            as? ActivityManager
            ?: return null
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        return memoryInfo.totalMem.takeIf { it > 0L }
    }

    /// إشارة أندرويد الرسمية لجهاز منخفض الذاكرة (1GB / Android Go).
    /// موثوقة أكثر من قراءة totalMem وحدها لأن النظام نفسه يعتمدها
    /// في قرارات قتل العمليات وحدود الكاش.
    private fun isLowRamDevice(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE)
            as? ActivityManager
            ?: return false
        return activityManager.isLowRamDevice
    }
}
