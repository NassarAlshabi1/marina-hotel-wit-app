/// ============================================================
/// Marina Hotel - Local DB vs Appwrite Comparison
/// ============================================================
/// Compares local database tables with Appwrite collections
/// ============================================================

class SyncComparison {
  /// === LOCAL DATABASE (local_db.dart) - 28 Tables ===
  static const List<String> localTables = [
    'Rooms',              // 1
    'Bookings',           // 2
    'BookingNotes',       // 3
    'Employees',         // 4
    'Expenses',          // 5
    'CashTransactions',  // 6
    'Payments',         // 7
    'Debts',            // 8
    'ShiftNotes',       // 9
    'BookingNights',    // 10
    'HotelDayLedger',   // 11
    'PriceAdjustments',  // 12
    'BookingPriceAdjustments', // 13
    'AuditLogs',        // 14
    'PaymentVoids',     // 15
    'GuestInfos',       // 16
    'AutoFixRuns',      // 17 ⚠️ Local only
    'IntegrityViolations', // 18 ⚠️ Local only
    'AppSessions',     // 19 ⚠️ Local only
    'SalaryCycles',    // 20
    'SalaryPayments', // 21
    'SalaryWithdrawals', // 22
    'Outbox',         // 23 ⚠️ Local only
    'SyncState',       // 24 ⚠️ Local only
    'RestoreFixLog',  // 25 ⚠️ Local only
    'SyncQueue',      // 26 ⚠️ Local only
    'SyncLog',       // 27 ⚠️ Local only
    'SyncConflicts',  // 28 ⚠️ Local only
  ];

  /// === APPWRITE COLLECTIONS - 22 Collections ===
  static const List<String> appwriteCollections = [
    // Core (6)
    'rooms',              'bookings',     'payments',
    'expenses',           'employees',   'debts',
    // Extended (13)
    'booking_notes',       'cash_transactions',   'booking_nights',
    'hotel_day_ledger',  'salary_cycles',    'salary_payments',
    'salary_withdrawals', 'shift_notes',      'price_adjustments',
    'booking_price_adjustments', 'audit_logs', 'payment_voids',
    'guest_infos',
    // Additional (3)
    'devices',           'sync_logs',     'blacklist',
  ];

  /// === SYNCED TO APPWRITE (20) ===
  static const List<String> syncedToAppwrite = [
    // ✅ Synced
    'rooms',              'bookings',
    'payments',           'expenses',
    'employees',         'debts',
    'booking_notes',      'cash_transactions',
    'booking_nights',   'hotel_day_ledger',
    'salary_cycles',   'salary_payments',
    'salary_withdrawals', 'shift_notes',
    'price_adjustments', 'booking_price_adjustments',
    'audit_logs',     'payment_voids',
    'guest_infos',
  ];

  /// === NOT SYNCED (8) - Local Only ===
  static const List<String> notSynced = [
    'AutoFixRuns',        // Sync tracking
    'IntegrityViolations', // Debug
    'AppSessions',       // Session tracking
    'Outbox',          // Pending sync queue
    'SyncState',        // Sync state
    'RestoreFixLog',    // Restore logs
    'SyncQueue',       // Sync queue
    'SyncLog',         // Sync history
    'SyncConflicts',   // Conflict tracking
    'devices',        // Maybe
    'sync_logs',       // Maybe
    'blacklist',       // Maybe
  ];

  static void printComparison() {
    print('═' * 60);
    print('🔄 Local DB vs Appwrite - Sync Comparison');
    print('═' * 60);
    print('');

    // Local DB
    print('━━ LOCAL DATABASE (${localTables.length} tables) ━━');
    print('  Used: ${localTables.length - 3} tables');
    print('');
    
    // Appwrite
    print('━━ APPWRITE (${appwriteCollections.length} collections) ━━');
    print('  Created: ${appwriteCollections.length} collections');
    print('');

    // Synced
    print('━━ ✅ SYNCED TO APPWRITE (${syncedToAppwrite.length}) ━━');
    for (final t in syncedToAppwrite) {
      print('  ✓ $t');
    }
    print('');

    // Not Synced
    print('━━ ⚠️  LOCAL ONLY (${notSynced.length}) ━━');
    for (final t in notSynced) {
      print('  • $t');
    }
    print('');

    // Summary
    print('━ SUMMARY ━');
    print('  Synced: ${syncedToAppwrite.length} collections');
    print('  Local Only: ${notSynced.length} tables');
    print('  Missing in Appwrite: Check blacklist, sync_logs, devices');
    print('═' * 60);
  }

  static void printDifference() {
    print('');
    print('━━ DIFFERENCES ━━');
    
    // Tables in local but not in Appwrite config
    final missingInAppwrite = localTables
        .map((t) => t.toLowerCase())
        .where((t) => !appwriteCollections.contains(t))
        .toList();
    
    if (missingInAppwrite.isNotEmpty) {
      print('⚠️  Tables not in Appwrite config:');
      for (final t in missingInAppwrite) {
        print('  - $t');
      }
    }
  }
}

void main() {
  SyncComparison.printComparison();
  SyncComparison.printDifference();
}