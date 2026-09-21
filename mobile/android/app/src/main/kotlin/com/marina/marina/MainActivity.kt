package com.marina.marina

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.rememberNavController
import com.marina.marina.navigation.MarinaNavGraph
import com.marina.marina.navigation.Screen
import com.marina.marina.presentation.auth.AuthViewModel
import com.marina.marina.ui.theme.MarinaTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MarinaTheme {
                // The app is fully Arabic (like the Flutter original, which
                // wrapped everything in Directionality.rtl): force RTL so the
                // side navigation always sits on the right edge, regardless
                // of the device locale.
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                val authViewModel: AuthViewModel = hiltViewModel()
                val authState by authViewModel.authState.collectAsState()

                // Wait for the persisted session check to finish before we
                // pick a start destination — otherwise NavHost would always
                // start at "login" since restoreSession() resolves async.
                if (authState.isRestoring) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                } else {
                    val navController = rememberNavController()
                    MarinaNavGraph(
                        navController = navController,
                        authViewModel = authViewModel,
                        startDestination = if (authState.isAuthenticated) {
                            Screen.Dashboard.route
                        } else {
                            Screen.Login.route
                        }
                    )
                }
                }
            }
        }
    }
}
