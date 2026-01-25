import 'package:drift/drift.dart';
import 'local_db.dart';

enum IssueType {
  orphanedRecord,
  duplicateUuid,
  versionInconsistency,
  amountMismatch,
  missingReference,
  invalidStatus,
}

class IntegrityIssue {
  final IssueType type;
  final String table;
  final String? uuid;
  final String description;
  final Map<String, dynamic>? metadata;
  final bool isCritical;

  IntegrityIssue({
    required this.type,
    required this.table,
    this.uuid,
    required this.description,
    this.metadata,
    this.isCritical = false,
  });

  @override
  String toString() =>
      'IntegrityIssue($type): $table${uuid != null ? '/$uuid' : ''} - $description';

  String toArabicMessage() {
    switch (type) {
      case IssueType.orphanedRecord:
        return 'سجل يتيم: $description';
      case IssueType.duplicateUuid:
        return 'معرّف مكرر: $description';
      case IssueType.versionInconsistency:
        return 'عدم تطابق في الإصدار: $description';
      case IssueType.amountMismatch:
        return 'عدم تطابق في المبالغ: $description';
      case IssueType.missingReference:
        return 'مرجع مفقود: $description';
      case IssueType.invalidStatus:
        return 'حالة غير صالحة: $description';
    }
  }
}

class IntegrityReport {
  final List<IntegrityIssue> issues;
  final DateTime timestamp;
  final Duration checkDuration;

  IntegrityReport({
    required this.issues,
    required this.timestamp,
    Duration? checkDuration,
  }) : checkDuration = checkDuration ?? Duration.zero;

  bool get hasIssues => issues.isNotEmpty;
  bool get hasCriticalIssues => issues.any((i) => i.isCritical);
  int get issueCount => issues.length;
  int get criticalIssueCount => issues.where((i) => i.isCritical).length;

  Map<IssueType, int> get issuesByType {
    final map = <IssueType, int>{};
    for (final issue in issues) {
      map[issue.type] = (map[issue.type] ?? 0) + 1;
    }
    return map;
  }

  @override
  String toString() {
    return 'IntegrityReport: ${issues.length} issues found '
        '(${criticalIssueCount} critical) at ${timestamp.toIso8601String()}';
  }
}

class SyncIntegrityChecker {
  static final instance = SyncIntegrityChecker._();
  SyncIntegrityChecker._();

  Future<IntegrityReport> verify(AppDatabase db) async {
    final startTime = DateTime.now();
    final issues = <IntegrityIssue>[];

    issues.addAll(await _checkOrphanedPayments(db));
    issues.addAll(await _checkOrphanedDebts(db));
    issues.addAll(await _checkDuplicateUuids(db));
    issues.addAll(await _checkVersionConsistency(db));
    issues.addAll(await _checkBookingAmounts(db));
    issues.addAll(await _checkPaymentBookingReferences(db));
    issues.addAll(await _checkDebtBookingReferences(db));

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    return IntegrityReport(
      issues: issues,
      timestamp: endTime,
      checkDuration: duration,
    );
  }

  Future<List<IntegrityIssue>> _checkOrphanedPayments(AppDatabase db) async {
    final issues = <IntegrityIssue>[];

    final orphaned = await db.customSelect('''
      SELECT p.local_uuid, p.booking_local_id 
      FROM payments p
      LEFT JOIN bookings b ON p.booking_local_id = b.id
      WHERE p.booking_local_id IS NOT NULL 
        AND b.id IS NULL 
        AND p.deleted_at IS NULL
    ''').get();

    for (final row in orphaned) {
      issues.add(
        IntegrityIssue(
          type: IssueType.orphanedRecord,
          table: 'payments',
          uuid: row.read<String>('local_uuid'),
          description:
              'Payment without associated booking (booking_local_id: ${row.read<int?>('booking_local_id')})',
          isCritical: true,
        ),
      );
    }

    return issues;
  }

  Future<List<IntegrityIssue>> _checkOrphanedDebts(AppDatabase db) async {
    final issues = <IntegrityIssue>[];

    final orphaned = await db.customSelect('''
      SELECT d.local_uuid, d.booking_local_id
      FROM debts d
      LEFT JOIN bookings b ON d.booking_local_id = b.id
      WHERE d.booking_local_id IS NOT NULL
        AND b.id IS NULL
        AND d.deleted_at IS NULL
    ''').get();

    for (final row in orphaned) {
      issues.add(
        IntegrityIssue(
          type: IssueType.orphanedRecord,
          table: 'debts',
          uuid: row.read<String>('local_uuid'),
          description:
              'Debt without associated booking (booking_local_id: ${row.read<int?>('booking_local_id')})',
          isCritical: true,
        ),
      );
    }

    return issues;
  }

  Future<List<IntegrityIssue>> _checkDuplicateUuids(AppDatabase db) async {
    final issues = <IntegrityIssue>[];

    final tables = [
      'bookings',
      'payments',
      'rooms',
      'expenses',
      'debts',
      'employees',
      'booking_notes',
    ];

    for (final table in tables) {
      final duplicates = await db.customSelect('''
        SELECT local_uuid, COUNT(*) as count
        FROM $table
        WHERE deleted_at IS NULL
        GROUP BY local_uuid
        HAVING COUNT(*) > 1
      ''').get();

      for (final row in duplicates) {
        final uuid = row.read<String>('local_uuid');
        final count = row.read<int>('count');

        issues.add(
          IntegrityIssue(
            type: IssueType.duplicateUuid,
            table: table,
            uuid: uuid,
            description: 'Duplicate UUID found $count times',
            isCritical: true,
          ),
        );
      }
    }

    return issues;
  }

  Future<List<IntegrityIssue>> _checkVersionConsistency(AppDatabase db) async {
    final issues = <IntegrityIssue>[];

    final tables = [
      'bookings',
      'payments',
      'rooms',
      'expenses',
      'debts',
      'employees',
    ];

    for (final table in tables) {
      final invalidVersions = await db.customSelect('''
        SELECT local_uuid, version
        FROM $table
        WHERE version < 1 OR version IS NULL
      ''').get();

      for (final row in invalidVersions) {
        issues.add(
          IntegrityIssue(
            type: IssueType.versionInconsistency,
            table: table,
            uuid: row.read<String>('local_uuid'),
            description: 'Invalid version: ${row.read<int?>('version')}',
            isCritical: false,
          ),
        );
      }
    }

    return issues;
  }

  Future<List<IntegrityIssue>> _checkBookingAmounts(AppDatabase db) async {
    final issues = <IntegrityIssue>[];

    final mismatches = await db.customSelect('''
      SELECT 
        b.local_uuid,
        b.total_due_cached,
        b.total_paid_cached,
        b.remaining_balance_cached,
        COALESCE(SUM(p.amount), 0) as actual_paid
      FROM bookings b
      LEFT JOIN payments p ON p.booking_local_id = b.id AND p.deleted_at IS NULL
      WHERE b.deleted_at IS NULL
      GROUP BY b.id, b.local_uuid, b.total_due_cached, b.total_paid_cached, b.remaining_balance_cached
      HAVING ABS(b.total_paid_cached - actual_paid) > 0.01
    ''').get();

    for (final row in mismatches) {
      final uuid = row.read<String>('local_uuid');
      final cachedPaid = row.read<double?>('total_paid_cached') ?? 0.0;
      final actualPaid = row.read<double>('actual_paid');

      issues.add(
        IntegrityIssue(
          type: IssueType.amountMismatch,
          table: 'bookings',
          uuid: uuid,
          description:
              'Payment amount mismatch: cached=$cachedPaid, actual=$actualPaid',
          metadata: {
            'cached_paid': cachedPaid,
            'actual_paid': actualPaid,
            'difference': (cachedPaid - actualPaid).abs(),
          },
          isCritical: true,
        ),
      );
    }

    return issues;
  }

  Future<List<IntegrityIssue>> _checkPaymentBookingReferences(
    AppDatabase db,
  ) async {
    final issues = <IntegrityIssue>[];

    final invalidRefs = await db.customSelect('''
      SELECT p.local_uuid, p.booking_local_id
      FROM payments p
      WHERE p.booking_local_id IS NOT NULL
        AND p.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM bookings b 
          WHERE b.id = p.booking_local_id 
          AND b.deleted_at IS NULL
        )
    ''').get();

    for (final row in invalidRefs) {
      issues.add(
        IntegrityIssue(
          type: IssueType.missingReference,
          table: 'payments',
          uuid: row.read<String>('local_uuid'),
          description:
              'Payment references non-existent or deleted booking (id: ${row.read<int?>('booking_local_id')})',
          isCritical: true,
        ),
      );
    }

    return issues;
  }

  Future<List<IntegrityIssue>> _checkDebtBookingReferences(
    AppDatabase db,
  ) async {
    final issues = <IntegrityIssue>[];

    final invalidRefs = await db.customSelect('''
      SELECT d.local_uuid, d.booking_local_id
      FROM debts d
      WHERE d.booking_local_id IS NOT NULL
        AND d.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM bookings b 
          WHERE b.id = d.booking_local_id 
          AND b.deleted_at IS NULL
        )
    ''').get();

    for (final row in invalidRefs) {
      issues.add(
        IntegrityIssue(
          type: IssueType.missingReference,
          table: 'debts',
          uuid: row.read<String>('local_uuid'),
          description:
              'Debt references non-existent or deleted booking (id: ${row.read<int?>('booking_local_id')})',
          isCritical: true,
        ),
      );
    }

    return issues;
  }

  Future<void> fixIssue(AppDatabase db, IntegrityIssue issue) async {
    switch (issue.type) {
      case IssueType.orphanedRecord:
        await _fixOrphanedRecord(db, issue);
        break;
      case IssueType.versionInconsistency:
        await _fixVersionInconsistency(db, issue);
        break;
      case IssueType.amountMismatch:
        await _fixAmountMismatch(db, issue);
        break;
      default:
        throw UnsupportedError('Cannot auto-fix issue type: ${issue.type}');
    }
  }

  Future<void> _fixOrphanedRecord(AppDatabase db, IntegrityIssue issue) async {
    await db.customStatement(
      '''
      UPDATE ${issue.table}
      SET deleted_at = ?
      WHERE local_uuid = ?
    ''',
      [DateTime.now().millisecondsSinceEpoch ~/ 1000, issue.uuid],
    );
  }

  Future<void> _fixVersionInconsistency(
    AppDatabase db,
    IntegrityIssue issue,
  ) async {
    await db.customStatement(
      '''
      UPDATE ${issue.table}
      SET version = 1
      WHERE local_uuid = ? AND (version IS NULL OR version < 1)
    ''',
      [issue.uuid],
    );
  }

  Future<void> _fixAmountMismatch(AppDatabase db, IntegrityIssue issue) async {
    if (issue.table != 'bookings' || issue.uuid == null) return;

    final actualPaid = issue.metadata?['actual_paid'] as double? ?? 0.0;

    final booking = await (db.select(
      db.bookings,
    )..where((t) => t.localUuid.equals(issue.uuid!))).getSingleOrNull();

    if (booking == null) return;

    final totalDue = booking.totalDueCached;
    final remaining = totalDue - actualPaid;

    await (db.update(
      db.bookings,
    )..where((t) => t.localUuid.equals(issue.uuid!))).write(
      BookingsCompanion(
        totalPaidCached: Value(actualPaid),
        remainingBalanceCached: Value(remaining),
        isFullyPaid: Value(remaining <= 0.01),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }
}
