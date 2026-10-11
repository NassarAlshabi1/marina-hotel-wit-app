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
     * Parity unification: ports branch2's worker migration 0009
     * (finance_snapshots table) to the local Room schema.
     *
     * NOTE: branch2's worker migration 0008 (idx_idempotency_processed_at)
     * is intentionally NOT ported here — `idempotency_log` is a Worker/D1
     * table only, not a Room entity on Android. The Android client never
     * stores idempotency keys locally (they live on the server). The
     * Worker applies 0008 to D1 independently via its own migration
     * pipeline; the Android side only mirrors tables that are Room
     * entities in AppDatabase.kt.
     *
     * Pure additive — no financial rewrite, no row mutation.
     * Mirrors worker/migrations/0009_finance_snapshots.sql.
     */
    val MIGRATION_76_77 = object : Migration(76, 77) {
        override fun migrate(db: SupportSQLiteDatabase) {
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
                    "ON finance_snapshots(approved_at)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_finance_snapshots_scenario " +
                    "ON finance_snapshots(scenario_key, approved_at)"
            )
        }
    }

    /**
     * Migration 77 → 78: custom_list_items (قوائم ديناميكية) + withdrawal_uuid
     * للمصروفات + مواءمة blacklist_entries مع Flutter (المرجع).
     *
     * ملاحظات تحقّق المخطط (Room يقارن الجدول الفعلي بالكيان بعد الهجرة):
     *  • الجداول/الأعمدة الجديدة تُنشأ هنا، وكل فهرس معلن في @Entity يجب
     *    إنشاؤه هنا أيضاً (وإلا: "Migration didn't properly handle").
     *  • `added_by`/`added_date` كانا يُضافان في MIGRATION_75_76 ثم حُذفا من
     *    الكيان لمواءمة Flutter — أي عمود زائد في الجدول الفعلي يُفشل التحقق،
     *    فتُعاد بناء الجدول بدونهما (SQLite على minSdk 26 بلا DROP COLUMN).
     *  • بلا بذر بيانات: القوائم تملأ من المزامنة أو إدخال المستخدم.
     */
    val MIGRATION_77_78 = object : Migration(77, 78) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                // الأنواع/القيود مطابقة لما يولّده Room من CustomListItemEntity —
                // بلا DEFAULT لأن الكيان لا يعلن @ColumnInfo(defaultValue=…).
                """CREATE TABLE IF NOT EXISTS custom_list_items (
                  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                  list_key TEXT NOT NULL,
                  name TEXT NOT NULL,
                  sort_order INTEGER NOT NULL,
                  is_active INTEGER NOT NULL,
                  is_system INTEGER NOT NULL,
                  local_uuid TEXT NOT NULL,
                  server_id INTEGER,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  last_modified INTEGER NOT NULL,
                  created_at_iso TEXT,
                  updated_at_iso TEXT,
                  deleted_at_iso TEXT,
                  created_at_epoch INTEGER NOT NULL,
                  last_modified_epoch INTEGER NOT NULL,
                  version INTEGER NOT NULL,
                  origin TEXT NOT NULL,
                  vector_clock TEXT NOT NULL,
                  device_id TEXT NOT NULL,
                  sync_timestamp INTEGER NOT NULL,
                  idempotency_key TEXT
                )""".trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_custom_list_key_order " +
                    "ON custom_list_items(list_key, sort_order)"
            )
            db.execSQL(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_list_key_name " +
                    "ON custom_list_items(list_key, name) WHERE deleted_at IS NULL"
            )

            // Add withdrawal_uuid column to expenses table (parity with Flutter)
            db.execSQL("ALTER TABLE expenses ADD COLUMN withdrawal_uuid TEXT")
            // فهرس ExpenseEntity idx_expenses_withdrawal_uuid — مطلوب للتحقق.
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_expenses_withdrawal_uuid " +
                    "ON expenses(withdrawal_uuid)"
            )

            // ── blacklist_entries: إزالة added_by/added_date وبناء الفهارس ──
            db.execSQL(
                """CREATE TABLE blacklist_entries_new (
                  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                  name TEXT NOT NULL,
                  nationality TEXT,
                  national_id TEXT,
                  phone TEXT,
                  reason TEXT,
                  notes TEXT,
                  reported_by TEXT NOT NULL,
                  active INTEGER NOT NULL,
                  local_uuid TEXT NOT NULL,
                  server_id INTEGER,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL,
                  deleted_at INTEGER,
                  last_modified INTEGER NOT NULL,
                  created_at_iso TEXT,
                  updated_at_iso TEXT,
                  deleted_at_iso TEXT,
                  created_at_epoch INTEGER NOT NULL,
                  last_modified_epoch INTEGER NOT NULL,
                  version INTEGER NOT NULL,
                  origin TEXT NOT NULL,
                  vector_clock TEXT NOT NULL,
                  device_id TEXT NOT NULL,
                  sync_timestamp INTEGER NOT NULL,
                  idempotency_key TEXT
                )""".trimIndent()
            )
            db.execSQL(
                """INSERT INTO blacklist_entries_new (
                  id, name, nationality, national_id, phone, reason, notes,
                  reported_by, active, local_uuid, server_id, created_at,
                  updated_at, deleted_at, last_modified, created_at_iso,
                  updated_at_iso, deleted_at_iso, created_at_epoch,
                  last_modified_epoch, version, origin, vector_clock,
                  device_id, sync_timestamp, idempotency_key
                ) SELECT
                  id, name, nationality, national_id, phone, reason, notes,
                  reported_by, active, local_uuid, server_id, created_at,
                  updated_at, deleted_at, last_modified, created_at_iso,
                  updated_at_iso, deleted_at_iso, created_at_epoch,
                  last_modified_epoch, version, origin, vector_clock,
                  device_id, sync_timestamp, idempotency_key
                FROM blacklist_entries""".trimIndent()
            )
            db.execSQL("DROP TABLE blacklist_entries")
            db.execSQL(
                "ALTER TABLE blacklist_entries_new RENAME TO blacklist_entries"
            )
            // فهارس BlacklistEntryEntity (معلنة في الكيان منذ مواءمة Flutter).
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_blacklist_entries_active " +
                    "ON blacklist_entries(active) WHERE deleted_at IS NULL"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_blacklist_entries_search " +
                    "ON blacklist_entries(name, phone, national_id, nationality) " +
                    "WHERE deleted_at IS NULL AND active = 1"
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
            .addMigrations(MIGRATION_70_71, MIGRATION_71_72, MIGRATION_72_73, MIGRATION_73_74, MIGRATION_74_75, MIGRATION_75_76, MIGRATION_76_77, MIGRATION_77_78)
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

    @Provides
    @Singleton
    fun provideCustomListsDao(db: AppDatabase) = db.customListsDao()
}
