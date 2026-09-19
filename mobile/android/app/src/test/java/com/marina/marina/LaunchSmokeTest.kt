package com.marina.marina

import android.os.Looper
import androidx.test.core.app.ActivityScenario
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Launch smoke test — reproduces the user-reported "app closes instantly on
 * open" crash inside CI, with the real production stack trace.
 *
 * Launches the REAL MainActivity with:
 *   - the real MarinaApp application class (full Hilt component graph),
 *   - the real merged manifest (all providers initialize: FirebaseInit,
 *     androidx.startup, FileProvider),
 *   - real Room database creation and DataStore reads,
 *   - real Jetpack Compose initial composition of Login/Dashboard.
 *
 * If the app crashes at open, this test fails carrying the exact exception
 * that a physical device would show in logcat.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LaunchSmokeTest {

    private val backgroundCrashes = CopyOnWriteArrayList<Throwable>()
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    @Before
    fun captureBackgroundCrashes() {
        previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { _, throwable ->
            backgroundCrashes.add(throwable)
            throwable.printStackTrace()
        }
    }

    @After
    fun assertNoBackgroundCrashes() {
        Thread.setDefaultUncaughtExceptionHandler(previousHandler)
        assertTrue(
            "Background threads crashed during launch:\n" +
                backgroundCrashes.joinToString("\n\n") { it.stackTraceToString() },
            backgroundCrashes.isEmpty()
        )
    }

    @Test
    fun activityLaunchesAndSurvivesComposition() {
        val scenario = ActivityScenario.launch(MainActivity::class.java)

        // Drain the main looper repeatedly: executes initial Compose
        // composition, recompositions, and async continuations (DataStore
        // restoreSession resolves on Dispatchers.IO and resumes here).
        repeat(80) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(50)
        }

        scenario.onActivity { activity ->
            assertTrue("Activity finished unexpectedly during launch", !activity.isFinishing)
        }

        // Final drain: give IO coroutines (Room/DataStore) another window.
        repeat(40) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(50)
        }

        scenario.close()
    }
}
