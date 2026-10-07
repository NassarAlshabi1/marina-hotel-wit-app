package com.marina.marina.di

import android.content.Context
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.marina.marina.data.local.AppDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    /** Add stable UUID references for salary-payment cycles and carry-over employees. */
    val MIGRATION_70_71 = object : Migration(70, 71) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE salary_payments ADD COLUMN cycle_uuid TEXT")
            db.execSQL("ALTER TABLE salary_carry_over_logs ADD COLUMN employee_uuid TEXT")
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_salary_payments_cycle_uuid " +
                    "ON salary_payments(cycle_uuid)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_salary_carryover_employee_uuid " +
                    "ON salary_carry_over_logs(employee_uuid)"
            )
        }
    }

    val MIGRATION_71_72 = object : Migration(71, 72) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE salary_withdrawals ADD COLUMN expense_uuid TEXT")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_salary_wd_expense_uuid ON salary_withdrawals(expense_uuid)")
            db.execSQL("CREATE TABLE IF NOT EXISTS pending_sync_links (entity TEXT NOT NULL, localUuid TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(entity, localUuid))")
        }
    }

    val MIGRATION_72_73 = object : Migration(72, 73) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("CREATE TABLE IF NOT EXISTS sync_quarantine (entity TEXT NOT NULL, recordKey TEXT NOT NULL, payload TEXT NOT NULL, reason TEXT NOT NULL, PRIMARY KEY(entity, recordKey))")
        }
    }

    /** Additive indexes only: no backfill, no financial-row rewrite. */
    val MIGRATION_73_74 = object : Migration(73, 74) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_salary_wd_employee_uuid ON salary_withdrawals(employee_uuid)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_salary_cycles_employee_uuid ON salary_cycles(employee_uuid)")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_salary_payments_employee_uuid ON salary_payments(employee_uuid)")
        }
    }

    val MIGRATION_74_75 = object : Migration(74, 75) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE expenses ADD COLUMN expense_kind TEXT")
            db.execSQL("""UPDATE expenses SET expense_kind = CASE
 WHEN TRIM(expense_type) IN ('رواتب','سحب راتب','سحب من الراتب') THEN 'salary_withdrawal'
 WHEN TRIM(expense_type) = 'سلفة' THEN 'salary_advance'
 WHEN TRIM(expense_type) = 'خصم من الراتب' AND is_auto_generated = 1 AND instr(description, 'قسط سلفة') > 0 THEN 'salary_installment'
 WHEN TRIM(expense_type) = 'خصم من الراتب' AND is_auto_generated = 1 THEN 'unclassified'
 WHEN TRIM(expense_type) IN ('خصم من الراتب','خصم راتب','خصم','غياب') THEN 'salary_deduction'
 ELSE 'normal' END WHERE expense_kind IS NULL""")
        }
    }

    /**
     * ✅ (2026-10-06) إغلاق فجوة «حقول خادمية تُسقَط صامتة عند السحب».
     *
     * اكتُشفت بمقارنة أعمدة `worker/schema.sql` بأعمدة كيانات Room لكل
     * الكيانات الـ24: 14 عموداً خادمياً بلا عمود محلي، منها ما كان يُخزَّن
     * بصفر/فراغ (كمية المخزون) ومنها ما كان يُفشل التطبيق كلياً (قيد
     * NOT NULL في `inventory_transactions.transaction_type` بلا واجهة
     * خادمية) فيتجمّد مؤشر الدلتا. كلها إضافية بحتة بلا إعادة كتابة صف:
     *  • `expenses.employee_link_cleared` — يُحفظ العلم بدل إزالته.
     *  • `salary_withdrawals.expense_id` — الرقم التسلسلي للمصروف المرتبط.
     *  • `inventory_items.is_active` — نظير `quantity` (الاسم المحلي
     *    `current_quantity` يُغذّى بالاسم الخادمي عند الاستيعاب).
     *  • `inventory_transactions.item_local_uuid` / `user_id` / `user_name`.
     *  • `blacklist_entries.added_by` / `added_date`.
     */
    val MIGRATION_75_76 = object : Migration(75, 76) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE expenses ADD COLUMN employee_link_cleared INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE salary_withdrawals ADD COLUMN expense_id INTEGER")
            db.execSQL("ALTER TABLE inventory_items ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1")
            db.execSQL("ALTER TABLE inventory_transactions ADD COLUMN item_local_uuid TEXT")
            db.execSQL("ALTER TABLE inventory_transactions ADD COLUMN user_id INTEGER")
            db.execSQL("ALTER TABLE inventory_transactions ADD COLUMN user_name TEXT")
            db.execSQL("ALTER TABLE blacklist_entries ADD COLUMN added_by TEXT")
            db.execSQL("ALTER TABLE blacklist_entries ADD COLUMN added_date TEXT")
            // حجر السحب: عدّاد المحاولات وعمر أول عزل — يقودان الشفاء الدوري
            // وإخلاء السقف الأقدم-أولاً (نظير Dart pull_quarantine).
            db.execSQL("ALTER TABLE sync_quarantine ADD COLUMN attempts INTEGER NOT NULL DEFAULT 1")
            db.execSQL("ALTER TABLE sync_quarantine ADD COLUMN firstSeen INTEGER NOT NULL DEFAULT 0")
        }
    }

    /**
     * Parity unification: ports branch2's worker migrations 0008 +
     * 0009 to the local Room schema. Both are pure additive — no
     * financial rewrite, no row mutation. Mirrors worker/migrations
     * 0008_idempotency_log_cleanup.sql + 0009_finance_snapshots.sql.
     *
     *  • `idx_idempotency_processed_at` — O(log n) TTL index for the
     *    daily cron cleanup of the local idempotency_log mirror
     *    (counterpart of worker/src/maintenance.ts).
     *
     *  • `finance_snapshots` table — append-only governance/forecast
     *    approval. ~10KB/week growth. Read-only from API.
     */
    val MIGRATION_76_77 = object : Migration(76, 77) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_idempotency_processed_at " +
                    "ON idempotency_log(processed_at)"
            )
            db.execSQL(
                """CREATE TABLE IF NOT EXISTS finance_snapshots (
                  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                  label TEXT NOT NULL DEFAULT '',
                  scenario_key TEXT NOT NULL DEFAULT 'base',
                  scenario_json TEXT NOT NULL DEFAULT '{}',
                  model_start TEXT NOT NULL,
                  model_end TEXT NOT NULL,
                  opening_balance REAL NOT NULL DEFAULT 0,
                  total_inflow REAL NOT NULL DEFAULT 0,
                  total_outflow REAL NOT NULL DEFAULT 0,
                  financing_need REAL NOT NULL DEFAULT 0,
                  weeks_below_threshold INTEGER NOT NULL DEFAULT 0,
                  forecast_json TEXT NOT NULL,
                  approved_by TEXT NOT NULL DEFAULT '',
                  approved_at INTEGER NOT NULL
                )""".trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_finance_snapshots_approved " +
                    "ON finance_snapshots(approved_at DESC)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_finance_snapshots_scenario " +
                    "ON finance_snapshots(scenario_key, approved_at DESC)"
            )
        }
    }

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context.applicationContext,
            AppDatabase::class.java,
            AppDatabase.DATABASE_NAME
        )
            .addMigrations(MIGRATION_70_71, MIGRATION_71_72, MIGRATION_72_73, MIGRATION_73_74, MIGRATION_74_75, MIGRATION_75_76, MIGRATION_76_77)
            // Unknown historical versions fail closed; never erase financial data/Outbox.
            .build()
    }

    @Provides
    @Singleton
    fun provideRoomsDao(db: AppDatabase) = db.roomsDao()

    @Provides
    @Singleton
    fun provideBookingsDao(db: AppDatabase) = db.bookingsDao()

    @Provides
    @Singleton
    fun providePaymentsDao(db: AppDatabase) = db.paymentsDao()

    @Provides
    @Singleton
    fun provideEmployeesDao(db: AppDatabase) = db.employeesDao()

    @Provides
    @Singleton
    fun provideExpensesDao(db: AppDatabase) = db.expensesDao()

    @Provides
    @Singleton
    fun provideDebtsDao(db: AppDatabase) = db.debtsDao()

    @Provides
    @Singleton
    fun provideBookingNotesDao(db: AppDatabase) = db.bookingNotesDao()

    @Provides
    @Singleton
    fun provideShiftNotesDao(db: AppDatabase) = db.shiftNotesDao()

    @Provides
    @Singleton
    fun provideOutboxDao(db: AppDatabase) = db.outboxDao()

    @Provides
    @Singleton
    fun provideInventoryDao(db: AppDatabase) = db.inventoryDao()

    @Provides
    @Singleton
    fun provideSalaryWithdrawalsDao(db: AppDatabase) = db.salaryWithdrawalsDao()

    @Provides
    @Singleton
    fun provideBookingNightsDao(db: AppDatabase) = db.bookingNightsDao()

    @Provides
    @Singleton
    fun provideHotelDayLedgerDao(db: AppDatabase) = db.hotelDayLedgerDao()

    @Provides
    @Singleton
    fun providePriceAdjustmentsDao(db: AppDatabase) = db.priceAdjustmentsDao()

    @Provides
    @Singleton
    fun provideBookingPriceAdjustmentsDao(db: AppDatabase) = db.bookingPriceAdjustmentsDao()

    @Provides
    @Singleton
    fun providePaymentVoidsDao(db: AppDatabase) = db.paymentVoidsDao()

    @Provides
    @Singleton
    fun provideGuestInfosDao(db: AppDatabase) = db.guestInfosDao()

    @Provides
    @Singleton
    fun provideSalaryCyclesDao(db: AppDatabase) = db.salaryCyclesDao()

    @Provides
    @Singleton
    fun provideSalaryPaymentsDao(db: AppDatabase) = db.salaryPaymentsDao()

    @Provides
    @Singleton
    fun provideSalaryCarryOverLogsDao(db: AppDatabase) = db.salaryCarryOverLogsDao()

    @Provides
    @Singleton
    fun provideBlacklistEntriesDao(db: AppDatabase) = db.blacklistEntriesDao()

    @Provides
    @Singleton
    fun provideAuditLogsDao(db: AppDatabase) = db.auditLogsDao()

    @Provides
    @Singleton
    fun provideCashTransactionsDao(db: AppDatabase) = db.cashTransactionsDao()

    @Provides
    @Singleton
    fun provideAutoFixRunsDao(db: AppDatabase) = db.autoFixRunsDao()

    @Provides
    @Singleton
    fun provideIntegrityViolationsDao(db: AppDatabase) = db.integrityViolationsDao()

    @Provides
    @Singleton
    fun provideAppSessionsDao(db: AppDatabase) = db.appSessionsDao()

    @Provides
    @Singleton
    fun provideRestoreFixLogDao(db: AppDatabase) = db.restoreFixLogDao()

    @Provides
    @Singleton
    fun provideSyncQueueDao(db: AppDatabase) = db.syncQueueDao()

    @Provides
    @Singleton
    fun provideSyncLogDao(db: AppDatabase) = db.syncLogDao()

    @Provides
    @Singleton
    fun provideSyncConflictsDao(db: AppDatabase) = db.syncConflictsDao()

    @Provides
    @Singleton
    fun provideAncestorCacheDao(db: AppDatabase) = db.ancestorCacheDao()

    @Provides
    @Singleton
    fun provideSyncRemoteMetaDao(db: AppDatabase) = db.syncRemoteMetaDao()

    @Provides
    @Singleton
    fun provideAppUsersDao(db: AppDatabase) = db.appUsersDao()

    @Provides
    @Singleton
    fun provideDevicesDao(db: AppDatabase) = db.devicesDao()
}
