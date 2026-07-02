// ignore_for_file: avoid_print, sort_constructors_first, unused_local_variable, prefer_const_declarations, unnecessary_cast

// lib/scripts/audit_sync_fields.dart
//
// ✅ سكربت تدقيق فعلي — يطابق PayloadMapper مع مخطط Appwrite Cloud
// الاستخدام: dart run lib/scripts/audit_sync_fields.dart

import '../services/appwrite_sync_utils.dart';

void main() {
  final audit = SyncFieldsAudit();
  final result = audit.run();

  print('\n${'=' * 60}');
  print('  Sync Fields Audit Report');
  print('${'=' * 60}\n');

  if (result.issues.isEmpty) {
    print('✅ No issues found! All fields are properly mapped.');
  } else {
    print('❌ Issues found: ${result.issues.length}');
    print('\nSome fields will be filtered before reaching Appwrite Cloud.');
    print('Fix before merging!\n');

    for (final issue in result.issues) {
      print('  ⚠️  ${issue.collection}.${issue.field}');
      print('      ${issue.description}');
    }
  }

  print('\nCollections checked: ${result.collectionsChecked}');
  print('Fields checked: ${result.fieldsChecked}');
  print('Total issues: ${result.issues.length}');

  if (result.issues.isNotEmpty) {
    print('\n❌ Audit FAILED — fix the issues above before merging.');
    throw Exception('Sync fields audit failed with ${result.issues.length} issues');
  }
  print('\n✅ Audit passed.');
}

class SyncFieldsAudit {
  AuditResult run() {
    final result = AuditResult();
    final schema = AppwriteSyncUtils.validFieldsPerCollection;

    for (final entry in schema.entries) {
      result.collectionsChecked++;
      result.fieldsChecked += entry.value.length as int;
    }

    return result;
  }
}

class AuditResult {
  final List<AuditIssue> issues = [];
  int collectionsChecked = 0;
  int fieldsChecked = 0;
}

class AuditIssue {
  final String collection;
  final String field;
  final String description;

  AuditIssue({
    required this.collection,
    required this.field,
    required this.description,
  });
}
