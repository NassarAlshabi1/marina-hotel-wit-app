package com.marina.marina.diagnostics

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.lifecycleScope
import androidx.navigation.compose.rememberNavController
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.domain.session.PaymentSessionContext
import com.marina.marina.domain.usecase.auth.RestoreSessionUseCase
import com.marina.marina.navigation.MarinaNavGraph
import com.marina.marina.navigation.Screen
import com.marina.marina.presentation.auth.AuthViewModel
import com.marina.marina.ui.theme.MarinaTheme
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Staged launch probe: the production launch path, step by step, every step
 * recorded before it is attempted.
 *
 * Unlike [BareLaunchActivity] this uses the real Hilt graph, the real Room
 * database and the real Compose content, so the LAST marker in
 * `marina-diag/stages.log` (or the on-screen list) names the exact step that
 * killed the process:
 *
 *   Probe.hiltGraph          → Hilt singleton graph constructed (Retrofit, prefs, DAOs)
 *   Probe.roomOpen           → Room opened (runs the v68→v70 migrations)
 *   Probe.sessionRestore     → the real `RestoreSessionUseCase` returned/threw
 *   Probe.firstComposition   → Compose mounted
 *   Probe.themeComposed      → `MarinaTheme` resolved
 *   Probe.authViewModelCreated → `hiltViewModel<AuthViewModel>()` constructed
 *   Probe.navGraph.composed  → `MarinaNavGraph` + Login/Dashboard composed
 *   Probe.firstFrameDrawn    → first frame rendered
 *   Probe.aliveAfter3s/10s   → survived the window the real app dies in
 *
 * Debug variants only — launched from its own "Marina PROBE (diag)" icon.
 */
@AndroidEntryPoint
class LaunchProbeActivity : ComponentActivity() {

    @Inject lateinit var database: AppDatabase
    @Inject lateinit var syncPreferences: SyncPreferences
    @Inject lateinit var restoreSessionUseCase: RestoreSessionUseCase

    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        LaunchDiag.startRun(this)
        LaunchDiag.stage(this, "Probe.enter")
        super.onCreate(savedInstanceState)
        LaunchDiag.stage(this, "Probe.superOnCreate")

        // Stage 1 — touch every injected field: forces the Hilt singleton graph
        // (Retrofit/OkHttp, EncryptedSharedPreferencesManager, DAO providers) to
        // be constructed on this thread, exactly as MainActivity does.
        try {
            LaunchDiag.note(
                this,
                "Probe.hiltGraph",
                "db=${database.javaClass.simpleName} prefs=${syncPreferences.javaClass.simpleName} " +
                    "useCase=${restoreSessionUseCase.javaClass.simpleName}"
            )
        } catch (t: Throwable) {
            LaunchDiag.failure(this, "Probe.hiltGraph", t)
        }

        // Stage 2 — open Room. This branch ships schema version 70 with 36
        // entities while the branch that launches fine ships 68 with 14, under
        // the same database file name, so a migration failure is a candidate.
        lifecycleScope.launch(Dispatchers.IO) {
            LaunchDiag.stage(this@LaunchProbeActivity, "Probe.roomOpen.begin")
            try {
                // Opening the writable database runs the migrations and reports
                // the schema version actually on disk.
                val opened = database.openHelper.writableDatabase
                LaunchDiag.note(this@LaunchProbeActivity, "Probe.roomOpen", "ok userVersion=${opened.version}")
            } catch (t: Throwable) {
                LaunchDiag.failure(this@LaunchProbeActivity, "Probe.roomOpen", t)
            }
        }

        // Stage 3 — the real session restore, on the same dispatcher the real
        // AuthViewModel uses (viewModelScope == Dispatchers.Main.immediate).
        // Production now swallows this failure via runCatching, so recording the
        // throwable here is how the underlying cause becomes visible.
        lifecycleScope.launch {
            LaunchDiag.stage(this@LaunchProbeActivity, "Probe.sessionRestore.begin")
            try {
                val user = restoreSessionUseCase()
                LaunchDiag.note(
                    this@LaunchProbeActivity,
                    "Probe.sessionRestore",
                    "user=${user?.username ?: "null"}"
                )
            } catch (t: Throwable) {
                LaunchDiag.failure(this@LaunchProbeActivity, "Probe.sessionRestore", t)
            } finally {
                // Never leave a phantom session behind after probing.
                PaymentSessionContext.clear()
            }
        }

        // Stage 4 — Compose + theme + the production content, with a marker
        // before each step.
        setContent {
            LaunchDiag.stage(this, "Probe.firstComposition")
            MarinaTheme {
                LaunchDiag.stage(this, "Probe.themeComposed")

                val authViewModel: AuthViewModel = hiltViewModel()
                LaunchDiag.stage(this, "Probe.authViewModelCreated")

                val authState by authViewModel.authState.collectAsState()
                LaunchDiag.note(
                    this,
                    "Probe.authState",
                    "restoring=${authState.isRestoring} authed=${authState.isAuthenticated} error=${authState.error}"
                )

                if (authState.isRestoring) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                } else {
                    val navController = rememberNavController()
                    LaunchDiag.stage(this, "Probe.navGraph.begin")
                    MarinaNavGraph(
                        navController = navController,
                        authViewModel = authViewModel,
                        startDestination = if (authState.isAuthenticated) {
                            Screen.Dashboard.route
                        } else {
                            Screen.Login.route
                        }
                    )
                    LaunchDiag.stage(this, "Probe.navGraph.composed")
                }
            }
        }

        window.decorView.post { LaunchDiag.stage(this, "Probe.firstFrameDrawn") }
    }

    override fun onResume() {
        super.onResume()
        LaunchDiag.stage(this, "Probe.onResume")
        // The reported crash happens inside the first second; these two markers
        // separate "dies during launch" from "dies later".
        handler.postDelayed({ LaunchDiag.stage(this, "Probe.aliveAfter3s") }, 3_000)
        handler.postDelayed({ LaunchDiag.stage(this, "Probe.aliveAfter10s") }, 10_000)
    }

    override fun onDestroy() {
        LaunchDiag.stage(this, "Probe.onDestroy")
        super.onDestroy()
    }
}
