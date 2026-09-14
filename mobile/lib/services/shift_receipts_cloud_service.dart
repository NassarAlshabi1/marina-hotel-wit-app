// lib/services/shift_receipts_cloud_service.dart
// خدمة الاستلامات السحابية للمستخدمين في النوبات — قراءة فقط من Appwrite.
//
// تجعل بطاقة «استلامات المستخدمين الآخرين في النوبات» على الداشبورد تعمل
// سحابياً: تُسحب دفعات اليوم الفندقي الحالي مباشرة من السحابة وتُجمَّع
// حسب (المستخدم، الاسم، جلسة النوبة) — بمطابقة سلوك استعلام SQL المحلي
// في PaymentsRepository.watchPaymentShiftSummaries.
//
// الفرق الجوهري: المبالغ تُقرأ من السحابة مباشرة، فإذا استلم المستخدم 500
// ثم سجّل 1000 على جهازه، يظهر 1000 على أجهزة المدير/المشرف خلال ثوانٍ
// (دون انتظار دورة مزامنة كاملة).
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

import '../utils/debug_log.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'repositories/payments_repository.dart';

/// دالة سحب مستندات من مجموعة Appwrite — نقطة الحقن للاختبارات.
typedef PaymentDocsFetcher =
    Future<List<models.Document>> Function(
      String collectionId,
      List<String> queries,
    );

/// خدمة تجميع استلامات النوبات من السحابة — قراءة فقط.
class ShiftReceiptsCloudService {
  /// إنشاء الخدمة بدالة سحب مخصصة (يسمح بحقن بديل في الاختبارات).
  ShiftReceiptsCloudService({required PaymentDocsFetcher fetcher})
    : _fetcher = fetcher;

  final PaymentDocsFetcher _fetcher;

  /// غلاف جاهز يستخدم [AppwriteService.listAllDocuments] بلا ذاكرة مؤقتة
  /// (مع دعم الـ failover التلقائي إلى المشروع الثانوي إن كان مفعلاً).
  static PaymentDocsFetcher fetcherOf(AppwriteService service) =>
      (collectionId, queries) => service.listAllDocuments(
        collectionId: collectionId,
        queries: queries,
        useCache: false,
      );

  /// يرجع استعلام اليوم الفندقي المُمرر للسحابة — فصلٌ للاختبار.
  static String hotelDayQuery(String hotelDayKey) =>
      Query.equal('hotelDayKey', [hotelDayKey]);

  /// يسحب دفعات اليوم الفندقي [hotelDayKey] من السحابة ويجمعها حسب
  /// المستخدم/الجلسة مستثنياً المستخدم الحالي (يُعرض استلامه في بطاقة
  /// أخرى).
  ///
  /// يرمي الاستثناء عند فشل الشبكة — والمستدعي (المزود) يتحول حينها
  /// إلى البيانات المحلية كاحتياط.
  Future<List<PaymentShiftSummary>> fetchTodaySummaries({
    required String hotelDayKey,
    String? excludedUserName,
    String? excludedUserCloudId,
  }) async {
    final docs = await _fetcher(AppwriteConfig.paymentsCollectionId, [
      hotelDayQuery(hotelDayKey),
    ]);
    return aggregatePayments(
      docs,
      excludedUserName: excludedUserName,
      excludedUserCloudId: excludedUserCloudId,
    );
  }

  /// تجميع مستندات دفعات سحابية إلى ملخصات حسب (المستخدم، الاسم، الجلسة).
  ///
  /// الفلاتر مطابقة لاستعلام SQL المحلي:
  /// - تُستبعد الدفعات المحذوفة/الملغاة/رصيد السحب المؤجل
  /// - تُستبعد الدفعات غير المنسوبة إلى جلسة (receivedSessionUuid فارغ)
  /// - تُستبعد الدفعات بلا مستلم (اسم فارغ وcloudId فارغ)
  /// - الاسم الفارغ يُعرض «مستخدم غير معروف» (مطابق لـ COALESCE المحلي)
  static List<PaymentShiftSummary> aggregatePayments(
    List<models.Document> docs, {
    String? excludedUserName,
    String? excludedUserCloudId,
  }) {
    final buckets = <String, _Bucket>{};
    for (final doc in docs) {
      final data = doc.data;
      if (data['deletedAt'] != null) {
        continue;
      }
      if (data['isVoided'] == true) {
        continue;
      }
      if (data['isPendingBalance'] == true) {
        continue;
      }
      final sessionUuid = (data['receivedSessionUuid'] ?? '').toString();
      if (sessionUuid.isEmpty) {
        continue;
      }
      final rawName = (data['receivedByName'] ?? '').toString().trim();
      final cloudId = (data['receivedByCloudId'] ?? '').toString();
      if (rawName.isEmpty && cloudId.isEmpty) {
        continue;
      }

      // استثناء المستخدم الحالي (بطاقته تُعرض في قسم آخر).
      if (excludedUserCloudId != null &&
          excludedUserCloudId.isNotEmpty &&
          cloudId == excludedUserCloudId) {
        continue;
      }
      if (excludedUserName != null &&
          excludedUserName.isNotEmpty &&
          rawName == excludedUserName) {
        continue;
      }

      final userId = (data['receivedByUserId'] as num?)?.toInt() ?? 0;
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;

      // مفتاح التجميع مطابق لـ GROUP BY المحلي الثلاثي.
      final key = '$userId|$rawName|$sessionUuid';
      final bucket = buckets.putIfAbsent(key, _Bucket.new);
      bucket
        ..userId = userId
        ..rawName = rawName
        ..sessionUuid = sessionUuid
        ..totalAmount += amount
        ..paymentCount += 1;
    }

    final summaries =
        buckets.values
            .map(
              (b) => PaymentShiftSummary(
                userId: b.userId,
                userName: b.rawName.isEmpty ? 'مستخدم غير معروف' : b.rawName,
                sessionUuid: b.sessionUuid,
                totalAmount: b.totalAmount,
                paymentCount: b.paymentCount,
              ),
            )
            .toList()
          ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    dlog(() => '☁️ [ShiftReceipts] مستخلَصات سحابية: ${summaries.length}');
    return summaries;
  }
}

/// حاوية تجميع داخلية لكل (مستخدم، جلسة).
class _Bucket {
  int userId = 0;
  String rawName = '';
  String sessionUuid = '';
  double totalAmount = 0;
  int paymentCount = 0;
}
