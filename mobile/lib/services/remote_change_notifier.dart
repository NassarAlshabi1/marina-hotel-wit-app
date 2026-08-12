// ignore_for_file: discarded_futures
// lib/services/remote_change_notifier.dart
//
// ✅ إشعارات محلية عند اكتشاف وتطبيق تغييرات قادمة من هاتف آخر
//
// المنطق:
//   1. بعد نجاح apply محلي لتغيير قادم من pull
//   2. نتحقق أن device_id في السجل ≠ معرّف جهازنا الحالي
//   3. نتحقق أن الحدث لم يُسجَّل سابقاً (dedup persistent)
//   4. نُجمّع عدة تغييرات متقاربة في إشعار واحد
//   5. نُطلق إشعار محلي واحد عبر LocalNotificationService

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';

/// ✅ إشعار محلي عند تطبيق تغييرات قادمة من جهاز آخر.
class RemoteChangeNotifier {
  factory RemoteChangeNotifier() => _instance;
  RemoteChangeNotifier._internal();
  static final RemoteChangeNotifier _instance = RemoteChangeNotifier._internal();

  static RemoteChangeNotifier get instance => _instance;

  static const String _kDedupKey = 'remote_change_dedup_keys';
  static const int _kMaxDedupEntries = 500;
  static const Duration _kAggregationWindow = Duration(seconds: 3);

  String? _myDeviceId;
  final Set<String> _dedupKeys = <String>{};
  bool _dedupLoaded = false;
  final List<_PendingChange> _pendingChanges = <_PendingChange>[];
  Timer? _aggregationTimer;

  int get pendingCount => _pendingChanges.length;

  void setMyDeviceId(String deviceId) {
    _myDeviceId = deviceId;
    debugPrint('📞 RemoteChangeNotifier: my device ID = $deviceId');
  }

  Future<void> _ensureDedupLoaded() async {
    if (_dedupLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList(_kDedupKey) ?? <String>[];
      _dedupKeys.addAll(keys);
      _dedupLoaded = true;
      debugPrint('📞 RemoteChangeNotifier: loaded ${_dedupKeys.length} dedup keys');
    } catch (e) {
      debugPrint('⚠️ RemoteChangeNotifier: failed to load dedup keys: $e');
      _dedupLoaded = true;
    }
  }

  Future<void> _persistDedupKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> toSave;
      if (_dedupKeys.length > _kMaxDedupEntries) {
        final asList = _dedupKeys.toList();
        toSave = asList.sublist(asList.length - _kMaxDedupEntries);
        _dedupKeys
          ..clear()
          ..addAll(toSave);
      } else {
        toSave = _dedupKeys.toList();
      }
      await prefs.setStringList(_kDedupKey, toSave);
    } catch (e) {
      debugPrint('⚠️ RemoteChangeNotifier: failed to persist dedup keys: $e');
    }
  }

  Future<void> onRemoteChangeApplied({
    required String entity,
    required Map<String, dynamic> record,
    required String op,
  }) async {
    await _ensureDedupLoaded();

    final sourceDeviceId = (record['device_id'] as String?) ?? '';
    final localUuid = (record['local_uuid'] as String?) ?? '';
    final updatedAt = (record['updated_at'] as int?) ?? 0;

    // ✅ لا تُشعر لتغييرات نفس الجهاز
    if (_myDeviceId != null && _myDeviceId!.isNotEmpty && sourceDeviceId.isNotEmpty && sourceDeviceId == _myDeviceId) {
      return;
    }

    // ✅ إذا لم يتوفر device_id، لا نعرف إن كان من جهاز آخر
    if (sourceDeviceId.isEmpty) {
      debugPrint(
        '📞 RemoteChangeNotifier: skipping change without device_id '
        '($entity/$localUuid) — cannot verify cross-device origin',
      );
      return;
    }

    final dedupKey = '$entity:$localUuid:$updatedAt:$sourceDeviceId';

    if (_dedupKeys.contains(dedupKey)) {
      return;
    }

    _dedupKeys.add(dedupKey);
    await _persistDedupKeys();

    _pendingChanges.add(
      _PendingChange(
        entity: entity,
        op: op,
        localUuid: localUuid,
        sourceDeviceId: sourceDeviceId,
        updatedAt: updatedAt,
        roomNumber: record['room_number'] as String?,
        guestName: record['guest_name'] as String?,
        amount: record['amount'] as num?,
        expenseType: record['expense_type'] as String?,
        description: record['description'] as String?,
      ),
    );

    _aggregationTimer?.cancel();
    _aggregationTimer = Timer(_kAggregationWindow, _flushAggregatedNotification);
  }

  void _flushAggregatedNotification() {
    if (_pendingChanges.isEmpty) return;

    final changes = List<_PendingChange>.from(_pendingChanges);
    _pendingChanges.clear();

    final title = _buildTitle(changes);
    final body = _buildBody(changes);
    final payload = _buildPayload(changes);

    unawaited(
      LocalNotificationService.instance.notifyGeneric(
        title: title,
        body: body,
        payload: payload,
      ),
    );

    debugPrint(
      '📞 RemoteChangeNotifier: flushed ${changes.length} aggregated changes '
      '→ "$title"',
    );
  }

  String _buildTitle(List<_PendingChange> changes) {
    if (changes.length == 1) {
      return _singleChangeTitle(changes.first);
    }
    return '📱 ${changes.length} تحديثات من أجهزة أخرى';
  }

  String _singleChangeTitle(_PendingChange c) {
    switch (c.entity) {
      case 'bookings':
        return c.op == 'delete' ? '🚪 حذف حجز من جهاز آخر' : '🛎️ حجز جديد من جهاز آخر';
      case 'payments':
        return '💰 دفعة من جهاز آخر';
      case 'expenses':
        return '📉 مصروف من جهاز آخر';
      case 'debts':
        return '💸 دين من جهاز آخر';
      case 'rooms':
        return '🚪 تحديث غرفة من جهاز آخر';
      case 'employees':
        return '👤 تحديث موظف من جهاز آخر';
      default:
        return '📱 تحديث من جهاز آخر';
    }
  }

  String _buildBody(List<_PendingChange> changes) {
    if (changes.length == 1) {
      return _singleChangeBody(changes.first);
    }
    final byEntity = <String, int>{};
    for (final c in changes) {
      byEntity[c.entity] = (byEntity[c.entity] ?? 0) + 1;
    }
    final parts = <String>[];
    const entityLabels = {
      'bookings': 'حجوزات',
      'payments': 'مدفوعات',
      'expenses': 'مصروفات',
      'debts': 'ديون',
      'rooms': 'غرف',
      'employees': 'موظفين',
    };
    byEntity.forEach((entity, count) {
      final label = entityLabels[entity] ?? entity;
      parts.add('$count $label');
    });
    return parts.join('، ');
  }

  String _singleChangeBody(_PendingChange c) {
    final parts = <String>[];
    if (c.roomNumber != null && c.roomNumber!.isNotEmpty) {
      parts.add('غرفة ${c.roomNumber}');
    }
    if (c.guestName != null && c.guestName!.isNotEmpty) {
      parts.add(c.guestName!);
    }
    if (c.amount != null) {
      parts.add('${c.amount!.toStringAsFixed(0)} ريال');
    }
    if (c.expenseType != null && c.expenseType!.isNotEmpty) {
      parts.add(c.expenseType!);
    }
    if (c.description != null && c.description!.isNotEmpty) {
      parts.add(c.description!);
    }
    if (parts.isEmpty) {
      return 'تم تحديث ${c.entity} من جهاز آخر';
    }
    return parts.join(' — ');
  }

  String _buildPayload(List<_PendingChange> changes) {
    if (changes.length == 1) {
      final c = changes.first;
      return 'remote_change:${c.entity}:${c.localUuid}';
    }
    final first = changes.first;
    return 'remote_change:${first.entity}:multiple';
  }

  // ─── Testing helpers ────────────────────────────────────────

  @visibleForTesting
  Future<void> clearDedupForTesting() async {
    _dedupKeys.clear();
    _pendingChanges.clear();
    _aggregationTimer?.cancel();
    _aggregationTimer = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kDedupKey);
    } catch (_) {}
    _dedupLoaded = true;
  }

  @visibleForTesting
  void flushForTesting() {
    _aggregationTimer?.cancel();
    _aggregationTimer = null;
    _flushAggregatedNotification();
  }

  @visibleForTesting
  void setMyDeviceIdForTesting(String deviceId) {
    _myDeviceId = deviceId;
  }

  @visibleForTesting
  int get dedupKeysCount => _dedupKeys.length;

  static void handleNotificationTap(String? payload) {
    if (payload == null || !payload.startsWith('remote_change:')) return;

    final parts = payload.split(':');
    if (parts.length < 3) return;

    final entity = parts[1];
    final idOrMultiple = parts[2];

    debugPrint(
      '📞 RemoteChangeNotifier tap: entity=$entity, id=$idOrMultiple '
      '(navigation TODO — no router integration yet)',
    );
  }
}

class _PendingChange {
  _PendingChange({
    required this.entity,
    required this.op,
    required this.localUuid,
    required this.sourceDeviceId,
    required this.updatedAt,
    this.roomNumber,
    this.guestName,
    this.amount,
    this.expenseType,
    this.description,
  });

  final String entity;
  final String op;
  final String localUuid;
  final String sourceDeviceId;
  final int updatedAt;
  final String? roomNumber;
  final String? guestName;
  final num? amount;
  final String? expenseType;
  final String? description;
}
