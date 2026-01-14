import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

class AddOutboxProcessingStatusMigration {
  static Future<void> migrate(DatabaseConnectionUser db) async {
    try {
      debugPrint('🔄 Running migration: add_outbox_processing_status');
      
      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_status TEXT DEFAULT "pending" NOT NULL'
      );
      debugPrint('✅ Added processing_status column');
      
      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_started_at INTEGER'
      );
      debugPrint('✅ Added processing_started_at column');
      
      await db.customStatement(
        'ALTER TABLE outbox ADD COLUMN processing_worker TEXT'
      );
      debugPrint('✅ Added processing_worker column');
      
      await db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_outbox_processing_status ON outbox(processing_status)'
      );
      debugPrint('✅ Created index on processing_status');
      
      debugPrint('✅ Migration completed successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Migration failed: $e');
      debugPrint('Stack trace: ${stackTrace.toString()}');
      rethrow;
    }
  }
}
