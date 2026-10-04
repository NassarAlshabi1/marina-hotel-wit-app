package com.marina.marina.macrobenchmark

import android.os.Bundle
import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.StartupTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Fresh, offline entry screen only. No login credentials, synthetic swipes or financial writes. */
@LargeTest
@RunWith(AndroidJUnit4::class)
class EntryStartupBenchmark {
    @get:Rule
    val benchmark = MacrobenchmarkRule()

    @Before
    fun requireDisposableOfflineHarness() {
        phase("Checking offline harness and UiAutomator shell")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        assertEquals("Only the verified offline harness may run this suite", "true",
            InstrumentationRegistry.getArguments().getString("marina.offlineVerified"))
        assertEquals("Personal/physical devices are not supported by this harness", "1",
            UiDevice.getInstance(instrumentation).executeShellCommand("getprop ro.kernel.qemu").trim())
        phase("Offline and emulator guards passed")
    }

    @Test
    fun coldStartup() = measure(StartupMode.COLD)

    @Test
    fun warmStartup() = measure(StartupMode.WARM)

    private fun phase(message: String) {
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("marina.phase", message)
        })
    }

    private fun measure(mode: StartupMode) {
        phase("$mode entering measureRepeated with Full compilation")
        benchmark.measureRepeated(
            packageName = TARGET_PACKAGE,
            metrics = listOf(StartupTimingMetric()),
            iterations = ITERATIONS,
            startupMode = mode,
            compilationMode = CompilationMode.Full(),
            setupBlock = {
                // Outside the measured block: do not add status IPC to captured startup.
                phase("$mode setup reached after benchmark initialization/compilation")
                pressHome()
                if (mode == StartupMode.WARM) {
                    startActivityAndWait()
                    check(device.wait(Until.hasObject(By.res(LOGIN_TAG)), LOGIN_TIMEOUT_MS))
                    pressHome()
                }
            }
        ) {
            startActivityAndWait()
            assertTrue("Expected actual login screen, not a crash/splash/other activity",
                device.wait(Until.hasObject(By.res(LOGIN_TAG)), LOGIN_TIMEOUT_MS))
        }

        phase("$mode measurement completed")
    }

    private companion object {
        const val TARGET_PACKAGE = "com.a.a"
        const val LOGIN_TAG = "marina_login_screen"
        const val ITERATIONS = 8
        const val LOGIN_TIMEOUT_MS = 15_000L
    }
}
