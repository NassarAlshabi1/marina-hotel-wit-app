// test/services/shift_receipts_cloud_test.dart
//
// اختبارات خدمة الاستلامات السحابية لبطاقة «استلامات المستخدمين الآخرين
// في النوبات» — بلا شبكة:
// 1) hotelDayQuery يبني استعلام Appwrite الصحيح لليوم الفندقي.
// 2) aggregatePayments يجمع الدفعات حسب (المستخدم، الاسم، الجلسة) ويطبّق
//    الفلاتر نفسها المستخدمة في استعلام SQL المحلي.
import 'dart:convert';

import 'package:appwrite/models.dart' as models;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/shift_receipts_cloud_service.dart';

models.Document _doc(String id, Map<String, dynamic> data) {
  return models.Document(
    $id: id,
    $sequence: 1,
    $collectionId: 'payments',
    $databaseId: 'test_db',
    $createdAt: '2026-09-14T00:00:00.000Z',
    $updatedAt: '2026-09-14T00:00:00.000Z',
    $permissions: const <String>[],
    data: data,
  );
}

Map<String, dynamic> _payment({
  String id = 'p1',
  double amount = 500,
  String sessionUuid = 'sess-1',
  String name = 'المستخدم 1',
  String cloudId = 'cloud-1',
  int userId = 11,
  bool? voided,
  bool? pendingBalance,
  String? deletedAt,
}) {
  return <String, dynamic>{
    'amount': amount,
    'hotelDayKey': '2026-09-14',
    'receivedSessionUuid': sessionUuid,
    'receivedByName': name,
    'receivedByCloudId': cloudId,
    'receivedByUserId': userId,
    if (voided != null) 'isVoided': voided,
    if (pendingBalance != null) 'isPendingBalance': pendingBalance,
    if (deletedAt != null) 'deletedAt': deletedAt,
  };
}

void main() {
  group('ShiftReceiptsCloudService.hotelDayQuery', () {
    test('يبني استعلام equal بصيغة Appwrite JSON الصحيحة', () {
      final q = ShiftReceiptsCloudService.hotelDayQuery('2026-09-14');
      final decoded = jsonDecode(q) as Map<String, dynamic>;
      expect(decoded['method'], 'equal');
      expect(decoded['attribute'], 'hotelDayKey');
      expect(decoded['values'], ['2026-09-14']);
    });
  });

  group('ShiftReceiptsCloudService.aggregatePayments', () {
    test('يجمع دفعات المستخدم نفسه في نفس الجلسة (500 ثم 1000 = 1500)', () {
      final docs = [
        _doc('p1', _payment(amount: 500)),
        _doc('p2', _payment(id: 'p2', amount: 1000)),
      ];
      final rows = ShiftReceiptsCloudService.aggregatePayments(docs);
      expect(rows, hasLength(1));
      expect(rows.first.userName, 'المستخدم 1');
      expect(rows.first.totalAmount, 1500);
      expect(rows.first.paymentCount, 2);
      expect(rows.first.userId, 11);
    });

    test('يجمع كل جلسات اليوم الفندقي للمستخدم نفسه في سطر واحد', () {
      final docs = [
        _doc('p1', _payment(amount: 500)),
        _doc('p2', _payment(id: 'p2', amount: 700, sessionUuid: 'sess-2')),
        _doc('p3', _payment(id: 'p3', amount: 300, sessionUuid: 'sess-3')),
      ];
      final rows = ShiftReceiptsCloudService.aggregatePayments(docs);
      // ثلاث جلسات = سطر واحد بإجمالي مدفوعات اليوم الفندقي للمستخدم.
      expect(rows, hasLength(1));
      expect(rows.first.totalAmount, 1500);
      expect(rows.first.paymentCount, 3);
      expect(rows.first.userName, 'المستخدم 1');
    });

    test('يستبعد المحذوف/الملغى/رصيد السحب المؤجل/بلا جلسة', () {
      final docs = [
        _doc('d1', _payment(deletedAt: '2026-09-14T10:00:00.000Z')),
        _doc('d2', _payment(id: 'd2', voided: true)),
        _doc('d3', _payment(id: 'd3', pendingBalance: true)),
        _doc('d4', _payment(id: 'd4', sessionUuid: '')),
      ];
      expect(ShiftReceiptsCloudService.aggregatePayments(docs), isEmpty);
    });

    test('يستبعد الدفعات بلا مستلم (اسم وcloudId فارغان)', () {
      final docs = [_doc('p1', _payment(name: '', cloudId: ''))];
      expect(ShiftReceiptsCloudService.aggregatePayments(docs), isEmpty);
    });

    test('يستثني المستخدم الحالي بالمعرّف السحابي أو بالاسم', () {
      final docs = [
        _doc('p1', _payment(cloudId: 'me-cloud')),
        _doc('p2', _payment(id: 'p2', cloudId: 'c2', name: 'أنا بالاسم')),
        _doc('p3', _payment(id: 'p3', cloudId: 'c3', name: 'زائد')),
      ];
      final rows = ShiftReceiptsCloudService.aggregatePayments(
        docs,
        excludedUserName: 'أنا بالاسم',
        excludedUserCloudId: 'me-cloud',
      );
      expect(rows, hasLength(1));
      expect(rows.first.userName, 'زائد');
    });

    test('الاسم الفارغ مع cloudId موجود يظهر «مستخدم غير معروف»', () {
      final docs = [
        _doc('p1', _payment(name: '', cloudId: 'cloud-x', amount: 250)),
      ];
      final rows = ShiftReceiptsCloudService.aggregatePayments(docs);
      expect(rows, hasLength(1));
      expect(rows.first.userName, 'مستخدم غير معروف');
      expect(rows.first.totalAmount, 250);
    });

    test('يرتب السطور تنازلياً حسب الإجمالي', () {
      final docs = [
        _doc(
          'p1',
          _payment(amount: 300, cloudId: 'c-a', name: 'صغير', userId: 1),
        ),
        _doc(
          'p2',
          _payment(
            id: 'p2',
            amount: 900,
            cloudId: 'c-b',
            name: 'كبير',
            userId: 2,
          ),
        ),
        _doc(
          'p3',
          _payment(
            id: 'p3',
            amount: 600,
            cloudId: 'c-c',
            name: 'متوسط',
            userId: 3,
          ),
        ),
      ];
      final rows = ShiftReceiptsCloudService.aggregatePayments(docs);
      expect(rows.map((r) => r.totalAmount).toList(), [900, 600, 300]);
    });
  });
}
