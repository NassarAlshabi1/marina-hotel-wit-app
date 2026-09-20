package com.marina.marina.diagnostics

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.widget.ScrollView
import android.widget.TextView

/**
 * Bare launch probe: framework [Activity] + [TextView] only.
 *
 * No Hilt, no Compose, no Navigation, no Room, no Firebase, no AppCompat.
 *
 *  - If this screen appears, the process got a window on screen after
 *    `Application.onCreate` and after every ContentProvider
 *    (FirebaseInitProvider, androidx.startup, WorkManager, FileProvider, ...)
 *    had already run. The failure is then inside the Activity / Compose / DI
 *    half of the launch path.
 *  - If this screen closes too, the failure is in `Application` (Hilt setup)
 *    or in a provider, i.e. before any screen is even created.
 *
 * Debug variants only — launched from its own "Marina BARE (diag)" icon.
 */
class BareLaunchActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        LaunchDiag.startRun(this)
        LaunchDiag.stage(this, "Bare.enter")
        super.onCreate(savedInstanceState)
        LaunchDiag.stage(this, "Bare.superOnCreate")

        val view = TextView(this).apply {
            setPadding(48, 140, 48, 48)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            text = "BARE LAUNCH ALIVE\n\n" + LaunchDiag.snapshot(this@BareLaunchActivity)
        }
        setContentView(ScrollView(this).apply { addView(view) })
        LaunchDiag.stage(this, "Bare.setContentView")

        // Surviving past the 3s mark proves nothing in the framework-only path
        // killed the process during the window the real app dies in (<1s).
        handler.postDelayed({
            LaunchDiag.stage(this, "Bare.aliveAfter3s")
            view.text = "BARE LAUNCH ALIVE (3s)\n\n" + LaunchDiag.snapshot(this)
        }, 3_000)
    }

    override fun onStart() {
        super.onStart()
        LaunchDiag.stage(this, "Bare.onStart")
    }

    override fun onResume() {
        super.onResume()
        LaunchDiag.stage(this, "Bare.onResume")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) LaunchDiag.stage(this, "Bare.windowFocused")
    }

    override fun onPause() {
        LaunchDiag.stage(this, "Bare.onPause")
        super.onPause()
    }

    override fun onDestroy() {
        LaunchDiag.stage(this, "Bare.onDestroy")
        super.onDestroy()
    }
}
