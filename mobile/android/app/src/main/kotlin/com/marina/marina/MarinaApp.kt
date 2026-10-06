package com.marina.marina

import android.app.Application
import com.marina.marina.data.sync.AutoSyncEngine
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class MarinaApp : Application() {

    /**
     * ✅ (2026-09-25) محرك المزامنة التلقائية — يبدأ مع عملية التطبيق نفسها
     * (نظير main.dart::start() في مرجع Flutter): مراقب outbox يدفع كتابات
     * كل الشاشات تلقائياً، فحص D1 وسحب تزايدي عبر بوابة الساعة
     * عند دخول الواجهة وعودة الاتصال، واسترداد صفوف الانهيار.
     */
    @Inject lateinit var autoSyncEngine: AutoSyncEngine

    override fun onCreate() {
        super.onCreate()
        // Initialize Firebase, Crashlytics, etc.
        autoSyncEngine.start()
    }
}
