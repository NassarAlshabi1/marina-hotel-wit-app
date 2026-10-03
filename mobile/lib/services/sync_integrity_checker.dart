import 'package:drift/drift.dart';
import 'enhanced_booking_calculation_service.dart';
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
  IntegrityIssue({
    required this.type,
    required this.table,
    required this.description,
    this.uuid,
    this.metadata,
    this.isCritical = false,
  });
  final IssueType type;
  final String table;
  final String? uuid;
  final String description;
  final Map<String, dynamic>? metadata;
  final bool isCritical;

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
  IntegrityReport({
    required this.issues,
    required this.timestamp,
    Duration? checkDuration,
  }) : checkDuration = checkDuration ?? Duration.zero;
  final List<IntegrityIssue> issues;
  final DateTime timestamp;
  final Duration checkDuration;

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
        '($criticalIssueCount critical) at ${timestamp.toIso8601String()}';
  }
}

class SyncIntegrityChecker {
  SyncIntegrityChecker._();
  static final instance = SyncIntegrityChecker._();

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
    issues.addAll(await _checkOrphanedSalaryWithdrawals(db));
    issues.addAll(await _checkOrphanedSalaryCycles(db));
    issues.addAll(await _checkOrphanedSalaryPayments(db));
    issues.addAll(await _checkOrphanedPendingLinks(db));

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
      case IssueType.versionInconsistency:
        await _fixVersionInconsistency(db, issue);
      case IssueType.amountMismatch:
        await _fixAmountMismatch(db, issue);
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
    if (issue.table != 'bookings' || issue.uuid == null) {
      return;
    }

    final booking = await (db.select(
      db.bookings,
    )..where((t) => t.localUuid.equals(issue.uuid!))).getSingleOrNull();

    if (booking == null) {
      return;
    }

    // إعادة حساب كاملة بدلاً من الاعتماد على القيم المخزنة مؤقتاً (stale)
    final calcService = EnhancedBookingCalculationService(db);
    final calculation = await calcService.calculateForBooking(booking);
    final summary = calculation.financialSummary;

    await (db.update(
      db.bookings,
    )..where((t) => t.localUuid.equals(issue.uuid!))).write(
      BookingsCompanion(
        totalDueCached: Value(summary.totalDue.toDouble()),
        totalPaidCached: Value(summary.totalPaid.toDouble()),
        remainingBalanceCached: Value(summary.remainingBalance.toDouble()),
        isFullyPaid: Value(summary.isFullyPaid),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
      ),
    );
  }
}

/// التحقق من سحوبات الرواتب اليتيمة (تشير لموظف محذوف أو غير موجود)
Future<List<IntegrityIssue>> _checkOrphanedSalaryWithdrawals(AppDatabase db) async {
  final issues = <IntegrityIssue>[];

  final orphaned = await db.customSelect('''
    SELECT sw.local_uuid, sw.employee_id, sw.employee_uuid
    FROM salary_withdrawals sw
    LEFT JOIN employees e ON sw.employee_id = e.id
    WHERE sw.employee_id IS NOT NULL
      AND sw.deleted_at IS NULL
      AND (e.id IS NULL OR e.deleted_at IS NOT NULL)
  ''').get();

  for (final row in orphaned) {
    issues.add(
      IntegrityIssue(
        type: IssueType.orphanedRecord,
        table: 'salary_withdrawals',
        uuid: row.read<String>('local_uuid'),
        description:
            'Salary withdrawal references non-existent or deleted employee (employee_id: ${row.read<int?>('employee_id')}, employee_uuid: ${row.read<String?>('employee_uuid')})',
        isCritical: true,
      ),
    );
  }

  return issues;
}

/// التحقق من دورات الرواتب اليتيمة
Future<List<IntegrityIssue>> _checkOrphanedSalaryCycles(AppDatabase db) async {
  final issues = <IntegrityIssue>[];

  final orphaned = await db.customSelect('''
    SELECT sc.local_uuid, sc.employee_id, sc.employee_uuid
    FROM salary_cycles sc
    LEFT JOIN employees e ON sc.employee_id = e.id
    WHERE sc.employee_id IS NOT NULL
      AND sc.deleted_at IS NULL
      AND (e.id IS NULL OR e.deleted_at IS NOT NULL)
  ''').get();

  for (final row in orphaned) {
    issues.add(
      IntegrityIssue(
        type: IssueType.orphanedRecord,
        table: 'salary_cycles',
        uuid: row.read<String>('local_uuid'),
        description:
            'Salary cycle references non-existent or deleted employee (employee_id: ${row.read<int?>('employee_id')}, employee_uuid: ${row.read<String?>('employee_uuid')})',
        isCritical: true,
      ),
    );
  }

  return issues;
}

/// التحقق من مدفوعات الرواتب اليتيمة
Future<List<IntegrityIssue>> _checkOrphanedSalaryPayments(AppDatabase db) async {
  final issues = <IntegrityIssue>[];

  final orphaned = await db.customSelect('''
    SELECT sp.local_uuid, sp.cycle_id
    FROM salary_payments sp
    LEFT JOIN salary_cycles sc ON sp.cycle_id = sc.id
    WHERE sp.cycle_id IS NOT NULL
      AND sp.deleted_at IS NULL
      AND (sc.id IS NULL OR sc.deleted_at IS NOT NULL)
  ''').get();

  for (final row in orphaned) {
    issues.add(
      IntegrityIssue(
        type: IssueType.orphanedRecord,
        table: 'salary_payments',
        uuid: row.read<String>('local_uuid'),
        description:
            'Salary payment references non-existent or deleted cycle (cycle_id: ${row.read<int?>('cycle_id')})',
        isCritical: true,
      ),
    );
  }

  return issues;
}

/// التحقق من الروابط المعلقة غير المحلولة لفترة طويلة
Future<List<IntegrityIssue>> _checkOrphanedPendingLinks(AppDatabase db) async {
  final issues = <IntegrityIssue>[];

  final staleLinks = await db.customSelect('''
    SELECT id, child_entity, child_local_uuid, parent_entity, parent_local_uuid, status, created_at
    FROM pending_links
    WHERE status = 'pending'
      AND created_at < ?
  ''', variables: [
    Variable.withInt(
      DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
    ),
  ]).get();

  for (final row in staleLinks) {
    issues.add(
      IntegrityIssue(
        type: IssueType.missingReference,
        table: 'pending_links',
        uuid: row.read<String>('child_local_uuid'),
        description:
            'Pending link unresolved for >7 days: ${row.read<String>('child_entity')} (${row.read<String>('child_local_uuid')}) -> ${row.read<String>('parent_entity')} (${row.read<String?>('parent_local_uuid')})',
        isCritical: false,
        metadata: {
          'link_id': row.read<int>('id'),
          'status': row.read<String>('status'),
          'created_at': row.read<int>('created_at'),
        },
      ),
    );
  }

  return issues;
}
