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
     * كل الشاشات تلقائياً، سحب عند فتح التطبيق عبر بوابة الساعة، دورة دورية
     * حسب الإعدادات، فلش عند عودة الاتصال، واسترداد صفوف الانهيار.
     */
    @Inject lateinit var autoSyncEngine: AutoSyncEngine

    override fun onCreate() {
        super.onCreate()
        // Initialize Firebase, Crashlytics, etc.
        autoSyncEngine.start()
    }
}
