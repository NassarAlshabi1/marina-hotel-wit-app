// ═══════════════════════════════════════════════════════════════
//  cloudflare_config.dart — Cloudflare Worker Configuration
//  Replaces AppwriteConfig
// ═══════════════════════════════════════════════════════════════

import '../utils/env.dart';

class CloudflareConfig {
  CloudflareConfig._();

  /// Worker URL
  static String get workerUrl => Env.cloudflareWorkerUrl;

  /// Login credentials
  static String get username => Env.cloudflareUsername;
  static String get password => Env.cloudflarePassword;

  /// Entity → D1 table name mapping (1:1, same names as Drift)
  ///
  /// خطة الانتقال D7: أُضيفت inventory_items وinventory_transactions
  /// وblacklist — الثلاثة موجودة في عقد Appwrite (27 مجموعة) وكانت مفقودة
  /// من طبقة Cloudflare كاملةً، وأي سجل مخزون/قائمة سوداء كان سيُفقد صمتاً.
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
  ///  15. blacklist (cloud-only, no deps)
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
    'blacklist',
  ];

  static String? tableNameFor(String entity) => entityToTable[entity];

  /// Sync settings
  static const Duration syncInterval = Duration(minutes: 15);
  static const int batchSize = 25;
}
