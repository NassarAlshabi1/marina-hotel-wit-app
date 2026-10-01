package com.marina.marina

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    companion object {
        private const val MEMORY_CHANNEL = "com.marina.marina/device_memory"
    }

    // ✅ (2026-09-30) قناة قياس RAM الحقيقي — يستهلكها
    // WeakDeviceOptimizer لاختيار ملف الأداء (1GB → المستوى 3).
    // كانت غائبة: الكشف يعتمد على تخمين الأنوية فقط (يُسيء تقدير
    // أجهزة 8-أنوية/2GB كمتوسطة بدل ضعيفة).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEMORY_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "getTotalMemoryBytes") {
                try {
                    val activityManager =
                        getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val memoryInfo = ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memoryInfo)
                    result.success(memoryInfo.totalMem)
                } catch (e: Exception) {
                    result.error("UNAVAILABLE", "Memory info unavailable", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
