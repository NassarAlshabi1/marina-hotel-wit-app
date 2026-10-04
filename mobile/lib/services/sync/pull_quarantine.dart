// ══════════════════════════════════════════════════════════════════
//  pull_quarantine.dart — Pull quarantine + waiting ledger for orphans
// ══════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// سجل مُسحوب معاد جدولته: الكيان + الحمولة الكاملة (لإعادة الحل محلياً).
typedef PullRecord = ({String entity, Map<String, dynamic> record});

/// الحجر الصحي وسجل الانتظار للصفوف اليتيمة (2026-09-09 → 2026-09-15).
///
/// المشكلة: صف واحد بأبٍ مفقود خادمياً (يتيم بنيوي — أبُه حُذف يدوياً
/// من D1 أو لم يُنشأ أصلاً) كان يُفشل دورة السحب كلها عند كل محاولة
/// → المؤشر لا يتحرك → full sync لا يكتمل → bootstrap يعيد المحاولة
/// عند كل إقلاع إلى الأبد (خطأ بيانات واحد = جهاز مجمّد نهائياً).
///
/// السياسة القديمة (2026-09-09): تدرّج 3 دورات لكن عبر «تراجع المؤشر» —
/// كل دورة بهوية محجوبة تعيد سحب كل الصفحات وتطبيقها من أول الدورة
/// (7,300+ صف) حتى تكتمل العتبة. مكلف زمنياً جداً على شبكة يمن، ويولّد
/// تكراراً مزعجاً في مركز الأخطاء (تقرير 2026-09-14: 55 سجلاً محجوباً).
///
/// السياسة المصححة (2026-09-15 — طلب المستخدم: تسريع السحب وإصلاح
/// تجميد المؤشر): «سجل انتظار» بالحمولات الكاملة —
///   1. المؤشر يتقدم في نفس الدورة طالما الصفحات نفسها سليمة (لا شبكة/
///      HTTP/JSON/جداول متخطاة) — الصفحات طبّقت كلها فعلاً.
///   2. كل سجل محجوب (أب غير محلول أو تعارض مفتاح فريد) تُحفظ حمولته
///      كاملة في [_blockedPending] (persistent) ويُعاد حلّه من الحمولة
///      في كل دورة — بلا إعادة سحب أي صفحة إطلاقاً.
///   3. بعد [_quarantineBlockThreshold] دورات بنفس الهوية: يُنقل لسجل
///      الحجر [_quarantinedRecords] (مع حمولته أيضاً) ويتوقف عن إثقال
///      الدورة نهائياً.
///   4. الشفاء تلقائي من الحمولة: وصول الأب أو تفريغ المفتاح أو وصول
///      tombstone → التطبيق ينجح في إعادة المحاولة الدورية → يُمسح من
///      السجلين معاً. (وعد السابق كان معلقاً على إعادة بث الصف من
///      الخادم — الآن محقق دائماً لأن الحمولة محلية.)
///
/// الملكية: هذا المكوّن يملك الحالة والسياسة؛ مدير المزامنة يملك تدفق
/// الدورة والتسجيل (logging) — تُعاد الحقائق لا الرسائل.
class PullQuarantine {
  static const String _kQuarantineCountsKey = 'cf_pull_orphan_block_counts';
  static const String _kQuarantinedKey = 'cf_pull_quarantined_records';
  static const String _kBlockedPendingKey = 'cf_pull_blocked_pending';
  static const int _quarantineBlockThreshold = 3;

  /// عدد الدورات التي حُجب فيها كل سجل معتّق (identity = 'entity/uuid').
  final Map<String, int> _orphanBlockCounts = <String, int>{};

  /// سجل الحجر الصحي: identity -> بيانات التشخيص + حمولة السجل (record)
  /// لإعادة المحاولة الدورية (الشفاء من الحمولة المحلية).
  final Map<String, Map<String, dynamic>> _quarantinedRecords =
      <String, Map<String, dynamic>>{};

  /// ✅ (2026-09-15) سجل الانتظار: المحجوبون تحت العتبة مع حمولاتهم —
  /// يُعاد حلّهم من الحمولة كل دورة بدل إعادة سحب الصفحات عبر تراجع
  /// المؤشر. السقف يمنع انفجار التخزين في حالات مرضية قصوى.
  final Map<String, PullRecord> _blockedPending = <String, PullRecord>{};

  /// سقف سجل الانتظار (عدد السجلات). تجاوزه = عزل فوري للفائض الأقرب
  /// للعتبة (صمام أمان — الحالة الواقعية عشرات).
  static const int _blockedPendingCap = 300;

  /// ✅ (M2) سقف سجل الحجر الصحي — كان بلا حد والحمولات الكاملة تُخزَّن
  /// في SharedPreferences (بطء كل initialize + خطر TransactionTooLarge
  /// على أندرويد). الإخلاء بالأقدم first_seen مع عدّاده (بداية نظيفة
  /// إن عاد الصف ببث خادمي لاحق).
  static const int _quarantineCap = 300;

  /// سقف محاولات الشفاء الدورية للمعزولين في كل دورة (تكلفة محلية صفرية
  /// تقريباً لكن بلا سقف قد تنمو مع تاريخ الحجب الطويل).
  static const int _quarantineHealRetryLimit = 100;

  /// عتبة الدورات قبل النقل من الانتظار إلى الحجر (لرسائل التشخيص).
  int get blockThreshold => _quarantineBlockThreshold;

  /// سقف سجل الانتظار (لرسائل التشخيص).
  int get blockedPendingCap => _blockedPendingCap;

  /// سقف سجل الحجر (لرسائل التشخيص).
  int get quarantineCap => _quarantineCap;

  /// هوية السجل عبر السجلين ('entity/uuid').
  static String identity(String entity, String? localUuid) =>
      '$entity/$localUuid';

  /// ✅ (2026-10-05) هوية محسوبة من السجل كله — للصفوف التي فقدت
  /// local_uuid على السلك (كاتب أجنبي/استعادة ناقصة). تسمح بإدخال
  /// هذه الصفوف سلّم الانتظار/الحجر بدل الهوية المشتركة
  /// 'entity/null' التي كانت تُسقط كل الصفوف عدا واحد من المحاسبة.
  /// المفتاح الاحتياطي: id الصف الخادمي (مستقر عبر الدورات ما لم
  /// يُستبدل الصف كلياً — وعندها يعاد حسابه من جديد).
  static String identityForRecord(String entity, Map<String, dynamic> record) {
    final uuid = record['local_uuid']?.toString();
    if (uuid != null && uuid.isNotEmpty) return '$entity/$uuid';
    return '$entity#no-uuid/${record['id'] ?? record['server_id'] ?? '?'}';
  }

  /// ✅ (2026-10-05) هوية موحّدة داخلياً لكل سجل في السجلين — نفس
  /// دالة [identityForRecord]: الصفوف بلا local_uuid تُميّز بـ id
  /// الصف الخادمي بدل الانهيار على 'entity/null'. تعتمدها promote /
  /// stageWaiting / evictWaitingOverflow حتى لا تعيد اشتقاق هوية
  /// مختلفة عن مفاتيح خريطة المحاسبة (فجوة كان يبتلعها التخطي).
  static String _identityOf(PullRecord item) =>
      identityForRecord(item.entity, item.record);

  /// ✅ (M2) طابع first_seen للمقارنة أثناء الإخلاء — غياب/تشوه = 0
  /// (الأقدم) فيُخلى أولاً بأمان.
  static int firstSeen(Map<String, dynamic> entry) =>
      (entry['first_seen'] as num?)?.toInt() ?? 0;

  /// هل يوجد عمل معلّق (انتظار أو حجر) يستحق دورة إعادة حل؟
  bool get hasWork =>
      _blockedPending.isNotEmpty || _quarantinedRecords.isNotEmpty;

  /// هل سجل الانتظار غير فارغ؟
  bool get hasBlocked => _blockedPending.isNotEmpty;

  /// هل سجل الحجر غير فارغ؟
  bool get hasQuarantined => _quarantinedRecords.isNotEmpty;

  /// ✅ (مراجعة #2+#16) استعادة حالة الحجر الصحي للصفوف اليتيمة —
  /// يجب أن تعيش عبر الجلسات حتى يُقارب bootstrap خلال دورات متتالية.
  void restore(SharedPreferences prefs) {
    try {
      final countsRaw = prefs.getString(_kQuarantineCountsKey);
      if (countsRaw != null && countsRaw.isNotEmpty) {
        final decoded = jsonDecode(countsRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          _orphanBlockCounts[key] = (value as num?)?.toInt() ?? 0;
        });
      }
      final quarantinedRaw = prefs.getString(_kQuarantinedKey);
      if (quarantinedRaw != null && quarantinedRaw.isNotEmpty) {
        final decoded = jsonDecode(quarantinedRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map) {
            _quarantinedRecords[key] = Map<String, dynamic>.from(value);
          }
        });
      }
      // ✅ (2026-09-15) استعادة سجل الانتظار (الحمولات المحجوبة تحت
      // العتبة) — تعيش عبر الجلسات كالحجر، وإلا فُقدت حمولة سجل
      // محجوب عند إعادة تشغيل التطبيق وعاد الحجب من الصفر.
      final pendingRaw = prefs.getString(_kBlockedPendingKey);
      if (pendingRaw != null && pendingRaw.isNotEmpty) {
        final decoded = jsonDecode(pendingRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map &&
              value['entity'] != null &&
              value['record'] is Map) {
            _blockedPending[key] = (
              entity: value['entity'].toString(),
              record: Map<String, dynamic>.from(value['record'] as Map),
            );
          }
        });
      }
      if (_orphanBlockCounts.isNotEmpty ||
          _quarantinedRecords.isNotEmpty ||
          _blockedPending.isNotEmpty) {
        debugPrint(
          '🏥 Quarantine state restored: ${_orphanBlockCounts.length} '
          'counter(s), ${_quarantinedRecords.length} quarantined, '
          '${_blockedPending.length} pending',
        );
      }
    } catch (e) {
      debugPrint('⚠️ quarantine state load failed: $e');
    }
  }

  /// يحفظ الحالة الثلاثية (عدّادات + حجر + انتظار) في prefs.
  Future<void> persist(SharedPreferences prefs) async {
    try {
      // ✅ (M2) تقليم عدّادات يتيمة لا تنتمي لأي سجل — تمنع نمو الخريطة
      // بلا حد عبر الجلسات (الشفاء/الإخلاء يزيلان السجلات وقد يُبقيان
      // العدّاد).
      _orphanBlockCounts.removeWhere(
        (key, _) =>
            !_quarantinedRecords.containsKey(key) &&
            !_blockedPending.containsKey(key),
      );
      await prefs.setString(
        _kQuarantineCountsKey,
        jsonEncode(_orphanBlockCounts),
      );
      await prefs.setString(_kQuarantinedKey, jsonEncode(_quarantinedRecords));
      // ✅ (2026-09-15) حمولات سجل الانتظار تُخزَّن كاملة (persistent).
      await prefs.setString(
        _kBlockedPendingKey,
        jsonEncode({
          for (final entry in _blockedPending.entries)
            entry.key: {
              'entity': entry.value.entity,
              'record': entry.value.record,
            },
        }),
      );
    } catch (e) {
      debugPrint('⚠️ quarantine state persist failed: $e');
    }
  }

  /// يفرغ السجلات الثلاثة (عزل singleton بين الاختبارات).
  void clearAll() {
    _orphanBlockCounts.clear();
    _quarantinedRecords.clear();
    _blockedPending.clear();
  }

  /// هل السجل معزول حالياً؟
  bool isQuarantined(String entity, String? localUuid) =>
      _quarantinedRecords.containsKey(identity(entity, localUuid));

  /// يمسح السجل من الحجر وسجل الانتظار وعدّاد الحجب — يكتب prefs فقط
  /// حين يُزال شيء فعلاً. (M3: إغفال سجل الانتظار هنا كان يُبقي حمولة
  /// ميتة تُعاد محاولتها دورة إضافية هدراً.)
  Future<void> clear(String entity, String? localUuid) async {
    final id = identity(entity, localUuid);
    final removedLedger = _quarantinedRecords.remove(id) != null;
    final removedPending = _blockedPending.remove(id) != null;
    final removedCounter = _orphanBlockCounts.remove(id) != null;
    if (removedLedger || removedPending || removedCounter) {
      final prefs = await SharedPreferences.getInstance();
      await persist(prefs);
    }
  }

  /// لقطة سجل الانتظار لإعادة الحل (نسخة — آمنة أثناء التكرار).
  List<PullRecord> pendingForRetry() => List.of(_blockedPending.values);

  /// شُفي عنصر من سجل الانتظار (أو تحوّل لمتعارض — عندها يبقى عدّاده
  /// معلقاً حتى العتبة). يعيد هل أُزيل شيء (يستحق persist).
  bool noteLedgerHealed(String id, {required bool keepCounter}) {
    if (_blockedPending.remove(id) == null) return false;
    if (!keepCounter) _orphanBlockCounts.remove(id);
    return true;
  }

  /// مرشحو الشفاء الدوري من الحجر (بسقف الدورة).
  List<PullRecord> collectHealCandidates() {
    final retryItems = <PullRecord>[];
    for (final entry in _quarantinedRecords.entries) {
      if (retryItems.length >= _quarantineHealRetryLimit) break;
      final raw = entry.value['record'];
      final entity = entry.value['entity']?.toString();
      if (raw is Map && raw.isNotEmpty && entity != null) {
        retryItems.add((
          entity: entity,
          record: Map<String, dynamic>.from(raw),
        ));
      }
    }
    return retryItems;
  }

  /// شُفي عنصر معزول (يعيد هل أُزيل — يستحق persist).
  bool noteQuarantineHealed(String id) {
    if (_quarantinedRecords.remove(id) == null) return false;
    _orphanBlockCounts.remove(id);
    return true;
  }

  /// محاسبة الدورة: يرفع عدّاد كل هوية ويقسّمها انتظار/حجر.
  ({List<PullRecord> toWait, List<PullRecord> toQuarantine}) accountBlocked(
    Map<String, PullRecord> pool,
  ) {
    final toWait = <PullRecord>[];
    final toQuarantine = <PullRecord>[];
    for (final entry in pool.entries) {
      final count = (_orphanBlockCounts[entry.key] ?? 0) + 1;
      _orphanBlockCounts[entry.key] = count;
      if (count >= _quarantineBlockThreshold) {
        toQuarantine.add(entry.value);
      } else {
        toWait.add(entry.value);
      }
    }
    return (toWait: toWait, toQuarantine: toQuarantine);
  }

  /// ينقل عناصر للحجر مع حمولاتها (أساس الشفاء الدوري) ويعيد المعزولة
  /// حديثاً (للإشعار) وهل مُسّ سجل الانتظار (يستحق persist).
  ({List<PullRecord> fresh, bool ledgerTouched}) promote(
    List<PullRecord> items,
    int nowSec,
  ) {
    final fresh = <PullRecord>[];
    var ledgerTouched = false;
    for (final item in items) {
      // ✅ (2026-10-05) _identityOf بدل identity — الصفوف بلا
      // local_uuid تحصل على هويتها المستقرة من id الصف الخادمي.
      final id = _identityOf(item);
      // ✅ (2026-09-09) إشعار الحجر فقط للهويات المعزولة حديثاً —
      // السجل المعزول سابقاً يعاد عزله صامتاً بلا إزعاج.
      if (!_quarantinedRecords.containsKey(id)) {
        fresh.add(item);
      }
      // ✅ (2026-09-15) الحمولة تُحفظ مع الحجر — أساس الشفاء
      // الدوري من الحمولة أعلاه.
      _quarantinedRecords[id] = <String, dynamic>{
        'entity': item.entity,
        'local_uuid': item.record['local_uuid']?.toString(),
        'first_seen': nowSec,
        'updated_at': item.record['updated_at'],
        'record': item.record,
      };
      // خرج من سجل الانتظار (إن كان فيه) — الحجر يحل محله.
      if (_blockedPending.remove(id) != null) {
        ledgerTouched = true;
      }
    }
    return (fresh: fresh, ledgerTouched: ledgerTouched);
  }

  /// يحفظ عناصر تحت العتبة في سجل الانتظار ويعيد الهويات الجديدة.
  Set<String> stageWaiting(List<PullRecord> items) {
    final newEntries = <String>{};
    for (final item in items) {
      // ✅ (2026-10-05) _identityOf — تطابق مفاتيح المحاسبة.
      final id = _identityOf(item);
      if (!_blockedPending.containsKey(id)) {
        newEntries.add(id);
      }
      _blockedPending[id] = item;
    }
    return newEntries;
  }

  /// صمام الأمان: الفائض عن سقف الانتظار (الأقرب للعتبة) يُعزل فوراً
  /// وحمولته تبقى في الحجر للشفاء الدوري. يعيد عدد المعزولين.
  int evictWaitingOverflow(int nowSec) {
    if (_blockedPending.length <= _blockedPendingCap) return 0;
    final overflow =
        (_blockedPending.keys.toList()..sort(
              (a, b) => (_orphanBlockCounts[b] ?? 0).compareTo(
                _orphanBlockCounts[a] ?? 0,
              ),
            ))
            .take(_blockedPending.length - _blockedPendingCap)
            .toList();
    for (final id in overflow) {
      final item = _blockedPending.remove(id)!;
      if (!_quarantinedRecords.containsKey(id)) {
        _quarantinedRecords[id] = <String, dynamic>{
          'entity': item.entity,
          'local_uuid': item.record['local_uuid']?.toString(),
          'first_seen': nowSec,
          'updated_at': item.record['updated_at'],
          'record': item.record,
        };
      }
    }
    return overflow.length;
  }

  /// ✅ (M2) فرض سقف الحجر — الإخلاء بالأقدم first_seen مع عدّاده
  /// (بداية نظيفة إن عاد الصف ببث خادمي لاحق). يعيد عدد المُخلين.
  int evictQuarantineOverflow() {
    if (_quarantinedRecords.length <= _quarantineCap) return 0;
    final ordered = _quarantinedRecords.entries.toList()
      ..sort(
        (a, b) => firstSeen(
          a.value,
        ).compareTo(firstSeen(b.value)),
      );
    final victims = ordered
        .take(_quarantinedRecords.length - _quarantineCap)
        .toList();
    for (final victim in victims) {
      _quarantinedRecords.remove(victim.key);
      _orphanBlockCounts.remove(victim.key);
    }
    return victims.length;
  }
}
