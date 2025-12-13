import 'package:drift/drift.dart';
import '../services/local_db.dart';

class DatabaseHealthChecker {
  final AppDatabase db;

  DatabaseHealthChecker(this.db);

  Future<Map<String, dynamic>> performHealthCheck() async {
    final results = <String, dynamic>{};

    try {
      results['schemaVersion'] = await _checkSchemaVersion();
      results['foreignKeys'] = await _checkForeignKeys();
      results['tables'] = await _checkTables();
      results['indexes'] = await _checkIndexes();
      results['syncFields'] = await _checkSyncFields();
      results['outbox'] = await _checkOutbox();
      results['syncState'] = await _checkSyncState();
      results['dataIntegrity'] = await _checkDataIntegrity();
      results['overall'] = 'healthy';
      results['timestamp'] = DateTime.now().toIso8601String();
    } catch (e) {
      results['overall'] = 'error';
      results['error'] = e.toString();
    }

    return results;
  }

  Future<Map<String, dynamic>> _checkSchemaVersion() async {
    return {
      'version': db.schemaVersion,
      'expected': 16,
      'status': db.schemaVersion == 16 ? 'ok' : 'outdated',
    };
  }

  Future<Map<String, dynamic>> _checkForeignKeys() async {
    final result = await db.customSelect('PRAGMA foreign_keys').get();
    final enabled = result.first.data['foreign_keys'] == 1;
    
    return {
      'enabled': enabled,
      'status': enabled ? 'ok' : 'disabled',
    };
  }

  Future<Map<String, dynamic>> _checkTables() async {
    final expectedTables = [
      'rooms',
      'bookings',
      'booking_notes',
      'employees',
      'expenses',
      'cash_transactions',
      'payments',
      'debts',
      'shift_notes',
      'booking_nights',
      'hotel_day_ledger',
      'auto_fix_runs',
      'integrity_violations',
      'app_sessions',
      'salary_cycles',
      'salary_payments',
      'outbox',
      'sync_state',
      'restore_fix_log',
      'sync_queue',
      'sync_log',
      'sync_conflicts',
    ];

    final existingTables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    ).get();

    final tableNames = existingTables.map((r) => r.data['name'] as String).toList();
    final missing = expectedTables.where((t) => !tableNames.contains(t)).toList();

    return {
      'expected': expectedTables.length,
      'found': tableNames.length,
      'missing': missing,
      'status': missing.isEmpty ? 'ok' : 'incomplete',
    };
  }

  Future<Map<String, dynamic>> _checkIndexes() async {
    final indexes = await db.customSelect(
      "SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
    ).get();

    final indexesByTable = <String, List<String>>{};
    for (final idx in indexes) {
      final table = idx.data['tbl_name'] as String;
      final name = idx.data['name'] as String;
      indexesByTable.putIfAbsent(table, () => []).add(name);
    }

    return {
      'total': indexes.length,
      'byTable': indexesByTable,
      'status': indexes.length >= 12 ? 'ok' : 'missing',
    };
  }

  Future<Map<String, dynamic>> _checkSyncFields() async {
    final tablesWithSync = [
      'rooms',
      'bookings',
      'booking_notes',
      'employees',
      'expenses',
      'cash_transactions',
      'payments',
      'debts',
      'booking_nights',
      'hotel_day_ledger',
      'salary_cycles',
      'salary_payments',
    ];

    final results = <String, bool>{};
    
    for (final table in tablesWithSync) {
      final sql = await db.customSelect(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        variables: [Variable.withString(table)],
      ).get();

      if (sql.isNotEmpty) {
        final tableSql = sql.first.data['sql'] as String;
        final hasLocalUuid = tableSql.contains('local_uuid');
        final hasServerId = tableSql.contains('server_id');
        final hasLastModified = tableSql.contains('last_modified');
        
        results[table] = hasLocalUuid && hasServerId && hasLastModified;
      } else {
        results[table] = false;
      }
    }

    final allValid = results.values.every((v) => v);

    return {
      'tables': results,
      'valid': results.values.where((v) => v).length,
      'invalid': results.values.where((v) => !v).length,
      'status': allValid ? 'ok' : 'incomplete',
    };
  }

  Future<Map<String, dynamic>> _checkOutbox() async {
    final pendingCount = await db.customSelect(
      'SELECT COUNT(*) as count FROM outbox',
    ).getSingle();

    final failedCount = await db.customSelect(
      'SELECT COUNT(*) as count FROM outbox WHERE attempts > 5',
    ).getSingle();

    final count = pendingCount.data['count'] as int;
    final failed = failedCount.data['count'] as int;

    return {
      'pending': count,
      'failed': failed,
      'status': failed > 10 ? 'warning' : 'ok',
    };
  }

  Future<Map<String, dynamic>> _checkSyncState() async {
    final states = await db.select(db.syncState).get();
    
    if (states.isEmpty) {
      return {
        'initialized': false,
        'status': 'not_initialized',
      };
    }

    final state = states.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastSync = [state.lastPullTs, state.lastPushTs].reduce((a, b) => a > b ? a : b);
    final hoursSinceSync = (now - lastSync) / (1000 * 60 * 60);

    return {
      'initialized': true,
      'lastPullTs': state.lastPullTs,
      'lastPushTs': state.lastPushTs,
      'isSyncing': state.isSyncing == 1,
      'hoursSinceLastSync': hoursSinceSync.toStringAsFixed(2),
      'status': hoursSinceSync > 24 ? 'stale' : 'ok',
    };
  }

  Future<Map<String, dynamic>> _checkDataIntegrity() async {
    final issues = <String>[];

    final orphanedPayments = await db.customSelect(
      '''
      SELECT COUNT(*) as count FROM payments 
      WHERE booking_local_id IS NOT NULL 
      AND booking_local_id NOT IN (SELECT id FROM bookings)
      ''',
    ).getSingle();

    if ((orphanedPayments.data['count'] as int) > 0) {
      issues.add('مدفوعات يتيمة (بدون حجز مرتبط)');
    }

    final bookingsWithInvalidRooms = await db.customSelect(
      '''
      SELECT COUNT(*) as count FROM bookings 
      WHERE room_number NOT IN (SELECT room_number FROM rooms)
      ''',
    ).getSingle();

    if ((bookingsWithInvalidRooms.data['count'] as int) > 0) {
      issues.add('حجوزات بأرقام غرف غير موجودة');
    }

    final duplicateUuids = await db.customSelect(
      '''
      SELECT local_uuid, COUNT(*) as count FROM (
        SELECT local_uuid FROM rooms
        UNION ALL SELECT local_uuid FROM bookings
        UNION ALL SELECT local_uuid FROM payments
      )
      GROUP BY local_uuid
      HAVING count > 1
      ''',
    ).get();

    if (duplicateUuids.isNotEmpty) {
      issues.add('UUIDs مكررة عبر الجداول');
    }

    return {
      'issues': issues,
      'status': issues.isEmpty ? 'ok' : 'warning',
    };
  }

  Future<String> generateHealthReport() async {
    final health = await performHealthCheck();
    final buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('  تقرير سلامة قاعدة البيانات');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('');
    buffer.writeln('الوقت: ${health['timestamp']}');
    buffer.writeln('الحالة العامة: ${health['overall']}');
    buffer.writeln('');
    
    buffer.writeln('─── إصدار Schema ───');
    final schema = health['schemaVersion'] as Map;
    buffer.writeln('الإصدار الحالي: ${schema['version']}');
    buffer.writeln('الإصدار المتوقع: ${schema['expected']}');
    buffer.writeln('الحالة: ${schema['status']}');
    buffer.writeln('');

    buffer.writeln('─── Foreign Keys ───');
    final fk = health['foreignKeys'] as Map;
    buffer.writeln('مفعّلة: ${fk['enabled']}');
    buffer.writeln('الحالة: ${fk['status']}');
    buffer.writeln('');

    buffer.writeln('─── الجداول ───');
    final tables = health['tables'] as Map;
    buffer.writeln('المتوقعة: ${tables['expected']}');
    buffer.writeln('الموجودة: ${tables['found']}');
    if ((tables['missing'] as List).isNotEmpty) {
      buffer.writeln('الناقصة: ${(tables['missing'] as List).join(', ')}');
    }
    buffer.writeln('الحالة: ${tables['status']}');
    buffer.writeln('');

    buffer.writeln('─── الفهارس ───');
    final indexes = health['indexes'] as Map;
    buffer.writeln('العدد الكلي: ${indexes['total']}');
    buffer.writeln('الحالة: ${indexes['status']}');
    buffer.writeln('');

    buffer.writeln('─── حقول المزامنة ───');
    final syncFields = health['syncFields'] as Map;
    buffer.writeln('الصالحة: ${syncFields['valid']}');
    buffer.writeln('غير الصالحة: ${syncFields['invalid']}');
    buffer.writeln('الحالة: ${syncFields['status']}');
    buffer.writeln('');

    buffer.writeln('─── صندوق الصادر (Outbox) ───');
    final outbox = health['outbox'] as Map;
    buffer.writeln('المعلقة: ${outbox['pending']}');
    buffer.writeln('الفاشلة: ${outbox['failed']}');
    buffer.writeln('الحالة: ${outbox['status']}');
    buffer.writeln('');

    buffer.writeln('─── حالة المزامنة ───');
    final syncState = health['syncState'] as Map;
    buffer.writeln('مهيأة: ${syncState['initialized']}');
    if (syncState['initialized'] == true) {
      buffer.writeln('جارية: ${syncState['isSyncing']}');
      buffer.writeln('منذ آخر مزامنة: ${syncState['hoursSinceLastSync']} ساعة');
    }
    buffer.writeln('الحالة: ${syncState['status']}');
    buffer.writeln('');

    buffer.writeln('─── سلامة البيانات ───');
    final integrity = health['dataIntegrity'] as Map;
    if ((integrity['issues'] as List).isEmpty) {
      buffer.writeln('✓ لا توجد مشاكل');
    } else {
      buffer.writeln('⚠ المشاكل:');
      for (final issue in integrity['issues'] as List) {
        buffer.writeln('  - $issue');
      }
    }
    buffer.writeln('الحالة: ${integrity['status']}');
    buffer.writeln('');

    buffer.writeln('═══════════════════════════════════════');
    
    return buffer.toString();
  }
}
