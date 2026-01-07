import 'dart:convert';
import 'dart:io';

import '../local_db.dart';
import 'fix_nights_multiplication.dart';

/// Script لتشغيل migration إصلاح مشكلة ضرب الليالي في 1000
/// 
/// الاستخدام:
/// ```bash
/// cd mobile
/// dart run lib/services/migrations/run_nights_fix_migration.dart
/// ```
Future<void> main() async {
  print('🚀 Starting Nights Multiplication Fix Migration');
  print('=' * 80);
  
  // إنشاء database connection
  final db = AppDatabase();
  
  try {
    // تشغيل الـ migration مع تقرير
    final migration = FixNightsMultiplicationMigration(db);
    final report = await migration.executeWithReport();
    
    // طباعة التقرير
    print(report.toString());
    
    // حفظ التقرير في ملف JSON
    final reportFile = File('migration_report_${DateTime.now().millisecondsSinceEpoch}.json');
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    print('\n📄 Report saved to: ${reportFile.path}');
    
    // Exit code
    exit(report.success ? 0 : 1);
    
  } catch (e, stackTrace) {
    print('\n❌ Migration failed with error:');
    print(e);
    print('\nStack trace:');
    print(stackTrace);
    exit(1);
  } finally {
    await db.close();
  }
}
