package com.marina.marina.data.remote

import com.marina.marina.di.EncryptedSharedPreferencesManager
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CloudflareSyncService @Inject constructor(
    private val api: CloudflareWorkerApi,
    private val preferences: SyncPreferences
) {
    companion object {
        private const val TAG = "CloudflareSync"
    }

    /** The user object returned by the last successful Worker login (id/username/role). */
    var lastLoginUser: WorkerLoginUser? = null
        private set

    suspend fun login(username: String, password: String): Result<String> {
        return try {
            val response = api.login(
                WorkerLoginRequest(username, password, preferences.getDeviceId() ?: "")
            ).execute()
            if (response.isSuccessful && response.body()?.success == true) {
                response.body()?.token?.let { token ->
                    lastLoginUser = response.body()?.user
                    preferences.saveAuthToken(token)
                    Result.success(token)
                } ?: Result.failure(Exception("No token in response"))
            } else {
                Result.failure(Exception(response.body()?.error ?: "Login failed"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun pull(collection: String, cursor: Long, batchSize: Int = 100): Result<WorkerPullResponse> {
        return try {
            val response = api.pull(WorkerPullRequest(collection, cursor, batchSize)).execute()
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception("HTTP ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun push(entity: String, op: String, localUuid: String, payload: Map<String, Any>, clientTs: Long, idempotencyKey: String? = null): Result<WorkerPushResponse> {
        return try {
            val response = api.push(WorkerPushRequest(entity, op, localUuid, payload, clientTs, idempotencyKey)).execute()
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception("HTTP ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun d1Query(database: String, sql: String, params: List<Any>? = null): Result<List<Map<String, Any>>> {
        return try {
            val response = api.d1Query(database, D1QueryRequest(sql, params)).execute()
            if (response.isSuccessful) {
                val body = response.body()
                if (body?.result != null) {
                    val results = mutableListOf<Map<String, Any>>()
                    for (result in body.result) {
                        if (result.success) {
                            result.results?.let { results.addAll(it) }
                        } else {
                            return Result.failure(Exception(result.error ?: "Query failed"))
                        }
                    }
                    Result.success(results)
                } else {
                    Result.failure(Exception("Empty query result"))
                }
            } else {
                Result.failure(Exception("HTTP ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun d1Exec(database: String, sql: String, params: List<Any>? = null): Result<D1ExecResponse> {
        return try {
            val response = api.d1Exec(database, D1ExecRequest(sql, params)).execute()
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception("HTTP ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

@Singleton
class SyncPreferences @Inject constructor(
    private val preferencesManager: EncryptedSharedPreferencesManager
) {
    companion object {
        private const val KEY_AUTH_TOKEN = "auth_token"
        private const val KEY_LAST_PULL = "last_pull_ts"
        private const val KEY_LAST_PUSH = "last_push_ts"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_FULL_SYNC_COMPLETE = "full_sync_complete"
        private const val KEY_CURRENT_USER = "current_user_json"
    }

    /** Persists the logged-in user (JSON) so session restore keeps the REAL identity. */
    fun saveCurrentUserJson(json: String) {
        preferencesManager.saveString(KEY_CURRENT_USER, json)
    }

    fun getCurrentUserJson(): String? {
        return preferencesManager.getString(KEY_CURRENT_USER)
    }

    fun clearCurrentUser() {
        preferencesManager.saveString(KEY_CURRENT_USER, "")
    }

    fun saveAuthToken(token: String) {
        preferencesManager.saveString(KEY_AUTH_TOKEN, token)
    }

    fun getAuthToken(): String? {
        return preferencesManager.getString(KEY_AUTH_TOKEN)
    }

    fun saveLastPullTs(ts: Long) {
        preferencesManager.saveLong(KEY_LAST_PULL, ts)
    }

    fun getLastPullTs(): Long {
        return preferencesManager.getLong(KEY_LAST_PULL, 0L)
    }

    fun saveLastPushTs(ts: Long) {
        preferencesManager.saveLong(KEY_LAST_PUSH, ts)
    }

    fun getLastPushTs(): Long {
        return preferencesManager.getLong(KEY_LAST_PUSH, 0L)
    }

    fun saveDeviceId(deviceId: String) {
        preferencesManager.saveString(KEY_DEVICE_ID, deviceId)
    }

    fun getDeviceId(): String? {
        return preferencesManager.getString(KEY_DEVICE_ID)
    }

    fun isFullSyncComplete(): Boolean {
        return preferencesManager.getBoolean(KEY_FULL_SYNC_COMPLETE, false)
    }

    fun setFullSyncComplete(complete: Boolean) {
        preferencesManager.putBoolean(KEY_FULL_SYNC_COMPLETE, complete)
    }
}
