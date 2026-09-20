package com.marina.marina.diagnostics

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.File

/**
 * Verifies the debug launch-diagnostics harness itself, so the APK handed to a
 * device can be trusted to record what actually happened:
 *
 *  - [BareLaunchActivity] reaches a window with nothing but the framework (no
 *    Hilt, Compose, Room or Firebase) and leaves its stage markers behind.
 *  - [LaunchProbeActivity] walks the whole production path — Hilt graph, Room
 *    open, session restore, Compose, NavGraph — without recording a failure.
 *  - [LaunchDiag.recordFatal] really writes a full stack trace, replacing the
 *    device logcat that the crash report was missing.
 *
 * Lives in `src/test` but references `src/debug` classes, so it belongs to
 * `testDebugUnitTest` (the task CI runs); the release variant has no diagnostics.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LaunchDiagnosticsTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun stagesText(): String {
        val dir = LaunchDiag.directory(context) ?: return ""
        val file = File(dir, "stages.log")
        return if (file.isFile) file.readText() else ""
    }

    /** Idles the looper until [marker] shows up, so IO coroutines get a chance. */
    private fun awaitMarker(marker: String, timeoutMs: Long = 30_000) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            if (stagesText().contains(marker)) return
            Thread.sleep(50)
        }
    }

    @Test
    fun bareLaunchReachesWindowWithFrameworkOnly() {
        ActivityScenario.launch(BareLaunchActivity::class.java).use { scenario ->
            awaitMarker("Bare.onResume")
            scenario.onActivity { activity ->
                assertFalse("bare launch finished unexpectedly", activity.isFinishing)
            }
            val log = stagesText()
            assertTrue("bare markers missing from stages.log:\n$log", log.contains("STAGE  Bare.onResume"))
        }
    }

    @Test
    fun probeCompletesProductionLaunchPathWithoutFailure() {
        ActivityScenario.launch(LaunchProbeActivity::class.java).use { scenario ->
            listOf(
                "Probe.hiltGraph",
                "Probe.roomOpen",
                "Probe.sessionRestore",
                "Probe.firstComposition",
                "Probe.themeComposed",
                "Probe.navGraph"
            ).forEach { awaitMarker(it) }

            scenario.onActivity { activity ->
                assertFalse("probe finished unexpectedly", activity.isFinishing)
            }

            val log = stagesText()
            listOf(
                "Probe.hiltGraph",
                "Probe.roomOpen",
                "Probe.sessionRestore",
                "Probe.firstComposition",
                "Probe.themeComposed",
                "Probe.navGraph"
            ).forEach { marker ->
                assertTrue("$marker missing from stages.log:\n$log", log.contains(marker))
            }
            assertFalse("the probe recorded a failure:\n$log", log.contains("FAIL"))
        }
    }

    @Test
    fun fatalRecorderWritesFullStackTrace() {
        val dir = LaunchDiag.directory(context)
        assertNotNull("diagnostics directory was not created", dir)
        File(dir!!, "crash.log").delete()

        LaunchDiag.recordFatal(
            context,
            IllegalStateException("boom", IllegalArgumentException("root cause"))
        )

        val crash = File(dir, "crash.log")
        assertTrue("crash.log was not written to ${dir.absolutePath}", crash.isFile)
        val text = crash.readText()
        assertTrue("exception line missing:\n$text", text.contains("IllegalStateException: boom"))
        assertTrue(
            "cause chain missing:\n$text",
            text.contains("Caused by: java.lang.IllegalArgumentException: root cause")
        )
        assertTrue(
            "stack frames missing:\n$text",
            text.contains("at com.marina.marina.diagnostics.LaunchDiagnosticsTest")
        )
    }
}
