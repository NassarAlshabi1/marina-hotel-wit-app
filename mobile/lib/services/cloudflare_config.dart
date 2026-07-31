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
  };

  /// Tables to migrate (ordered by dependency)
  static const List<String> migrationOrder = [
    'rooms',
    'employees',
    'bookings',
    'payments',
    'expenses',
    'debts',
    'booking_nights',
    'booking_price_adjustments',
    'guest_infos',
    'salary_withdrawals',
    'shift_notes',
    'cash_transactions',
    'booking_notes',
    'price_adjustments',
    'audit_logs',
    'payment_voids',
    'salary_cycles',
    'salary_payments',
    'salary_carry_over_logs',
  ];

  static String? tableNameFor(String entity) => entityToTable[entity];

  /// Sync settings
  static const Duration syncInterval = Duration(minutes: 15);
  static const int batchSize = 25;
}
