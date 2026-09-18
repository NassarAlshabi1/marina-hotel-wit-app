package com.marina.marina.data

import retrofit2.http.*
import retrofit2.Call
import com.google.gson.annotations.SerializedName

data class D1QueryRequest(
    @SerializedName("sql") val sql: String,
    @SerializedName("params") val params: List<Any>? = null
)

data class D1QueryResponse(
    @SerializedName("result") val result: List<D1Result>?
)

data class D1Result(
    @SerializedName("results") val results: List<Map<String, Any>>?,
    @SerializedName("success") val success: Boolean,
    @SerializedName("error") val error: String?
)

data class D1ExecRequest(
    @SerializedName("sql") val sql: String,
    @SerializedName("params") val params: List<Any>? = null
)

data class D1ExecResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("error") val error: String?,
    @SerializedName("result") val result: D1ExecResult?
)

data class D1ExecResult(
    @SerializedName("meta") val meta: D1Meta?
)

data class D1Meta(
    @SerializedName("last_row_id") val lastRowId: Long?,
    @SerializedName("rows_read") val rowsRead: Long?,
    @SerializedName("rows_written") val rowsWritten: Long?,
    @SerializedName("changes") val changes: Long?
)

interface CloudflareD1Api {
    @POST("/api/d1/query")
    fun query(
        @Query("database") database: String,
        @Body request: D1QueryRequest
    ): Call<D1QueryResponse>

    @POST("/api/d1/exec")
    fun exec(
        @Query("database") database: String,
        @Body request: D1ExecRequest
    ): Call<D1ExecResponse>
}

data class WorkerPullRequest(
    @SerializedName("collection") val collection: String,
    @SerializedName("cursor") val cursor: Long,
    @SerializedName("batch_size") val batchSize: Int = 100
)

data class WorkerPullResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("records") val records: List<Map<String, Any>>?,
    @SerializedName("next_cursor") val nextCursor: Long?,
    @SerializedName("error") val error: String?
)

data class WorkerPushRequest(
    @SerializedName("entity") val entity: String,
    @SerializedName("op") val op: String,
    @SerializedName("local_uuid") val localUuid: String,
    @SerializedName("payload") val payload: Map<String, Any>,
    @SerializedName("client_ts") val clientTs: Long,
    @SerializedName("idempotency_key") val idempotencyKey: String?
)

data class WorkerPushResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("server_id") val serverId: Long?,
    @SerializedName("error") val error: String?
)

data class WorkerLoginRequest(
    @SerializedName("username") val username: String,
    @SerializedName("password") val password: String
)

data class WorkerLoginResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("token") val token: String?,
    @SerializedName("error") val error: String?
)

interface CloudflareWorkerApi {
    @POST("/api/auth/login")
    fun login(@Body request: WorkerLoginRequest): Call<WorkerLoginResponse>

    @POST("/api/sync/pull")
    fun pull(@Body request: WorkerPullRequest): Call<WorkerPullResponse>

    @POST("/api/sync/push")
    fun push(@Body request: WorkerPushRequest): Call<WorkerPushResponse>

    @POST("/api/d1/query")
    fun d1Query(
        @Query("database") database: String,
        @Body request: D1QueryRequest
    ): Call<D1QueryResponse>

    @POST("/api/d1/exec")
    fun d1Exec(
        @Query("database") database: String,
        @Body request: D1ExecRequest
    ): Call<D1ExecResponse>
}