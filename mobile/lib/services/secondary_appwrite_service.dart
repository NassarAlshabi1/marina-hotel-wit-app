// ignore_for_file: prefer_final_locals
import 'dart:convert';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_network_helper.dart';
import 'appwrite_sync_utils.dart';
import 'local_db.dart';
import 'secondary_appwrite_config.dart';

/// خدمة Appwrite الثانوية — تستخدم Appwrite SDK الرسمي (مثل Primary)
///
/// توفّر واجهة upsert للوجهة الثانوية. تُستخدم من SecondarySyncManager
/// فقط لتسليم سجلات outbox إلى خادم Appwrite الثانوي.
///
/// ❗ هذه الخدمة للكتابة فقط (push). السحب (pull) غير مُدعوم في هذه النسخة.
///
/// ✅ إصلاح (2026-06-28): استخدام AppwriteNetworkHelper لـ retry/timeout
/// مثل Primary. كتم أخطاء 404 المتوقعة في upsert probe.
class SecondaryAppwriteService {
  /// Factory singleton — يُرجع نفس الكائن دائماً.
  factory SecondaryAppwriteService() => _instance ??= SecondaryAppwriteService._();

  SecondaryAppwriteService._();
  static SecondaryAppwriteService? _instance;

  // ignore: prefer_constructors_over_static_methods
  static SecondaryAppwriteService get instance => SecondaryAppwriteService();

  final _networkHelper = AppwriteNetworkHelper();
  final _logger = AppwriteLogger();

  Client? _client;
  Databases? _databases;

  /// تهيئة الاتصال بـ Secondary (lazy)
  Future<void> ensureInitialized() async {
    if (_databases != null) return;

    if (!SecondaryAppwriteConfig.isConfigured) {
      throw StateError(
        'Secondary Appwrite is not configured. '
        'Call SecondaryAppwriteConfig.saveConfig() first.',
      );
    }

    final apiKey = SecondaryAppwriteConfig.apiKey;
    _client = Client().setEndpoint(SecondaryAppwriteConfig.endpoint).setProject(SecondaryAppwriteConfig.projectId);
    if (apiKey.isNotEmpty) {
      _client!.addHeader('X-Appwrite-Key', apiKey);
    }

    _databases = Databases(_client!);
  }

  /// إبطال الكاش (عند تغيير الإعدادات)
  void invalidate() {
    _client = null;
    _databases = null;
  }

  /// نتيجة اختبار الاتصال
  Future<ConnectionTestResult> testConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      await ensureInitialized();
      // ignore: deprecated_member_use
      await _databases!.listDocuments(
        databaseId: SecondaryAppwriteConfig.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      stopwatch.stop();
      return ConnectionTestResult(
        success: true,
        message: '✅ تم الاتصال بنجاح',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [Secondary] testConnection failed: $e');
      return ConnectionTestResult(success: false, message: '❌ فشل: $e', latencyMs: stopwatch.elapsedMilliseconds);
    }
  }

  /// رفع نسخة شاملة من كل البيانات المحلية إلى Secondary
  Future<FullBackupStats> uploadFullBackup({
    required void Function(String collection, int current, int total) onProgress,
    required void Function(String collectionName, int successCount, int failureCount) onCollectionComplete,
  }) async {
    await ensureInitialized();
    final db = DatabaseManager.instance;
    final stats = FullBackupStats();
    final collectionList = await getAllCollections(db);

    stats.totalCollections = collectionList.length;
    for (final coll in collectionList) {
      int successCount = 0;
      int failureCount = 0;
      int total = coll.records.length;
      int current = 0;

      for (final record in coll.records) {
        current++;
        onProgress(coll.name, current, total);

        // ✅ المعرّف يجب أن يأتي من localUuid حقيقي.
        // لا نرفع بمعرّف فارغ (يفسد النسخة ويُضلّل المستخدم) — بدل ذلك
        // نتخطّى السجل ونسجّله كخطأ صريح في الإحصائيات (fail fast / skip).
        final documentId = (record['localUuid'] as String?)?.trim();
        if (documentId == null || documentId.isEmpty) {
          failureCount++;
          const reason = 'تخطّي سجل بلا localUuid صالح (معرّف فارغ)';
          stats.failuresByCollection
              .putIfAbsent(coll.name, () => [])
              .add(FullBackupFailure(reason: reason, collectionName: coll.name));
          stats.errorsByReason[reason] = (stats.errorsByReason[reason] ?? 0) + 1;
          continue;
        }

        try {
          // ✅ P0: استخدام sanitizePayload بدلاً من filterPayloadForCollection
          // لضمان تحويل الأنواع (double→int), تحويل camelCase, إزالة الحقول الداخلية.
          final sanitized = AppwriteSyncUtils.sanitizePayload(coll.name, record, collectionId: coll.collectionId);
          // ✅ P1: إضافة syncTimestamp + idempotencyKey—حقول كانت مفقودة من ToMaps
          final enhancedData = Map<String, dynamic>.from(sanitized);
          final now = DateTime.now().millisecondsSinceEpoch;
          enhancedData['syncTimestamp'] ??= now;
          enhancedData['idempotencyKey'] ??= 'backup_${coll.name}_${documentId}_$now';
          enhancedData['sync_origin'] ??= 'secondary_backup';
          await upsertDocument(collectionId: coll.collectionId, documentId: documentId, data: enhancedData);
          successCount++;
        } catch (e) {
          failureCount++;
          final reason = e.toString();
          final failure = FullBackupFailure(
            documentId: documentId,
            reason: reason,
            collectionName: coll.name,
            timestamp: DateTime.now(),
          );
          stats.failuresByCollection.putIfAbsent(coll.name, () => []).add(failure);
          // ✅ P3: failedRecords كانت تبقى فارغة—الآن تُملأ بكل فشل
          stats.failedRecords.add(failure);
          // ✅ توسيع error truncation من 100→500 حرف لتحليل أفضل
          final reasonShort = reason.length > 500 ? reason.substring(0, 500) : reason;
          stats.errorsByReason[reasonShort] = (stats.errorsByReason[reasonShort] ?? 0) + 1;
        }
      }

      onCollectionComplete(coll.name, successCount, failureCount);
      stats.collectionDetails.add({
        'name': coll.name,
        'total': total,
        'success': successCount,
        'failure': failureCount,
        'isFullySuccessful': failureCount == 0,
      });
      stats.successCount += successCount;
      stats.failureCount += failureCount;
      if (failureCount == 0) {
        stats.fullySuccessfulCollections++;
      } else {
        stats.failedCollections++;
      }
      stats.collectionNames.add(coll.name);
    }

    return stats;
  }

  static final RegExp _unknownAttrPattern = RegExp(r'Unknown attribute:\s*"([^"]+)"');

  /// استخراج اسم السمة غير المعروفة من خطأ Appwrite (إن وُجد).
  String? _extractUnknownAttribute(AppwriteException e) {
    final type = e.type ?? '';
    final msg = e.message ?? e.toString();
    final isStructureError =
        e.code == 400 &&
        (type.contains('document_invalid_structure') ||
            msg.contains('Invalid document structure') ||
            msg.contains('Unknown attribute'));
    if (!isStructureError) return null;
    return _unknownAttrPattern.firstMatch(msg)?.group(1);
  }

  /// Upsert مستند في Secondary — غلاف صامد أمام انحراف المخطط: إذا رفض
  /// الخادم حقلاً غير معروف (Unknown attribute) نُزيله ونعيد المحاولة، بدل
  /// فشل السجل كاملاً (نفس سلوك Primary).
  Future<models.Document> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    var workingData = Map<String, dynamic>.from(data);
    final maxRetries = workingData.length + 1;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _upsertDocumentOnce(collectionId: collectionId, documentId: documentId, data: workingData);
      } on AppwriteException catch (e) {
        final unknownAttr = _extractUnknownAttribute(e);
        if (unknownAttr != null && workingData.containsKey(unknownAttr) && attempt < maxRetries) {
          workingData = Map<String, dynamic>.from(workingData)..remove(unknownAttr);
          _logger.warning(
            '⚠️ [Secondary] حقل غير معروف في المخطط — أُزيل وأُعيدت المحاولة: '
            '$collectionId.$unknownAttr',
            tag: 'SCHEMA_DRIFT',
          );
          continue;
        }
        rethrow;
      }
    }
  }

  Future<models.Document> _upsertDocumentOnce({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await ensureInitialized();
    final dbId = SecondaryAppwriteConfig.databaseId;

    bool isNotFound(AppwriteException e) =>
        e.code == 404 || (e.type ?? '').contains('document_not_found') || e.toString().contains('document_not_found');

    bool isAlreadyExists(AppwriteException e) =>
        e.code == 409 ||
        (e.type ?? '').contains('document_already_exists') ||
        (e.type ?? '').contains('conflict') ||
        e.toString().contains('document_already_exists');

    bool isRateLimit(AppwriteException e) =>
        e.code == 429 ||
        (e.type ?? '').contains('rate_limit') ||
        (e.type ?? '').contains('general_rate_limit_exceeded') ||
        e.toString().contains('429') ||
        e.toString().contains('rate limit');

    // ✅ معالجة ID بدون شرطات (نفس Primary)
    final altDocumentId = documentId.contains('-') ? documentId.replaceAll('-', '') : '';

    Future<models.Document> doUpdate(String id, {bool suppressErrorLog = false}) async {
      return _networkHelper.withRetryAndTimeout(
        operation: () =>
            // ignore: deprecated_member_use
            _databases!.updateDocument(databaseId: dbId, collectionId: collectionId, documentId: id, data: data),
        operationName: 'secondary_updateDocument',
        suppressErrorLog: suppressErrorLog,
      );
    }

    Future<models.Document> doCreate() async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.createDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        ),
        operationName: 'secondary_createDocument',
        suppressErrorLog: true,
      );
    }

    // الخطوة 1: updateDocument بالـ ID الأصلي
    // ✅ معالجة 429: انتظر قليلاً ثم انتقل مباشرة للإنشاء بدل إعادة الرمي
    // (الإعادة تستهلك كل محاولات withRetry قبل وصول 404 لـ catch)
    try {
      return await doUpdate(documentId, suppressErrorLog: true);
    } on AppwriteException catch (updateError) {
      if (isRateLimit(updateError)) {
        _logger.warning('secondary_upsert: 429 on update $documentId — waiting 65s then create', tag: 'RATE_LIMIT');
        await Future<void>.delayed(const Duration(seconds: 65));
        // انتقل مباشرة للخطوة 2 (create) — لا إعادة try update
      } else if (!isNotFound(updateError)) {
        if (isAlreadyExists(updateError)) {
          try {
            return await doCreate();
          } on AppwriteException catch (e2) {
            if (isAlreadyExists(e2)) {
              try {
                return await doUpdate(documentId);
              } catch (e3) {
                rethrow;
              }
            }
            rethrow;
          }
        }
        rethrow;
      }
    }

    // ✅ الخطوة 1.5: قبل الإنشاء، جرّب تحديث الـ ID البديل (بدون شرطات)
    // لسدّ مسار التكرار: update(بشرطات)=404 ثم create(بشرطات) ينجح رغم وجود
    // نسخة بدون شرطات. نحدّث في مكانه بدل إنشاء نسخة مكررة.
    if (altDocumentId.isNotEmpty) {
      try {
        return await doUpdate(altDocumentId, suppressErrorLog: true);
      } on AppwriteException catch (altError) {
        if (!isNotFound(altError)) {
          rethrow;
        }
      }
    }

    // الخطوة 2: createDocument
    try {
      return await doCreate();
    } on AppwriteException catch (createError) {
      if (isAlreadyExists(createError)) {
        // ✅ تجربة ID البديل فقط — بلا حذف/ترحيل (نفس Primary)
        if (altDocumentId.isNotEmpty) {
          try {
            return await doUpdate(altDocumentId, suppressErrorLog: true);
          } on AppwriteException catch (altError) {
            if (!isNotFound(altError)) {
              rethrow;
            }
          }
        }
        // ✅ P1-4 fix: إضافة await هنا — بدونه يُعاد الـ Future فوراً ولا
        // يلتقط catch أي فشل async (النظام الأساسي يستخدم return await).
        try {
          return await doUpdate(documentId, suppressErrorLog: true);
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// حذف مستند من Secondary
  ///
  /// ✅ P1-2 fix: الحذف idempotent — استخدام نفس `isNotFound()` المستخدم
  /// في upsertDocument بدل فحص `code == 404` فقط. الثانوي يُملأ كسولاً
  /// (سجلات كثيرة لم تُدفَع إليه بعد)، فحذف سجل غير موجود شائع جداً
  /// ولا يجب أن يُعامل كخطأ.
  Future<void> deleteDocument({required String collectionId, required String documentId}) async {
    await ensureInitialized();
    try {
      await _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.deleteDocument(
          databaseId: SecondaryAppwriteConfig.databaseId,
          collectionId: collectionId,
          documentId: documentId,
        ),
        operationName: 'secondary_deleteDocument',
      );
    } on AppwriteException catch (e) {
      // ✅ P1-2: نفس منطق isNotFound في upsert — 404 أو document_not_found
      // بأي صيغة (code أو type أو toString).
      if (e.code == 404 ||
          (e.type ?? '').contains('document_not_found') ||
          e.toString().contains('document_not_found')) {
        return; // المستند غير موجود أصلاً — الحذف idempotent ✓
      }
      rethrow;
    }
  }

  /// الحصول على collection ID لكل كيان
  /// نعيد نفس أسماء collections المستخدمة في Primary لضمان التوافق
  String? getCollectionId(String entity) {
    return AppwriteConfig.collectionIdFor(entity);
  }

  /// مصدر الحقيقة الوحيد لجداول الرفع الشامل.
  ///
  /// كل مدخلة تربط اسم الكيان بدالة تجلب صفوفه من Drift وتحوّلها إلى خرائط.
  /// إضافة/إزالة جدول من النسخة الشاملة = تعديل سطر واحد هنا فقط.
  /// (سابقاً كانت قائمة `entities` و`switch` منفصلين يتباعدان مع الوقت،
  /// مما أدى لإسقاط `salary_carry_over_logs` صامتاً من النسخة "الشاملة".)
  Map<String, Future<List<Map<String, dynamic>>> Function()> _backupFetchers(AppDatabase db) {
    // ✅ إصلاح تطابق الحقول مع Primary:
    // نستخدم `row.toJson()` لكل كيان — تماماً مثل DeltaSyncService في Primary
    // (`_entityConfigs()` → `toJson: (row) => row.toJson()`).
    // سابقاً كانت هذه الدالة تعتمد على مُحوّلات يدوية (_roomToMap, _bookingToMap…)
    // تختار مجموعة فرعية من الأعمدة، فكانت تتباعد عن مخطط Primary وتُسقط حقولاً
    // صامتاً (لأن فلتر المخطط في sanitizePayload يُبقي فقط الحقول الموجودة أصلاً
    // في المدخلات). باستخدام toJson تُرسَل نفس أعمدة Primary بالضبط، ثم تمرّ عبر
    // نفس sanitizePayload/collectionSchema — فيتطابق ناتج الحقول حرفياً مع Primary.
    return {
      'rooms': () async => (await db.select(db.rooms).get()).map((e) => e.toJson()).toList(),
      'bookings': () async => (await db.select(db.bookings).get()).map((e) {
        final j = e.toJson();
        // ✅ حقل amount الموحّد لجدول bookings (مشتق من المبلغ المستحق)
        // حتى يطابق Primary تماماً في الحقول المُرسَلة.
        j['amount'] = e.totalDueCached;
        return j;
      }).toList(),
      'payments': () async => (await db.select(db.payments).get()).map((e) => e.toJson()).toList(),
      'expenses': () async => (await db.select(db.expenses).get()).map((e) => e.toJson()).toList(),
      'debts': () async => (await db.select(db.debts).get()).map((e) => e.toJson()).toList(),
      'employees': () async => (await db.select(db.employees).get()).map((e) => e.toJson()).toList(),
      'booking_notes': () async => (await db.select(db.bookingNotes).get()).map((e) => e.toJson()).toList(),
      'booking_nights': () async => (await db.select(db.bookingNights).get()).map((e) => e.toJson()).toList(),
      'cash_transactions': () async => (await db.select(db.cashTransactions).get()).map((e) => e.toJson()).toList(),
      'salary_cycles': () async => (await db.select(db.salaryCycles).get()).map((e) => e.toJson()).toList(),
      'salary_payments': () async => (await db.select(db.salaryPayments).get()).map((e) => e.toJson()).toList(),
      'salary_withdrawals': () async => (await db.select(db.salaryWithdrawals).get()).map((e) => e.toJson()).toList(),
      'salary_carry_over_logs': () async =>
          (await db.select(db.salaryCarryOverLogs).get()).map((e) => e.toJson()).toList(),
      'shift_notes': () async => (await db.select(db.shiftNotes).get()).map((e) => e.toJson()).toList(),
      'price_adjustments': () async => (await db.select(db.priceAdjustments).get()).map((e) => e.toJson()).toList(),
      'booking_price_adjustments': () async =>
          (await db.select(db.bookingPriceAdjustments).get()).map((e) => e.toJson()).toList(),
      'audit_logs': () async => (await db.select(db.auditLogs).get()).map((e) => e.toJson()).toList(),
      'payment_voids': () async => (await db.select(db.paymentVoids).get()).map((e) => e.toJson()).toList(),
      // app_settings ليس جدول Drift — يُبنى من SharedPreferences كما في السابق.
      'app_settings': () async => [await _appSettingsToMap()],
      'guest_infos': () async => (await db.select(db.guestInfos).get()).map((e) => e.toJson()).toList(),
    };
  }

  /// تجميع كل بيانات الجداول المحلية للرفع الشامل
  /// ✅ P0-3 إصلاح: استخدام اجراءات Drift الفعلية بدلاً من قائمة ثابتة فارغة
  /// ✅ يُبنى من `_backupFetchers` (مصدر حقيقة واحد) بدل قائمة + switch منفصلين.
  Future<List<CollectionData>> getAllCollections(AppDatabase db) async {
    final fetchers = _backupFetchers(db);
    final result = <CollectionData>[];

    for (final entry in fetchers.entries) {
      final entity = entry.key;
      final collectionId = AppwriteConfig.collectionIdFor(entity);
      if (collectionId == null) {
        // كيان بلا collectionId مُعرّف — لا يمكن رفعه؛ نتخطّاه صراحةً مع تنبيه.
        debugPrint('⚠️ [Secondary] تخطّي "$entity": لا يوجد collectionId مطابق');
        continue;
      }

      final records = await entry.value();
      result.add(CollectionData(name: entity, collectionId: collectionId, records: records));
    }

    return result;
  }

  // ── Entity to Map converters ──
  // ✅ لم تعد هناك مُحوّلات يدوية لكل كيان — نستخدم row.toJson() في
  //    _backupFetchers تماماً مثل Primary. يبقى فقط app_settings لأنه
  //    ليس جدول Drift.

  /// تحويل إعدادات التطبيق من SharedPreferences إلى خريطة للرفع
  /// app_settings مخزّن في SharedPreferences (ليس Drift) كمستند واحد
  /// بمعرّف ثابت 'whatsapp_settings' — نفس النمط المستخدم في Primary sync.
  Future<Map<String, dynamic>> _appSettingsToMap() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final deviceId = prefs.getString('appwrite_delta_device_id') ?? 'default';

    final map = <String, dynamic>{
      'localUuid': 'whatsapp_settings',
      'value': '',
      'hotel_name': prefs.getString('hotel_name') ?? 'فندق مارينا بلازا',
      'hotel_cutoff_hour': prefs.getInt('hotel_cutoff_hour') ?? 14,
      'dark_mode': prefs.getBool('dark_mode') ?? false,
      'wa_api_type': prefs.getString('wa_api_type') ?? 'greenapi',
      'wa_api_base_url': prefs.getString('wa_api_base_url') ?? '',
      'wa_api_instance_id': prefs.getString('wa_api_instance_id') ?? '',
      'wa_custom_url_template': prefs.getString('wa_custom_url_template') ?? '',
      'wa_sendzen_api_key': prefs.getString('wa_sendzen_api_key') ?? '',
      'wa_sendzen_from_number': prefs.getString('wa_sendzen_from_number') ?? '',
      'telegram_enabled': prefs.getBool('telegram_enabled') ?? false,
      'telegram_chat_id': prefs.getString('telegram_chat_id') ?? '',
      'telegram_notifications_enabled': prefs.getBool('telegram_notifications_enabled') ?? false,
      'telegram_daily_report_enabled': prefs.getBool('telegram_daily_report_enabled') ?? false,
      'telegram_daily_report_time': prefs.getString('telegram_daily_report_time') ?? '',
      'appwrite_sync_interval': prefs.getInt('appwrite_sync_interval') ?? 15,
      // حقول المزامنة الأساسية (SyncFields)
      'deviceId': deviceId,
      'serverId': null,
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
      'lastModified': now,
      'lastModifiedEpoch': now,
      'createdAtEpoch': now,
      'createdAtIso': DateTime.now().toIso8601String(),
      'updatedAtIso': DateTime.now().toIso8601String(),
      'deletedAtIso': null,
      'version': 1,
      'origin': 'local',
      'vectorClock': '{}',
      'idempotencyKey': null,
      'syncTimestamp': now,
      'sync_origin': 'secondary_backup',
    };

    // ✅ الخيار 2: تجميع مفاتيح WhatsApp/Telegram النصّية في config_json واحد
    // (مطابق لـ Primary) لتفادي تجاوز حدّ حجم الصف في Appwrite.
    // ⚠️ نُعيد استخدام `AppwriteSyncUtils.appSettingsConfigKeys` (DRY) — مصدر
    //    وحيد للقائمة بين Primary و Secondary لتفادي الانحراف مستقبلاً.
    final configMap = <String, dynamic>{};
    for (final k in AppwriteSyncUtils.appSettingsConfigKeys) {
      if (map.containsKey(k)) {
        configMap[k] = map.remove(k);
      }
    }
    map['config_json'] = jsonEncode(configMap);

    return map;
  }
}

/// نتيجة اختبار الاتصال
class ConnectionTestResult {
  ConnectionTestResult({required this.success, required this.message, this.latencyMs});
  final bool success;
  final String message;
  final int? latencyMs;
}

/// إحصائيات رفع نسخة شاملة
class FullBackupStats {
  int totalCollections = 0;
  int fullySuccessfulCollections = 0;
  int failedCollections = 0;
  int successCount = 0;
  int failureCount = 0;
  String? error;
  final List<String> collectionNames = [];
  final List<Map<String, dynamic>> collectionDetails = [];
  final Map<String, List<FullBackupFailure>> failuresByCollection = {};
  final List<FullBackupFailure> failedRecords = [];
  final Map<String, int> errorsByReason = {};

  /// ملخص نصي جاهز للنسخ إلى الحافظة
  String get textSummary {
    final buf = StringBuffer();
    buf.writeln('📊 تقرير النسخة الشاملة — Secondary Appwrite');
    buf.writeln('═══════════════════════════════════════');
    buf.writeln();
    buf.writeln('✅ نجح: $successCount');
    buf.writeln('❌ فشل: $failureCount');
    buf.writeln('📁 الجداول: $fullySuccessfulCollections مكتمل / $failedCollections فاشل');
    if (error != null) {
      buf.writeln('⚠️ خطأ عام: $error');
    }
    buf.writeln();

    if (collectionDetails.isNotEmpty) {
      buf.writeln('── تفاصيل الجداول ──');
      for (final detail in collectionDetails) {
        final name = detail['name'] ?? '?';
        final total = detail['total'] ?? 0;
        final success = detail['success'] ?? 0;
        final failure = detail['failure'] ?? 0;
        final icon = (failure as int) == 0 ? '✅' : '⚠️';
        buf.writeln('  $icon $name: $success/$total (فشل: $failure)');
      }
      buf.writeln();
    }

    if (errorsByReason.isNotEmpty) {
      buf.writeln('── الأخطاء حسب السبب ──');
      for (final entry in errorsByReason.entries) {
        buf.writeln('  [${entry.value}] ${entry.key}');
      }
      buf.writeln();
    }

    if (failuresByCollection.isNotEmpty) {
      buf.writeln('── الأخطاء حسب الجدول ──');
      for (final entry in failuresByCollection.entries) {
        buf.writeln('  📁 ${entry.key} (${entry.value.length} خطأ):');
        for (final failure in entry.value) {
          final id = failure.documentId ?? 'بدون معرّف';
          final reason = failure.reason.length > 200 ? '${failure.reason.substring(0, 200)}...' : failure.reason;
          buf.writeln('    · [$id] $reason');
        }
      }
    }

    buf.writeln();
    buf.writeln('🕐 ${DateTime.now().toLocal().toIso8601String()}');
    buf.writeln('Marina Hotel — Backup Report');
    return buf.toString();
  }

  /// تحويل إلى Map للتصدير
  Map<String, dynamic> toJson() {
    return {
      'totalCollections': totalCollections,
      'fullySuccessfulCollections': fullySuccessfulCollections,
      'failedCollections': failedCollections,
      'successCount': successCount,
      'failureCount': failureCount,
      'error': error,
      'collectionNames': collectionNames,
      'collectionDetails': collectionDetails,
      'failuresByCollection': failuresByCollection.map((k, v) => MapEntry(k, v.map((f) => f.toJson()).toList())),
      'failedRecords': failedRecords.map((f) => f.toJson()).toList(),
      'errorsByReason': errorsByReason,
      'timestamp': DateTime.now().toLocal().toIso8601String(),
    };
  }
}

/// خطأ في رفع سجل واحد
class FullBackupFailure {
  FullBackupFailure({      required this.reason,
      this.documentId,
      this.collectionName,
      this.timestamp,
  });
  final String? documentId;
  final String reason;
  final String? collectionName;
  final DateTime? timestamp;

  @override
  String toString() {
    final coll = collectionName ?? '?';
    final id = documentId ?? 'بدون معرّف';
    return '❌ [$coll] $id: $reason';
  }

  /// تحويل إلى Map للتصدير والنسخ
  Map<String, dynamic> toJson() {
    return {
      'documentId': documentId,
      'reason': reason,
      'collectionName': collectionName,
      'timestamp': timestamp?.toLocal().toIso8601String(),
    };
  }
}

/// بيانات جدول للرفع الشامل
class CollectionData {
  CollectionData({required this.name, required this.collectionId, required this.records});
  final String name;
  final String collectionId;
  final List<Map<String, dynamic>> records;
}
