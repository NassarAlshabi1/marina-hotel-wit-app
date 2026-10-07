package com.marina.marina.data.auth

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.gson.Gson
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerLoginResponse
import com.marina.marina.data.remote.WorkerLoginUser
import com.marina.marina.data.sync.AutoSyncEngine
import com.marina.marina.di.EncryptedSharedPreferencesManager
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.session.UserSessionManager
import dagger.Lazy
import java.lang.reflect.Proxy
import kotlinx.coroutines.runBlocking
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
import retrofit2.Call
import retrofit2.Response

/** Local fixtures only. No real HTTP client, credentials or production calls. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = android.app.Application::class)
class AuthStartupLazyTest {
    private lateinit var context: Context
    private lateinit var preferences: SyncPreferences
    private lateinit var sessions: UserSessionManager
    private var remoteResolutions = 0

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE).edit().clear().commit()
        preferences = SyncPreferences(EncryptedSharedPreferencesManager(context))
        sessions = UserSessionManager()
        sessions.endSession()
        remoteResolutions = 0
    }

    @After
    fun tearDown() {
        sessions.endSession()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun localRepository() = AuthRepositoryImpl(
        Lazy {
            remoteResolutions++
            error("A local auth operation must not construct the remote graph")
        },
        preferences,
        sessions
    )

    @Test
    fun signedOutRestoreDoesNotConstructRemoteGraph() = runBlocking {
        val repository = localRepository()
        assertEquals(0, remoteResolutions)
        assertNull(repository.restoreSession())
        assertEquals(0, remoteResolutions)
        assertFalse(sessions.isSessionActive)
    }

    @Test
    fun rememberedIdentityAndPermissionsAreRestoredLocally() = runBlocking {
        val user = AuthUser(
            id = 23, username = "fixture-user", fullName = "Fixture",
            userType = "employee", permissions = listOf("view_rooms")
        )
        preferences.setRememberMe(true)
        preferences.saveAuthToken("synthetic-token")
        preferences.saveDeviceId("synthetic-device")
        preferences.saveCurrentUserJson(Gson().toJson(user))
        assertEquals(user, localRepository().restoreSession())
        assertEquals(user, sessions.currentUser.value)
        assertEquals(0, remoteResolutions)
    }

    @Test
    fun disabledRememberMeNeverRestoresSavedToken() = runBlocking {
        preferences.setRememberMe(false)
        preferences.saveAuthToken("synthetic-token")
        preferences.saveDeviceId("synthetic-device")
        assertNull(localRepository().restoreSession())
        assertFalse(sessions.isSessionActive)
        assertEquals(0, remoteResolutions)
    }

    @Test
    fun localLoginAndLogoutRemainNetworkIndependent() = runBlocking {
        val repository = localRepository()
        val user = repository.login(LocalAdminAuth.ADMIN_USERNAME, LocalAdminAuth.ADMIN_PASSWORD, true).getOrThrow()
        assertEquals("admin", user.userType)
        assertTrue(sessions.isSessionActive)
        assertEquals(0, remoteResolutions)
        repository.logout()
        assertFalse(sessions.isSessionActive)
        assertNull(repository.restoreSession())
        assertEquals(0, remoteResolutions)
    }

    @Test
    fun explicitRemoteLoginStillUsesWorkerIdentity() = runBlocking {
        var requests = 0
        val api = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader, arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            check(method.name == "login") { "Unexpected API operation: ${method.name}" }
            requests++
            Proxy.newProxyInstance(Call::class.java.classLoader, arrayOf(Call::class.java)) { _, call, _ ->
                check(call.name == "execute")
                Response.success(WorkerLoginResponse("synthetic-token", WorkerLoginUser("23", "fixture-user", "employee")))
            }
        } as CloudflareWorkerApi
        val service by lazy { CloudflareSyncService(api, CloudflareConfig(context), preferences) }
        val repository = AuthRepositoryImpl(Lazy { remoteResolutions++; service }, preferences, sessions)
        assertEquals(0, remoteResolutions)
        val user = repository.login("fixture-user", "synthetic-password", true).getOrThrow()
        assertTrue(remoteResolutions > 0)
        assertEquals(1, requests)
        assertEquals(23, user.id)
        assertEquals("employee", user.userType)
        assertTrue(user.permissions.isEmpty())
        assertEquals(user, sessions.currentUser.value)
    }

    @Test
    fun constructingEngineDoesNotResolveDatabaseOrNetworkGraph() {
        var resolutions = 0
        AutoSyncEngine(
            context,
            Lazy { resolutions++; error("SyncManager resolved during construction") },
            Lazy { resolutions++; error("Outbox resolved during construction") },
            preferences,
            Lazy { resolutions++; error("Probe service resolved during construction") },
            Lazy { resolutions++; error("Realtime client resolved during construction") }
        )
        assertEquals(0, resolutions)
    }
}
