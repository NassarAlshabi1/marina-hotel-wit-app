import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class AddOutboxProcessingStatusMigration {
  static Future<void> migrate(DatabaseConnectionUser db) async {
    try {
      dlog('🔄 Running migration: add_outbox_processing_status');

      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_status TEXT DEFAULT "pending" NOT NULL',
      );
      dlog('✅ Added processing_status column');

      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_started_at INTEGER',
      );
      dlog('✅ Added processing_started_at column');

      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_worker TEXT',
      );
      dlog('✅ Added processing_worker column');

      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_outbox_processing_status ON outbox(processing_status)',
      );
      dlog('✅ Created index on processing_status');

      dlog('✅ Migration completed successfully');
    } catch (e, stackTrace) {
      dlog(() => '❌ Migration failed: $e');
      dlog(() => 'Stack trace: $stackTrace');
      rethrow;
    }
  }
}
