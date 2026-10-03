package com.marina.marina.resources

import android.app.Application
import android.content.Context
import android.graphics.drawable.AdaptiveIconDrawable
import android.os.Build
import android.view.ContextThemeWrapper
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [26, 34], application = Application::class)
class WindowResourcesTest {
    @Test
    fun navigationBarHasAppropriateContrastOnMinimumAndModernSdk() {
        val context = ContextThemeWrapper(
            ApplicationProvider.getApplicationContext<Context>(), R.style.Theme_MarinaHotel_NoActionBar
        )
        val colors = context.obtainStyledAttributes(intArrayOf(android.R.attr.navigationBarColor))
        try {
            val expected = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                R.color.marina_canvas
            } else {
                R.color.marina_navigation_legacy
            }
            assertEquals(context.getColor(expected), colors.getColor(0, 0))
        } finally {
            colors.recycle()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val flags = context.obtainStyledAttributes(intArrayOf(android.R.attr.windowLightNavigationBar))
            try {
                assertTrue(flags.getBoolean(0, false))
            } finally {
                flags.recycle()
            }
        }
    }

    @Test
    fun launcherIconInflatesOnBothSdkVersions() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val icon = context.getDrawable(R.mipmap.ic_launcher)
        assertTrue(icon is AdaptiveIconDrawable)
        icon as AdaptiveIconDrawable
        assertNotNull(icon.foreground)
        assertNotNull(icon.background)
    }
}
