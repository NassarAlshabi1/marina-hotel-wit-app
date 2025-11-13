import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';
import 'providers.dart';

/// نوع العملية على البيانات
enum ChangeAction {
  insert, // إضافة
  update, // تعديل
  delete, // حذف
}

/// سجل تغيير واحد
class ChangeRecord {
  final String tableName;
  final String recordUuid;
  final ChangeAction action;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  ChangeRecord({
    required this.tableName,
    required this.recordUuid,
    required this.action,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'table': tableName,
        'uuid': recordUuid,
        'action': action.name,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChangeRecord.fromJson(Map<String, dynamic> json) {
    return ChangeRecord(
      tableName: json['table'] as String,
      recordUuid: json['uuid'] as String,
      action: ChangeAction.values.firstWhere((e) => e.name == json['action']),
      data: json['data'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// حزمة تغييرات للمزامنة
class DeltaPackage {
  final List<ChangeRecord> changes;
  final DateTime createdAt;
  final int changesCount;

  DeltaPackage({
    required this.changes,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        changesCount = changes.length;

  Map<String, dynamic> toJson() => {
        'changes': changes.map((c) => c.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'changes_count': changesCount,
      };

  factory DeltaPackage.fromJson(Map<String, dynamic> json) {
    final changesList = json['changes'] as List<dynamic>;
    return DeltaPackage(
      changes: changesList.map((c) => ChangeRecord.fromJson(c)).toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// خدمة المزامنة بالفروقات (Delta Sync)
/// ترفع فقط التغييرات الجديدة بدلاً من كل البيانات
class DeltaSyncService {
  static const String _prefsLastSyncTimestampKey = 'delta_sync_last_timestamp';
  static const String _prefsPendingChangesKey = 'delta_sync_pending_changes';

  /// تسجيل تغيير جديد
  static Future<void> recordChange({
    required String tableName,
    required String recordUuid,
    required ChangeAction action,
    Map<String, dynamic>? data,
  }) async {
    try {
      final change = ChangeRecord(
        tableName: tableName,
        recordUuid: recordUuid,
        action: action,
        data: data,
      );

      // حفظ التغيير في القائمة المعلقة
      await _addPendingChange(change);

      debugPrint('📝 تم تسجيل تغيير: $tableName/$recordUuid (${action.name})');
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل التغيير: $e');
    }
  }

  /// إضافة تغيير إلى القائمة المعلقة
  static Future<void> _addPendingChange(ChangeRecord change) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString(_prefsPendingChangesKey);

      List<Map<String, dynamic>> pendingList = [];
      if (pendingJson != null) {
        final decoded = jsonDecode(pendingJson) as List<dynamic>;
        pendingList = decoded.cast<Map<String, dynamic>>();
      }

      pendingList.add(change.toJson());

      await prefs.setString(_prefsPendingChangesKey, jsonEncode(pendingList));
    } catch (e) {
      debugPrint('❌ خطأ في حفظ التغيير المعلق: $e');
    }
  }

  /// جلب جميع التغييرات المعلقة
  static Future<List<ChangeRecord>> getPendingChanges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString(_prefsPendingChangesKey);

      if (pendingJson == null) return [];

      final decoded = jsonDecode(pendingJson) as List<dynamic>;
      return decoded
          .map((json) => ChangeRecord.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ خطأ في جلب التغييرات المعلقة: $e');
      return [];
    }
  }

  /// مسح التغييرات المعلقة بعد المزامنة الناجحة
  static Future<void> clearPendingChanges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsPendingChangesKey);
      debugPrint('🧹 تم مسح التغييرات المعلقة');
    } catch (e) {
      debugPrint('❌ خطأ في مسح التغييرات المعلقة: $e');
    }
  }

  /// إنشاء حزمة Delta من التغييرات منذ آخر مزامنة
  static Future<DeltaPackage?> createDeltaPackage() async {
    final stopwatch = Stopwatch()..start();

    try {
      final lastSyncTime = await getLastSyncTimestamp();
      final db = getDatabase();

      debugPrint('🔍 بدء إنشاء حزمة Delta...');
      debugPrint('   آخر مزامنة: ${lastSyncTime?.toIso8601String() ?? "لم تتم من قبل"}');

      final changes = <ChangeRecord>[];

      // جلب التغييرات من كل جدول
      await _collectChangesFromTable(
        db,
        'bookings',
        lastSyncTime,
        changes,
      );
      await _collectChangesFromTable(
        db,
        'payments',
        lastSyncTime,
        changes,
      );
      await _collectChangesFromTable(
        db,
        'expenses',
        lastSyncTime,
        changes,
      );
      await _collectChangesFromTable(
        db,
        'rooms',
        lastSyncTime,
        changes,
      );
      await _collectChangesFromTable(
        db,
        'employees',
        lastSyncTime,
        changes,
      );
      await _collectChangesFromTable(
        db,
        'cash_transactions',
        lastSyncTime,
        changes,
      );
      await _collectChangesFromTable(
        db,
        'booking_notes',
        lastSyncTime,
        changes,
      );

      // إضافة التغييرات المعلقة
      final pendingChanges = await getPendingChanges();
      changes.addAll(pendingChanges);

      stopwatch.stop();

      if (changes.isEmpty) {
        debugPrint('ℹ️ لا توجد تغييرات للمزامنة');
        return null;
      }

      debugPrint('✅ تم إنشاء حزمة Delta بنجاح');
      debugPrint('   عدد التغييرات: ${changes.length}');
      debugPrint('   الوقت المستغرق: ${stopwatch.elapsedMilliseconds}ms');

      return DeltaPackage(changes: changes);
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء حزمة Delta: $e');
      return null;
    }
  }

  /// جمع التغييرات من جدول معين
  static Future<void> _collectChangesFromTable(
    AppDatabase db,
    String tableName,
    DateTime? lastSyncTime,
    List<ChangeRecord> changes,
  ) async {
    try {
      if (lastSyncTime == null) {
        // أول مزامنة - نعتبر كل شيء جديد
        return;
      }

      final lastSyncMillis = lastSyncTime.millisecondsSinceEpoch;

      switch (tableName) {
        case 'bookings':
          final modifiedBookings = await (db.select(db.bookings)
                ..where((t) => t.lastModified.isBiggerOrEqualValue(lastSyncMillis)))
              .get();
          for (final booking in modifiedBookings) {
            changes.add(ChangeRecord(
              tableName: tableName,
              recordUuid: booking.localUuid,
              action: ChangeAction.update,
              data: booking.toJson(),
            ));
          }
          break;

        case 'payments':
          final modifiedPayments = await (db.select(db.payments)
                ..where((t) => t.lastModified.isBiggerOrEqualValue(lastSyncMillis)))
              .get();
          for (final payment in modifiedPayments) {
            changes.add(ChangeRecord(
              tableName: tableName,
              recordUuid: payment.localUuid,
              action: ChangeAction.update,
              data: payment.toJson(),
            ));
          }
          break;

        case 'expenses':
          final modifiedExpenses = await (db.select(db.expenses)
                ..where((t) => t.lastModified.isBiggerOrEqualValue(lastSyncMillis)))
              .get();
          for (final expense in modifiedExpenses) {
            changes.add(ChangeRecord(
              tableName: tableName,
              recordUuid: expense.localUuid,
              action: ChangeAction.update,
              data: expense.toJson(),
            ));
          }
          break;

        case 'rooms':
          final modifiedRooms = await (db.select(db.rooms)
                ..where((t) => t.lastModified.isBiggerOrEqualValue(lastSyncMillis)))
              .get();
          for (final room in modifiedRooms) {
            changes.add(ChangeRecord(
              tableName: tableName,
              recordUuid: room.localUuid,
              action: ChangeAction.update,
              data: room.toJson(),
            ));
          }
          break;

        case 'employees':
          final modifiedEmployees = await (db.select(db.employees)
                ..where((t) => t.lastModified.isBiggerOrEqualValue(lastSyncMillis)))
              .get();
          for (final employee in modifiedEmployees) {
            changes.add(ChangeRecord(
              tableName: tableName,
              recordUuid: employee.localUuid,
              action: ChangeAction.update,
              data: employee.toJson(),
            ));
          }
          break;

        case 'cash_transactions':
          final modifiedTransactions = await (db.select(db.cashTransactions)
                ..where((t) => t.lastModified.isBiggerOrEqualValue(lastSyncMillis)))
              .get();
          for (final transaction in modifiedTransactions) {
            changes.add(ChangeRecord(
              tableName: tableName,
              recordUuid: transaction.localUuid,
              action: ChangeAction.update,
              data: transaction.toJson(),
            ));
          }
          break;

        case 'booking_notes':
          final modifiedNotes = await (db.select(db.bookingNotes)
                ..where((t) => t.lastModified.isBiggerOrEqualValue(lastSyncMillis)))
              .get();
          for (final note in modifiedNotes) {
            changes.add(ChangeRecord(
              tableName: tableName,
              recordUuid: note.localUuid,
              action: ChangeAction.update,
              data: note.toJson(),
            ));
          }
          break;
      }
    } catch (e) {
      debugPrint('❌ خطأ في جمع التغييرات من $tableName: $e');
    }
  }

  /// تطبيق حزمة Delta على قاعدة البيانات المحلية
  static Future<void> applyDeltaPackage(DeltaPackage package) async {
    final stopwatch = Stopwatch()..start();

    try {
      debugPrint('📥 بدء تطبيق حزمة Delta...');
      debugPrint('   عدد التغييرات: ${package.changesCount}');

      final db = getDatabase();
      int appliedCount = 0;

      for (final change in package.changes) {
        try {
          await _applyChange(db, change);
          appliedCount++;
        } catch (e) {
          debugPrint('❌ خطأ في تطبيق التغيير ${change.recordUuid}: $e');
        }
      }

      stopwatch.stop();

      debugPrint('✅ تم تطبيق التغييرات بنجاح');
      debugPrint('   التغييرات المطبقة: $appliedCount/${package.changesCount}');
      debugPrint('   الوقت المستغرق: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('❌ خطأ في تطبيق حزمة Delta: $e');
      rethrow;
    }
  }

  /// تطبيق تغيير واحد
  static Future<void> _applyChange(AppDatabase db, ChangeRecord change) async {
    if (change.data == null && change.action != ChangeAction.delete) {
      return;
    }

    switch (change.tableName) {
      case 'bookings':
        if (change.action == ChangeAction.delete) {
          await (db.delete(db.bookings)
                ..where((t) => t.localUuid.equals(change.recordUuid)))
              .go();
        } else {
          final booking = Booking.fromJson(change.data!);
          await db.into(db.bookings).insertOnConflictUpdate(booking);
        }
        break;

      case 'payments':
        if (change.action == ChangeAction.delete) {
          await (db.delete(db.payments)
                ..where((t) => t.localUuid.equals(change.recordUuid)))
              .go();
        } else {
          final payment = Payment.fromJson(change.data!);
          await db.into(db.payments).insertOnConflictUpdate(payment);
        }
        break;

      case 'expenses':
        if (change.action == ChangeAction.delete) {
          await (db.delete(db.expenses)
                ..where((t) => t.localUuid.equals(change.recordUuid)))
              .go();
        } else {
          final expense = Expense.fromJson(change.data!);
          await db.into(db.expenses).insertOnConflictUpdate(expense);
        }
        break;

      case 'rooms':
        if (change.action == ChangeAction.delete) {
          await (db.delete(db.rooms)
                ..where((t) => t.localUuid.equals(change.recordUuid)))
              .go();
        } else {
          final room = Room.fromJson(change.data!);
          await db.into(db.rooms).insertOnConflictUpdate(room);
        }
        break;

      case 'employees':
        if (change.action == ChangeAction.delete) {
          await (db.delete(db.employees)
                ..where((t) => t.localUuid.equals(change.recordUuid)))
              .go();
        } else {
          final employee = Employee.fromJson(change.data!);
          await db.into(db.employees).insertOnConflictUpdate(employee);
        }
        break;

      case 'cash_transactions':
        if (change.action == ChangeAction.delete) {
          await (db.delete(db.cashTransactions)
                ..where((t) => t.localUuid.equals(change.recordUuid)))
              .go();
        } else {
          final transaction = CashTransaction.fromJson(change.data!);
          await db.into(db.cashTransactions).insertOnConflictUpdate(transaction);
        }
        break;

      case 'booking_notes':
        if (change.action == ChangeAction.delete) {
          await (db.delete(db.bookingNotes)
                ..where((t) => t.localUuid.equals(change.recordUuid)))
              .go();
        } else {
          final note = BookingNote.fromJson(change.data!);
          await db.into(db.bookingNotes).insertOnConflictUpdate(note);
        }
        break;
    }
  }

  /// حفظ timestamp آخر مزامنة
  static Future<void> setLastSyncTimestamp(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsLastSyncTimestampKey,
        timestamp.toIso8601String(),
      );
      debugPrint('💾 تم حفظ timestamp المزامنة: ${timestamp.toIso8601String()}');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ timestamp المزامنة: $e');
    }
  }

  /// جلب timestamp آخر مزامنة
  static Future<DateTime?> getLastSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampStr = prefs.getString(_prefsLastSyncTimestampKey);
      return timestampStr != null ? DateTime.parse(timestampStr) : null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب timestamp المزامنة: $e');
      return null;
    }
  }

  /// حساب حجم حزمة Delta (بالبايتات)
  static int calculatePackageSize(DeltaPackage package) {
    try {
      final jsonString = jsonEncode(package.toJson());
      return utf8.encode(jsonString).length;
    } catch (e) {
      debugPrint('❌ خطأ في حساب حجم الحزمة: $e');
      return 0;
    }
  }
}
