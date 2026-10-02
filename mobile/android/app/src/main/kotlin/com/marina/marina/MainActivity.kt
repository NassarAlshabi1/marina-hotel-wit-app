package com.marina.marina

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                    contentColor = MaterialTheme.colorScheme.onBackground
                ) {
                    // Force RTL for the fully Arabic application so the sidebar
                    // remains on the right edge on every device locale.
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                        val authViewModel: AuthViewModel = hiltViewModel()
                        val authState by authViewModel.authState.collectAsState()

                        // Resolve the saved session before choosing the start route.
                        if (authState.isRestoring) {
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center
                            ) {
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
}
