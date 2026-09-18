package com.marina.marina

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class MarinaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize Firebase, Crashlytics, etc.
    }
}