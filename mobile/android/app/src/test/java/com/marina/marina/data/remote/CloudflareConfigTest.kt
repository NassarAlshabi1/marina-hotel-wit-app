package com.marina.marina.data.remote

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * ✅ (2026-09-24) اختبارات إعدادات Cloudflare — تحرس نقل cloudflare_config.dart:
 * الافتراضي admin/admin، الأولوية للـ overrides، وفصل التخزين
 * (username في prefs عادية / password في prefs مشفّرة).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CloudflareConfigTest {

    private lateinit var config: CloudflareConfig
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        config = CloudflareConfig(context)
    }

    @After
    fun tearDown() {
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
    }

    @Test
    fun `defaults are admin-admin without overrides`() {
        assertEquals("admin", config.username)
        assertEquals("admin", config.password)
        assertFalse(config.hasCredentialOverrides)
    }

    @Test
    fun `username override takes priority over builtin`() {
        config.setCredentialOverrides(username = "manager", password = null)
        assertEquals("manager", config.username)
        // كلمة المرور تبقى المدمجة (قيمة null = إبقاء).
        assertEquals("admin", config.password)
        assertTrue(config.hasCredentialOverrides)
    }

    @Test
    fun `password override stored separately from username`() {
        config.setCredentialOverrides(username = "sync_service", password = "s3cret")
        assertEquals("sync_service", config.username)
        assertEquals("s3cret", config.password)

        // الفصل: username في prefs العادية، password في المشفّرة.
        val plain = context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
        val secure = context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
        assertEquals("sync_service", plain.getString(CloudflareConfig.USERNAME_OVERRIDE_KEY, null))
        assertEquals(
            "s3cret",
            secure.getString(CloudflareConfig.PASSWORD_OVERRIDE_SECURE_KEY, null)
        )
        // لا كلمة مرور نصاً صريحاً في prefs العادية (fix M2 في Flutter).
        assertNull(plain.getString("cf_password_override", null))
    }

    @Test
    fun `blank username override is ignored`() {
        config.setCredentialOverrides(username = "   ", password = null)
        assertEquals("admin", config.username)
    }

    @Test
    fun `clearCredentialOverrides returns to builtin`() {
        config.setCredentialOverrides(username = "manager", password = "pw")
        assertTrue(config.hasCredentialOverrides)
        config.clearCredentialOverrides()
        assertEquals("admin", config.username)
        assertEquals("admin", config.password)
        assertFalse(config.hasCredentialOverrides)
    }

    @Test
    fun `d1 token lifecycle through secure storage`() {
        // لا توكن افتراضياً — المسار المباشر معطّل حتى يضبطه المستخدم.
        assertNull(config.d1ApiToken)
        assertFalse(CloudflareD1Service.PARAMS_BUDGET > 0 && config.d1ApiToken != null)

        config.setD1ApiToken("cfut_exAMPLEtoken123")
        assertEquals("cfut_exAMPLEtoken123", config.d1ApiToken)

        // المسح يطفئ المسار المباشر.
        config.setD1ApiToken(null)
        assertNull(config.d1ApiToken)
        assertFalse(CloudflareD1Service.PARAMS_BUDGET > 0 && config.d1ApiToken != null)
    }
}
