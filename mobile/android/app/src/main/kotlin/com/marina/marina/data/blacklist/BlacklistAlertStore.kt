package com.marina.marina.data.blacklist

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.marina.marina.presentation.blacklist.BlacklistAlertService
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

/**
 * DataStore for persisting blacklist alerts across app restarts.
 * Mirrors Flutter's SharedPreferences-based persistence.
 */
private val Context.blacklistAlertDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "blacklist_alerts"
)

@Singleton
class BlacklistAlertStore @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        val ALERTS_JSON = stringPreferencesKey("alerts_json")
    }

    val alertsJsonFlow: Flow<String?> = context.blacklistAlertDataStore.data.map { it[ALERTS_JSON] }

    suspend fun saveAlerts(alerts: List<BlacklistAlertService.BlacklistAlert>) {
        val jsonStr = Json.encodeToString(alerts.map { it.toJson() })
        context.blacklistAlertDataStore.edit { it[ALERTS_JSON] = jsonStr }
    }

    suspend fun loadAlerts(): List<BlacklistAlertService.BlacklistAlert> {
        val jsonStr = alertsJsonFlow.first() ?: return emptyList()
        if (jsonStr.isBlank()) return emptyList()
        try {
            val list = Json.decodeFromString<List<String>>(jsonStr)
            return list.map { BlacklistAlertService.BlacklistAlert.fromJson(it) }
        } catch (e: Exception) {
            return emptyList()
        }
    }

    suspend fun clearAlerts() {
        context.blacklistAlertDataStore.edit { it[ALERTS_JSON] = "" }
    }
}