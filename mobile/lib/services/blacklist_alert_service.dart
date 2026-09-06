// ignore_for_file: discarded_futures, use_build_context_synchronously
// ═══════════════════════════════════════════════════════════════
//  blacklist_alert_service.dart — خدمة تنبيهات القائمة السوداء
//  تراقب تسجيل دخول النزلاء وتطابق أسماءهم مع القائمة السوداء
//  تعرض تنبيه فوري على الشاشة الرئيسية عند المطابقة
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/local_db.dart';
import '../services/repositories/blacklist_repository.dart';

/// نموذج تنبيه القائمة السوداء
class BlacklistAlert {
  const BlacklistAlert({
    required this.guestName,
    required this.roomNumber,
    required this.bookingId,
    required this.blacklistEntry,
    required this.detectedAt,
  });

  final String guestName;
  final String roomNumber;
  final int bookingId;
  final BlacklistEntry blacklistEntry;
  final DateTime detectedAt;

  String get displayName => '${blacklistEntry.name} (غرفة $roomNumber)';

  String get reasonText => blacklistEntry.reason ?? 'سبب غير محدد';

  Map<String, dynamic> toJson() => {
    'guestName': guestName,
    'roomNumber': roomNumber,
    'bookingId': bookingId,
    'blacklistName': blacklistEntry.name,
    'reason': blacklistEntry.reason,
    'detectedAt': detectedAt.toIso8601String(),
  };

  static BlacklistAlert fromJson(
    Map<String, dynamic> json,
    BlacklistEntry entry,
  ) {
    return BlacklistAlert(
      guestName: json['guestName'] as String,
      roomNumber: json['roomNumber'] as String,
      bookingId: json['bookingId'] as int,
      blacklistEntry: entry,
      detectedAt: DateTime.parse(json['detectedAt'] as String),
    );
  }
}

/// خدمة تنبيهات القائمة السوداء — Singleton
class BlacklistAlertService {
  BlacklistAlertService._();
  static final BlacklistAlertService instance = BlacklistAlertService._();

  static const _storageKey = 'blacklist_alerts';

  final _alertsController = StreamController<List<BlacklistAlert>>.broadcast();
  Stream<List<BlacklistAlert>> get alertsStream => _alertsController.stream;

  List<BlacklistAlert> _activeAlerts = [];
  List<BlacklistAlert> get activeAlerts => List.unmodifiable(_activeAlerts);

  bool _initialized = false;

  /// تهيئة — تحميل التنبيهات المحفوظة + فحص النزلاء الحاليين
  Future<void> initialize(AppDatabase db) async {
    if (_initialized) return;
    _initialized = true;

    await _loadPersistedAlerts(db);
    await _scanCurrentGuests(db);
    _alertsController.add(_activeAlerts);
  }

  /// فحص نزيل جديد عند تسجيل الدخول
  Future<BlacklistAlert?> checkGuest({
    required AppDatabase db,
    required String guestName,
    required String roomNumber,
    required int bookingId,
  }) async {
    final repo = BlacklistRepository(db);
    final match = await repo.findBlacklistMatch(guestName);

    if (match == null || !match.active) return null;

    // تحقق من عدم وجود تنبيه مكرر لنفس الحجز
    final existing = _activeAlerts.where(
      (a) => a.bookingId == bookingId && a.guestName == guestName,
    );
    if (existing.isNotEmpty) return existing.first;

    final alert = BlacklistAlert(
      guestName: guestName,
      roomNumber: roomNumber,
      bookingId: bookingId,
      blacklistEntry: match,
      detectedAt: DateTime.now(),
    );

    _activeAlerts.insert(0, alert);
    _alertsController.add(_activeAlerts);
    await _persistAlerts();

    debugPrint(
      '🚨 BLACKLIST ALERT: ${match.name} matched guest "$guestName" in room $roomNumber',
    );

    return alert;
  }

  /// فحص كل النزلاء الحاليين (عند تشغيل التطبيق)
  Future<void> _scanCurrentGuests(AppDatabase db) async {
    try {
      final activeBookings = await db
          .customSelect(
            'SELECT id, guest_name, room_number FROM bookings '
            'WHERE status = ? AND deleted_at IS NULL AND actual_checkout IS NULL',
            variables: [const Variable<String>('checked_in')],
          )
          .get();

      final repo = BlacklistRepository(db);
      var newAlerts = 0;

      for (final row in activeBookings) {
        final guestName = row.data['guest_name'] as String;
        final roomNumber = row.data['room_number'] as String;
        final bookingId = row.data['id'] as int;

        // تخطي إذا كان هناك تنبيه موجود بالفعل
        if (_activeAlerts.any((a) => a.bookingId == bookingId)) continue;

        final match = await repo.findBlacklistMatch(guestName);
        if (match != null && match.active) {
          _activeAlerts.add(
            BlacklistAlert(
              guestName: guestName,
              roomNumber: roomNumber,
              bookingId: bookingId,
              blacklistEntry: match,
              detectedAt: DateTime.now(),
            ),
          );
          newAlerts++;
        }
      }

      if (newAlerts > 0) {
        debugPrint('🚨 Blacklist scan: $newAlerts new alert(s) found');
        await _persistAlerts();
      }
    } catch (e) {
      debugPrint('⚠️ Blacklist scan failed: $e');
    }
  }

  /// إزالة تنبيه عند مغادرة النزيل
  Future<void> dismissAlert(int bookingId) async {
    _activeAlerts = _activeAlerts
        .where((a) => a.bookingId != bookingId)
        .toList();
    _alertsController.add(_activeAlerts);
    await _persistAlerts();
  }

  /// إزالة كل التنبيهات
  Future<void> clearAll() async {
    _activeAlerts = [];
    _alertsController.add(_activeAlerts);
    await _persistAlerts();
  }

  /// تحميل التنبيهات المحفوظة من SharedPreferences
  Future<void> _loadPersistedAlerts(AppDatabase db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final list = jsonDecode(jsonStr) as List;
      final repo = BlacklistRepository(db);
      final allEntries = await repo.listAll();

      _activeAlerts = [];
      for (final item in list) {
        final json = item as Map<String, dynamic>;
        final bookingId = json['bookingId'] as int;

        // تحقق من أن النزيل لا يزال مسجلاً
        final booking = await db
            .customSelect(
              'SELECT id FROM bookings WHERE id = ? AND status = ? AND deleted_at IS NULL',
              variables: [
                Variable<int>(bookingId),
                const Variable<String>('checked_in'),
              ],
            )
            .getSingleOrNull();

        if (booking == null) continue; // النزيل غادر — تخطى

        // ابحث عن مدخل القائمة السوداء بالاسم
        final name = json['blacklistName'] as String;
        final entry = allEntries.where((e) => e.name == name).firstOrNull;
        if (entry == null || !entry.active) continue;

        _activeAlerts.add(BlacklistAlert.fromJson(json, entry));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load blacklist alerts: $e');
    }
  }

  /// حفظ التنبيهات في SharedPreferences
  Future<void> _persistAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_activeAlerts.map((a) => a.toJson()).toList());
      await prefs.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('⚠️ Failed to persist blacklist alerts: $e');
    }
  }

  void dispose() {
    _alertsController.close();
  }
}

// ═══════════════════════════════════════════════════════════════
//  Riverpod Providers
// ═══════════════════════════════════════════════════════════════

/// Provider لخدمة تنبيهات القائمة السوداء
final blacklistAlertServiceProvider = Provider<BlacklistAlertService>((ref) {
  return BlacklistAlertService.instance;
});

/// Stream للتنبيهات النشطة (يُستخدم في الـ UI)
final blacklistAlertsProvider = StreamProvider<List<BlacklistAlert>>((ref) {
  final service = ref.read(blacklistAlertServiceProvider);
  return service.alertsStream;
});
