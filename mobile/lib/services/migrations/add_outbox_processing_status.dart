import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

class AddOutboxProcessingStatusMigration {
  static Future<void> migrate(DatabaseConnectionUser db) async {
    try {
      AppLogger.info('🔄 Running migration: add_outbox_processing_status', tag: 'APP');

      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_status TEXT DEFAULT "pending" NOT NULL',
      );
      AppLogger.info('✅ Added processing_status column', tag: 'APP');

      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_started_at INTEGER',
      );
      AppLogger.info('✅ Added processing_started_at column', tag: 'APP');

      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_worker TEXT',
      );
      AppLogger.info('✅ Added processing_worker column', tag: 'APP');

      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_outbox_processing_status ON outbox(processing_status)',
      );
      AppLogger.info('✅ Created index on processing_status', tag: 'APP');

      AppLogger.info('✅ Migration completed successfully', tag: 'APP');
    } catch (e, stackTrace) {
      AppLogger.error('❌ Migration failed: $e', tag: 'APP');
      AppLogger.info('Stack trace: $stackTrace', tag: 'APP');
      rethrow;
    }
  }
}
