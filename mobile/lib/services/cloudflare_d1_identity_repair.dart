import 'package:drift/drift.dart' show UpdateKind, Variable;

import '../utils/id.dart';
import 'local_db.dart';

/// Repairs legacy rows before a direct Cloudflare D1 data upload.
/// It only fills missing identities and derives links from explicit local FKs.
class CloudflareD1IdentityRepair {
  CloudflareD1IdentityRepair._();

  static const Set<String> dataTables = {
    'rooms',
    'bookings',
    'booking_nights',
    'booking_notes',
    'booking_price_adjustments',
    'payments',
    'payment_voids',
    'price_adjustments',
    'expenses',
    'debts',
    'employees',
    'guest_infos',
    'cash_transactions',
    'shift_notes',
    'salary_cycles',
    'salary_payments',
    'salary_withdrawals',
    'salary_carry_over_logs',
    'audit_logs',
    'inventory_items',
    'inventory_transactions',
  };

  static Future<CloudflareD1IdentityRepairResult> repair({
    required AppDatabase db,
    required Set<String> selectedTables,
  }) async {
    final selected = selectedTables.intersection(dataTables);
    var identitiesRepaired = 0;
    var linksRepaired = 0;

    await db.transaction(() async {
      for (final table in selected) {
        final where = table == 'shift_notes'
            ? " AND (created_by IS NULL OR created_by <> 'blacklist')"
            : '';
        final rows = await db
            .customSelect(
              'SELECT id FROM "$table" WHERE '
              '(local_uuid IS NULL OR TRIM(local_uuid) = "")$where',
            )
            .get();
        for (final row in rows) {
          final id = row.data['id'];
          if (id == null) continue;
          identitiesRepaired += await db.customUpdate(
            'UPDATE "$table" SET local_uuid = ? WHERE id = ? AND '
            '(local_uuid IS NULL OR TRIM(local_uuid) = "")',
            variables: [Variable<String>(IdGen.uuid()), Variable<Object>(id)],
            updateKind: UpdateKind.update,
          );
        }
      }

      const mappings = <_UuidLinkMapping>[
        _UuidLinkMapping(
          'salary_withdrawals',
          'employee_uuid',
          'employee_id',
          'employees',
        ),
        _UuidLinkMapping(
          'salary_cycles',
          'employee_uuid',
          'employee_id',
          'employees',
        ),
        _UuidLinkMapping(
          'salary_payments',
          'employee_uuid',
          'cycle_id',
          'salary_cycles',
          parentUuidColumn: 'employee_uuid',
        ),
        _UuidLinkMapping(
          'salary_payments',
          'cycle_uuid',
          'cycle_id',
          'salary_cycles',
        ),
        _UuidLinkMapping(
          'salary_carry_over_logs',
          'employee_uuid',
          'employee_id',
          'employees',
        ),
        _UuidLinkMapping(
          'salary_withdrawals',
          'expense_uuid',
          'expense_id',
          'expenses',
        ),
        _UuidLinkMapping(
          'inventory_transactions',
          'item_local_uuid',
          'item_id',
          'inventory_items',
        ),
        _UuidLinkMapping(
          'payments',
          'booking_uuid_cache',
          'booking_local_id',
          'bookings',
        ),
        _UuidLinkMapping(
          'debts',
          'booking_uuid_cache',
          'booking_local_id',
          'bookings',
        ),
        _UuidLinkMapping(
          'booking_nights',
          'booking_uuid_cache',
          'booking_local_id',
          'bookings',
        ),
        _UuidLinkMapping(
          'booking_price_adjustments',
          'booking_local_uuid',
          'booking_local_id',
          'bookings',
        ),
      ];
      for (final mapping in mappings) {
        if (!selected.contains(mapping.child) ||
            !selected.contains(mapping.parent)) {
          continue;
        }
        linksRepaired += await db.customUpdate(
          'UPDATE "${mapping.child}" AS child SET "${mapping.childColumn}" '
          '= (SELECT parent."${mapping.parentUuidColumn}" FROM "${mapping.parent}" AS parent '
          'WHERE parent.id = child."${mapping.fkColumn}") '
          'WHERE child."${mapping.fkColumn}" IS NOT NULL AND '
          '(child."${mapping.childColumn}" IS NULL OR TRIM(child."${mapping.childColumn}") = "") '
          'AND EXISTS (SELECT 1 FROM "${mapping.parent}" AS parent '
          'WHERE parent.id = child."${mapping.fkColumn}" AND '
          'parent."${mapping.parentUuidColumn}" IS NOT NULL AND '
          'TRIM(parent."${mapping.parentUuidColumn}") <> "")',
          updateKind: UpdateKind.update,
        );
      }
    });

    return CloudflareD1IdentityRepairResult(
      identitiesRepaired: identitiesRepaired,
      linksRepaired: linksRepaired,
    );
  }
}

class _UuidLinkMapping {
  const _UuidLinkMapping(
    this.child,
    this.childColumn,
    this.fkColumn,
    this.parent, {
    this.parentUuidColumn = 'local_uuid',
  });

  final String child;
  final String childColumn;
  final String fkColumn;
  final String parent;
  final String parentUuidColumn;
}

class CloudflareD1IdentityRepairResult {
  const CloudflareD1IdentityRepairResult({
    required this.identitiesRepaired,
    required this.linksRepaired,
  });

  final int identitiesRepaired;
  final int linksRepaired;
}
