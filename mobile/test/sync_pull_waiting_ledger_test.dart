// ═══════════════════════════════════════════════════════════════
//  sync_pull_waiting_ledger_test.dart — 2026-09-15
//
//  عقد «سجل الانتظار» — إصلاح تقرير أخطاء 2026-09-14:
//  «55 سجل محجوب (أب غير محلول أو تعارض مفتاح فريد) — تجميد مؤشر
//  السحب» + «فشل مزامنة جزئي» المتكرر.
//
//  التصميم القديم: المحجوب يُفشل الدورة → المؤشر يتراجع لأول الدورة
//  → إعادة سحب كل الصفحات وتطبيقها كل دورة (7,300+ صف) حتى اكتمال
//  عتبة الحجر (3 دورات). مكلف زمنياً ومزعج في مركز الأخطاء.
//
//  العقد الجديد: الصفحات السليمة = نجاح ومؤشر يتقدم؛ المحجوب تُحفظ
//  حمولته كاملة في سجل الانتظار (persistent) وتُعاد محاولته من
//  الحمولة في بداية كل دورة — بلا إعادة سحب أي صفحة. بعد العتبة
//  ينتقل لسجل الحجر (مع حمولته) وتستمر محاولات الشفاء الدورية.
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _syncFields(
  String uuid,
  int updatedAt, {
  int? serverId,
  String device = 'other-device',
}) => {
  'id': serverId,
  'local_uuid': uuid,
  'created_at': updatedAt,
  'updated_at': updatedAt,
  'last_modified': updatedAt,
  'created_at_epoch': 0,
  'last_modified_epoch': 0,
  'version': 1,
  'origin': 'server',
  'vector_clock': '{}',
  'device_id': device,
};

Map<String, dynamic> _employeeRow(
  String uuid, {
  int? serverId,
  int updatedAt = 1700000500,
}) => {
  ..._syncFields(uuid, updatedAt, serverId: serverId),
  'name': 'موظف سجل الانتظار',
  'basic_salary': 1000.0,
  'position': 'موظف',
  'status': 'active',
};

Map<String, dynamic> _withdrawalRow(
  String uuid, {
  required int employeeId,
  int updatedAt = 1700000800,
}) => {
  ..._syncFields(uuid, updatedAt),
  'employee_id': employeeId,
  'amount': 250.0,
  'withdraw_date': '2026-09-15',
  'hotel_day_key': '2026-09-15',
  'withdrawal_type': 'cash',
  'description': 'سحب عقد سجل الانتظار',
};

/// يخدم الصفحات بالترتيب عبر دورات sync متتالية على نفس المدير.
class _MultiCycleQueueClient extends http.BaseClient {
  _MultiCycleQueueClient(this.pages);

  final List<Map<String, dynamic>> pages;
  final urls = <Uri>[];
  int _served = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    urls.add(request.url);
    if (request.method != 'GET') {
      throw StateError('unexpected ${request.method} ${request.url}');
    }
    if (_served >= pages.length) {
      throw StateError('exhausted after ${pages.length} pages');
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(pages[_served++]))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
    });
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager(http.Client client) async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: client,
      token: 'test-token',
      deviceId: 'waiting-ledger-device',
      fullSyncCompleted: false,
      lastPullCursor: 0,
    );
    return manager;
  }

  Future<Object?> pref(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(key);
  }

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  Future<Object?> cell(String table, String column, String byUuid) async {
    final row = await db
        .customSelect(
          'SELECT $column AS v FROM $table WHERE local_uuid = ?',
          variables: [Variable(byUuid)],
        )
        .getSingleOrNull();
    return row?.data['v'];
  }

  Map<String, dynamic> pendingMap(Object? raw) =>
      jsonDecode(raw.toString()) as Map<String, dynamic>;

  test(
    'المحجوب يدخل سجل الانتظار والدورة تنجح، ثم يُشفى من الحمولة عند وصول الأب',
    () async {
      // الدورة 1: سحوبة بدون موظفها (employee_id 55) — تُؤجل ثم تفشل
      // إعادة محاولتها → حمولتها في سجل الانتظار، والدورة ✅ تنجح
      // والمؤشر يتقدم (القديم: فشل + تراجع مؤشر + إعادة سحب كل الصفحات).
      final client = _MultiCycleQueueClient([
        {
          'changes': [_withdrawalRow('sw-orphan', employeeId: 55)],
          'cursor': '1700000800',
          'has_more': false,
          'errors': <dynamic>[],
        },
        // الدورة 2: صفحة مسح الحذفيات (فارغة) + صفحة الدلتا الفعلية:
        // الموظف وصل — إعادة محاولة الحمولة تُشفي السحوبة وتترجم أبها.
        {
          'changes': <dynamic>[],
          'cursor': '0',
          'has_more': false,
          'errors': <dynamic>[],
        },
        {
          'changes': [_employeeRow('emp-1', serverId: 55)],
          'cursor': '1700000810',
          'has_more': false,
          'errors': <dynamic>[],
        },
      ]);
      final manager = await makeManager(client);

      final first = await manager.sync();
      expect(first.status, SyncStatus.success, reason: 'الصفحات سليمة = نجاح');
      expect(await pref('cf_last_pull_cursor'), 1700000800);
      expect(await count('salary_withdrawals'), 0);
      final pending1 = pendingMap(await pref('cf_pull_blocked_pending'));
      expect(pending1.keys, contains('salary_withdrawals/sw-orphan'));
      expect(
        ((pending1['salary_withdrawals/sw-orphan']
                as Map<String, dynamic>)['record']
            as Map<String, dynamic>)['local_uuid'],
        'sw-orphan',
        reason: 'الحمولة كاملة في السجل — أساس إعادة الحلول بلا إعادة سحب',
      );

      final second = await manager.sync();
      expect(second.status, SyncStatus.success);
      // الشفاء من الحمولة: السحوبة طُبّقت بأبها المترجم، والسجل تفريغ.
      expect(await count('salary_withdrawals'), 1);
      expect(await cell('salary_withdrawals', 'employee_id', 'sw-orphan'), 1);
      expect(
        pendingMap(await pref('cf_pull_blocked_pending')),
        isEmpty,
        reason: 'المُشفى يخرج من سجل الانتظار نهائياً',
      );
    },
  );

  test(
    'المعزول بعد العتبة يُشفى من حمولته المحفوظة عند وصول أبِه لاحقاً',
    () async {
      final client = _MultiCycleQueueClient([
        // الدورة 1: السحوبة اليتيمة (بلا موظف أبداً).
        {
          'changes': [_withdrawalRow('sw-late', employeeId: 77)],
          'cursor': '1700000800',
          'has_more': false,
          'errors': <dynamic>[],
        },
        // الدورتان 2 و3: صفحة مسح الحذفيات + دلتا فارغة — العدّاد يصل 3.
        ...List.generate(
          2,
          (i) => <String, dynamic>{
            'changes': <dynamic>[],
            'cursor': '17000008${i}1',
            'has_more': false,
            'errors': <dynamic>[],
          },
        ),
        // الدورة 4: الموظف وصل أخيراً — الشفاء من حمولة المعزول.
        {
          'changes': <dynamic>[],
          'cursor': '0',
          'has_more': false,
          'errors': <dynamic>[],
        },
        {
          'changes': [_employeeRow('emp-late', serverId: 77)],
          'cursor': '1700000831',
          'has_more': false,
          'errors': <dynamic>[],
        },
      ]);
      final manager = await makeManager(client);

      // دورات الانتظار الثلاث كلها تنجح (لا تجميد).
      for (var i = 0; i < 3; i++) {
        final result = await manager.sync();
        expect(
          result.status,
          SyncStatus.success,
          reason: 'الدورة ${i + 1}: اليتيم لا يُفشل الدورة بعد اليوم',
        );
      }
      // العتبة اكتملت: عُزل مع حمولته.
      final quarantined = pendingMap(await pref('cf_pull_quarantined_records'));
      expect(quarantined.keys, contains('salary_withdrawals/sw-late'));
      expect(await count('salary_withdrawals'), 0);

      // الدورة 4: الأب وصل — الشفاء من الحمولة يُدرج السحوبة بمفتاح
      // الأب المترجم ويُخرجها من الحجر (تحقيق وعد رسالة الحجر).
      final fourth = await manager.sync();
      expect(fourth.status, SyncStatus.success);
      expect(await count('salary_withdrawals'), 1);
      expect(await cell('salary_withdrawals', 'employee_id', 'sw-late'), 1);
      expect(
        pendingMap(await pref('cf_pull_quarantined_records')),
        isNot(contains('salary_withdrawals/sw-late')),
      );
    },
  );
}
