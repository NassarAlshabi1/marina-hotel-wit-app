package com.marina.marina.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.google.gson.annotations.SerializedName

/**
 * Finance snapshot — append-only governance/forecast approval table.
 *
 * Parity unification: ports branch2's `worker/migrations/0009_finance_snapshots.sql`
 * + the `finance_snapshots` table from B2's `worker/schema.sql` L1103 to the
 * Android Room schema (Room migration 76→77).
 *
 * Read-only from API: no UPDATE, no DELETE. New snapshots are appended
 * by the manager/admin via the Worker `/api/finance/snapshots` route
 * (B2 `worker/src/finance-routes.ts`). The local copy is a mirror pulled
 * during sync so the Android app can read the latest snapshot offline
 * and compare variance against live D1 data.
 *
 * Not a sync entity — does not extend BaseSyncEntity. Id is server-assigned
 * (D1 INTEGER autoIncrement). Inserted locally only via the sync ingestor
 * on pull; never pushed by the Android client.
 */
@Entity(
    tableName = "finance_snapshots",
    indices = [
        Index(value = ["approved_at"], name = "idx_finance_snapshots_approved"),
        Index(value = ["scenario_key", "approved_at"], name = "idx_finance_snapshots_scenario"),
    ]
)
data class FinanceSnapshotEntity(
    @PrimaryKey(autoGenerate = true) @SerializedName("id") val id: Long = 0,
    @SerializedName("label") @ColumnInfo(name = "label") val label: String = "",
    @SerializedName("scenario_key") @ColumnInfo(name = "scenario_key", defaultValue = "base") val scenarioKey: String = "base",
    @SerializedName("scenario_json") @ColumnInfo(name = "scenario_json", defaultValue = "{}") val scenarioJson: String = "{}",
    @SerializedName("model_start") @ColumnInfo(name = "model_start") val modelStart: String,
    @SerializedName("model_end") @ColumnInfo(name = "model_end") val modelEnd: String,
    @SerializedName("opening_balance") @ColumnInfo(name = "opening_balance", defaultValue = "0") val openingBalance: Double = 0.0,
    @SerializedName("total_inflow") @ColumnInfo(name = "total_inflow", defaultValue = "0") val totalInflow: Double = 0.0,
    @SerializedName("total_outflow") @ColumnInfo(name = "total_outflow", defaultValue = "0") val totalOutflow: Double = 0.0,
    @SerializedName("financing_need") @ColumnInfo(name = "financing_need", defaultValue = "0") val financingNeed: Double = 0.0,
    @SerializedName("weeks_below_threshold") @ColumnInfo(name = "weeks_below_threshold", defaultValue = "0") val weeksBelowThreshold: Int = 0,
    @SerializedName("forecast_json") @ColumnInfo(name = "forecast_json") val forecastJson: String,
    @SerializedName("approved_by") @ColumnInfo(name = "approved_by", defaultValue = "") val approvedBy: String = "",
    @SerializedName("approved_at") @ColumnInfo(name = "approved_at") val approvedAt: Long,
)
