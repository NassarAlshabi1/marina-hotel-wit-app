// ═══════════════════════════════════════════════════════════════
//  cloudflare_config.dart — Cloudflare Worker Configuration
//  Replaces AppwriteConfig
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import '../utils/env.dart';
import 'worker_endpoints.dart';

class CloudflareConfig {
  CloudflareConfig._();

  /// ✅ (2026-09-09) Worker URL — ديناميكي الآن: يعيد النقطة الفعّالة
  /// من [WorkerEndpoints] (النطاق المخصّص للمستخدم إن وُضع، وإلا
  /// workers.dev، مع تثبيت آخر نقطة نجحت). كل بُناة الروابط في
  /// المدير/الخدمات تقرأ هذا getter — التبديل بين النقاط شفاف تماماً.
  static String get workerUrl => WorkerEndpoints.active;

  /// النطاق المدمج من بيئة البناء (workers.dev) — للعرض والتشخيص فقط.
  static String get builtinWorkerUrl => WorkerEndpoints.builtin;

  /// Login credentials — ✅ (2026-09-10) قابلة للتغطية وقت التشغيل الآن:
  /// شاشة تسجيل الدخول (CloudflareLoginScreen) تحفظ overrides في
  /// SharedPreferences فتعمل أولويةً على قيم --dart-define المدمجة.
  static String? _usernameOverride;
  static String? _passwordOverride;

  /// مفاتيح التخزين — عامة للاختبارات وشاشة الدخول (قراءة حالة موجودة).
  static const String usernameOverrideKey = 'cf_username_override';
  static const String passwordOverrideKey = 'cf_password_override';

  static String get username => _usernameOverride ?? Env.cloudflareUsername;
  static String get password => _passwordOverride ?? Env.cloudflarePassword;

  /// هل وُضعت اعتمادات مخصّصة من التطبيق (بدل المدمجة)؟
  static bool get hasCredentialOverrides =>
      _usernameOverride != null || _passwordOverride != null;

  /// تحميل الاعتمادات المخصّصة من التفضيلات — يُستدعى مرة واحدة مبكراً
  /// في main() قبل أي initialize() للمدير. fail-open: أي فشل = المدمج.
  static Future<void> loadCredentialOverrides({
    SharedPreferences? prefs,
  }) async {
    try {
      final sp = prefs ?? await SharedPreferences.getInstance();
      final u = sp.getString(usernameOverrideKey);
      final p = sp.getString(passwordOverrideKey);
      _usernameOverride = (u != null && u.trim().isNotEmpty) ? u : null;
      _passwordOverride = (p != null && p.isNotEmpty) ? p : null;
      if (hasCredentialOverrides) {
        debugPrint(
          '✅ CloudflareConfig: credential overrides loaded '
          '(username: $username)',
        );
      }
    } catch (e) {
      dwarn(() => 'CloudflareConfig.loadCredentialOverrides failed: $e');
    }
  }

  /// حفظ اعتمادات مخصّصة (من شاشة تسجيل الدخول).
  /// - [username] فارغ = إبقاء المدمج؛ [password] فارغ/null = إبقاء
  ///   المدمج أو الكلمة المحفوظة سابقاً (لا نمسحها عبثاً).
  /// - لا يرمي استثناءات على التخزين الفاشل — يحدّث الذاكرة على الأقل.
  static Future<void> setCredentialOverrides({
    String? username,
    String? password,
  }) async {
    final trimmedUser = username?.trim() ?? '';
    _usernameOverride = trimmedUser.isNotEmpty ? trimmedUser : null;
    if (password != null && password.isNotEmpty) {
      _passwordOverride = password;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      if (_usernameOverride != null) {
        await sp.setString(usernameOverrideKey, _usernameOverride!);
      } else {
        await sp.remove(usernameOverrideKey);
      }
      if (_passwordOverride != null) {
        await sp.setString(passwordOverrideKey, _passwordOverride!);
      }
    } catch (e) {
      dwarn(() => 'CloudflareConfig.setCredentialOverrides persist: $e');
    }
  }

  /// مسح الاعتمادات المخصّصة والرجوع للمدمجة (--dart-define).
  static Future<void> clearCredentialOverrides() async {
    _usernameOverride = null;
    _passwordOverride = null;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(usernameOverrideKey);
      await sp.remove(passwordOverrideKey);
    } catch (e) {
      dwarn(() => 'CloudflareConfig.clearCredentialOverrides: $e');
    }
  }

  /// Test-only: تفريغ الحالة الساكنة (توازي WorkerEndpoints.resetForTests).
  @visibleForTesting
  static void resetCredentialOverridesForTests() {
    _usernameOverride = null;
    _passwordOverride = null;
  }

  /// Entity → D1 table name mapping (1:1, same names as Drift)
  ///
  /// خطة الانتقال D7: أُضيفت inventory_items وinventory_transactions
  /// وblacklist — الثلاثة موجودة في عقد Appwrite (27 مجموعة) وكانت مفقودة
  /// من طبقة Cloudflare كاملةً، وأي سجل مخزون/قائمة سوداء كان سيُفقد صمتاً.
  ///
  /// ✅ (2026-09-05) أُضيف app_users بتعليمات المستخدم («النطاق الافتراضي
  /// المزامنة … user_app … أيضاً pull/push و outbox delta sync»):
  /// الكيان كان يُزامَن عبر Appwrite Cloud (appwrite_config.dart:116،
  /// outbox_dao.dart _entityTableMap، auth_local_store
  /// _enqueuePermissionSync) لكن طبقة Cloudflare أسقطته كلياً. المجموعة
  /// الحية موجودة في مشروع Appwrite (schema_extract.json
  /// in_valid_not_in_schema) والجدول المحلي Drift AppUsers أُضيف
  /// (local_db.dart schemaVersion 66).
  static const Map<String, String> entityToTable = {
    'rooms': 'rooms',
    'bookings': 'bookings',
    'payments': 'payments',
    'expenses': 'expenses',
    'employees': 'employees',
    'debts': 'debts',
    'booking_notes': 'booking_notes',
    'shift_notes': 'shift_notes',
    'cash_transactions': 'cash_transactions',
    'booking_nights': 'booking_nights',
    'salary_cycles': 'salary_cycles',
    'salary_payments': 'salary_payments',
    'salary_withdrawals': 'salary_withdrawals',
    'salary_carry_over_logs': 'salary_carry_over_logs',
    'price_adjustments': 'price_adjustments',
    'booking_price_adjustments': 'booking_price_adjustments',
    'audit_logs': 'audit_logs',
    'payment_voids': 'payment_voids',
    'guest_infos': 'guest_infos',
    'inventory_items': 'inventory_items',
    'inventory_transactions': 'inventory_transactions',
    'app_users': 'app_users',
    'devices': 'devices',
    'blacklist': 'blacklist',
  };

  /// Tables to migrate (ordered by FK dependency — topological sort)
  /// Parent tables must be migrated before child tables that reference them.
  /// Order:
  ///   1. rooms, employees (no FK deps)
  ///   2. salary_cycles (deps: employees)
  ///   3. cash_transactions (no FK deps)
  ///   4. bookings (deps: rooms)
  ///   5. guest_infos (no FK deps)
  ///   6. booking_notes, booking_nights, booking_price_adjustments (deps: bookings)
  ///   7. payments (deps: bookings, cash_transactions)
  ///   8. expenses (deps: cash_transactions)
  ///   9. debts (deps: bookings)
  ///  10. salary_payments (deps: salary_cycles, employees)
  ///  11. salary_withdrawals (deps: employees, expenses)
  ///  12. salary_carry_over_logs (deps: employees)
  ///  13. audit_logs, payment_voids, shift_notes, price_adjustments
  ///  14. inventory_items (no FK deps) → inventory_transactions (deps:
  ///      inventory_items via item_local_uuid/item_id)
  ///  15. app_users (no FK deps — local Drift table AppUsers,
  ///      schemaVersion 66)
  ///  16. devices (no FK deps — local Drift table Devices,
  ///      schemaVersion 67; يستبدل مجموعة devices في Appwrite)
  ///  17. blacklist (cloud-only, no deps)
  static const List<String> migrationOrder = [
    'rooms',
    'employees',
    'salary_cycles',
    'cash_transactions',
    'bookings',
    'guest_infos',
    'booking_notes',
    'booking_nights',
    'booking_price_adjustments',
    'payments',
    'expenses',
    'debts',
    'salary_payments',
    'salary_withdrawals',
    'salary_carry_over_logs',
    'audit_logs',
    'payment_voids',
    'shift_notes',
    'price_adjustments',
    'inventory_items',
    'inventory_transactions',
    'app_users',
    'devices',
    'blacklist',
  ];

  static String? tableNameFor(String entity) => entityToTable[entity];

  /// نطاق النسخ الاحتياطي إلى Cloudflare D1 (تبويب رفع D1) = كيانات
  /// النطاق الافتراضي للمزامنة ([migrationOrder] — 24 كياناً).
  ///
  /// - النطاق الافتراضي المزامنة بتأكيد المستخدم (2026-09-05): rooms،
  ///   bookings، booking_nights، booking_notes، payments، payment_voids،
  ///   user_app (app_users)، price_adjustments،
  ///   booking_price_adjustments، expenses، debts، employees،
  ///   guest_infos، cash_transactions، shift_notes، salary_cycles،
  ///   salary_payments، salary_withdrawals، salary_carry_over_logs،
  ///   audit_logs، inventory_items، inventory_transactions — ومعها
  ///   blacklist (طلب صريح سابق من المستخدم ولم يسحبه؛ تجسيد افتراضي
  ///   من shift_notes الموسومة).
  /// - `blacklist` ضمن القائمة (كيان من عقد Appwrite) لكن بلا جدول
  ///   Drift محلي — صفوفها مخزنة في shift_notes الموسومة
  ///   created_by='blacklist' وتُجسَّد افتراضياً عند الرفع عبر
  ///   CloudflareD1Service.blacklistRowFromShiftNote.
  /// - `app_users` له جدول Drift محلي الآن (AppUsers، schemaVersion 66)
  ///   فيمرّ عبر الفلترة الفيزيائية كأي جدول.
  /// - `hotel_day_ledger` مستبعد عمداً (تأكيد المستخدم 2026-09-05:
  ///   «جدول محلي لا أريد أن يتم مزامنته») — محلي-فقط بالتصميم (D8)
  ///   ولا مقابل له في Appwrite Cloud، ويبقى محلياً كلياً.
  static const List<String> d1BackupTables = migrationOrder;

  /// وسم تخزين القائمة السوداء داخل جدول shift_notes المحلي
  /// (مطابق لـ BlacklistRepository._createdByTag — منع تكرار السلسلة
  /// النصية في استعلامات النطاق).
  static const String blacklistStorageTag = 'blacklist';

  /// Sync settings
  static const Duration syncInterval = Duration(minutes: 15);

  /// عدد الصفوف المطلوبة في كل صفحة pull من D1.
  /// ✅ (2026-09-08) رُفع من 25 إلى 100: الـ worker يضيف حدود الطلب إلى
  /// استعلام SQL مباشرة (بلا سقف خادمي) وأداء D1 على صفحات 100 ممتاز؛
  /// هذا يقلّص full sync (~7,300 صف) من ~292 طلباً إلى ~73 طلباً —
  /// أسرع بـ 4 مرات وبتكلفة requests أقل على الخطة المجانية.
  /// ملاحظة: worker يطبّق boundary-extension فيمكن أن تعيد الصفحة أكثر
  /// من [batchSize] صفاً عند تساوي updated_at على الحد — مقصود ولحماية
  /// الصفوف مكررة الطابع من الفقد.
  static const int batchSize = 100;

  /// ✅ (2026-09-09) صفحة السحب الكامل — أكبر من صفحة الدلتا (طلب
  /// المستخدم: تسريع السحب الكامل عند أول تثبيت): ~7,300 صف ≈ 18
  /// طلباً بدل 73. السقف الخادمي للسحب MAX_PULL_BATCH_SIZE=500،
  /// والدلتا تبقى [batchSize] (طلبات متكررة خفيفة).
  static const int fullPullBatchSize = 400;
}
