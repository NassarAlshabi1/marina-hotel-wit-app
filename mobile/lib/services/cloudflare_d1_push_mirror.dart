// ══════════════════════════════════════════════════════════════════
//  cloudflare_d1_push_mirror.dart — رفع آمن لشاشة النسخ الاحتياطي
//  Cloudflare D1 عبر بروتوكول المزامنة الحقيقي (/api/sync/push)
//  بدل REST API الإداري (INSERT OR REPLACE الخام).
//
//  لماذا هذا الملف موجود (RU3 — القرار 2026-09-28):
//  CloudflareD1Service.uploadData ينفّذ `INSERT OR REPLACE` مباشرة عبر
//  api.cloudflare.com/client/v4 بلا أي فحص version أو ساعة متجهة — أُثبت
//  تجريبياً (mobile/test/raw_d1_backup_upload_outbox_test.dart، RU3) أن
//  هذا يمحو صمتاً تعديلات خادمية أحدث حقيقية بمجرد أن يرفع جهاز يحمل
//  نسخة محلية أقدم (لم يُزامن منذ فترة).
//
//  المسار الحقيقي /api/sync/push محمي فعلاً بهذا الفحص — resolveLwwDecision
//  (worker/src/database.ts:976) يرفض («timestampLoss» → إبقاء existing كما
//  هو دون تطبيق) أي دفعة وارِدة أقدم زمنياً/إصدارياً من الصف المخزَّن على
//  D1 حالياً. توجيه الرفع عبر outbox + CloudflareSyncManager.sync() بدل
//  الكتابة الخام يمنح كل صف نفس هذا الفحص تلقائياً — بلا حاجة لإعادة تنفيذه
//  على العميل.
//
//  الفرق الجوهري عن outbox العادي: هذه ليست تعديلات مستخدم جديدة، بل
//  إعادة إرسال حالة قائمة أصلاً — source:'restore' في OutboxDao.merge
//  يمنع _bumpVectorClockForLocalWrite من تضخيم الساعة المتجهة لكل صف
//  بلا تعديل حقيقي وراءه.
// ══════════════════════════════════════════════════════════════════

import 'cloudflare_d1_service.dart'
    show CloudflareD1SourceTable, CloudflareD1Progress, CloudflareD1UploadResult;
import 'cloudflare_sync_manager.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

class CloudflareD1PushMirror {
  CloudflareD1PushMirror(this.db, {CloudflareSyncManager? syncManager})
    : _syncManager = syncManager ?? CloudflareSyncManager();

  final AppDatabase db;
  final CloudflareSyncManager _syncManager;

  bool _cancelled = false;

  /// نفس حجم الدفعة المستخدم سابقاً في uploadData — قرار غير مرتبط
  /// بالبروتوكول الجديد، فقط للحفاظ على تجزئة قراءة/تقدّم مألوفة.
  static const int _readChunkSize = 400;

  void cancel() => _cancelled = true;

  /// يرفع [tables] عبر outbox الحقيقي + دورات دفع (`/api/sync/push`)
  /// بدل الكتابة الخام. يُعيد نفس [CloudflareD1UploadResult] المستخدم في
  /// شاشة الإعدادات حتى تبقى واجهة عرض النتيجة كما هي بلا تعديل.
  Future<CloudflareD1UploadResult> upload({
    required List<CloudflareD1SourceTable> tables,
    void Function(CloudflareD1Progress progress)? onProgress,
  }) async {
    _cancelled = false;
    final sw = Stopwatch()..start();
    final outboxDao = OutboxDao(db);

    var rowsUploaded = 0;
    var flushCalls = 0;
    final errors = <String>[];
    final warnings = <String>[];
    final doneTables = <String>[];
    final totalTables = tables.length;

    for (var ti = 0; ti < totalTables; ti++) {
      if (_cancelled) break;
      final t = tables[ti];
      onProgress?.call(
        CloudflareD1Progress(
          stage: 'رفع آمن عبر /push',
          currentTable: t.name,
          tableIndex: ti,
          tableCount: totalTables,
          rowsDone: 0,
          rowsTotal: t.rowCount,
        ),
      );

      if (t.rowCount == 0) {
        doneTables.add(t.name);
        continue;
      }

      try {
        var offset = 0;
        var rowsForTable = 0;
        var skippedNoUuid = 0;
        while (offset < t.rowCount) {
          if (_cancelled) break;
          final chunk = await t.readChunk(_readChunkSize, offset);
          if (chunk.isEmpty) break;

          for (final row in chunk) {
            final localUuid = row['local_uuid'] as String?;
            if (localUuid == null || localUuid.isEmpty) {
              // ✅ صف بلا هوية مزامنة (نادر: SyncFields مفقودة استثنائياً)
              // — لا يمكن دفعه عبر /push (يتطلب local_uuid). يُتخطى بدل
              // إسقاط الجدول كله.
              skippedNoUuid++;
              continue;
            }
            // ✅ id المحلي عمود Drift autoincrement بلا معنى على D1 (لها
            // عمود id مستقل بترقيمها الخاص) — نفس التصرف المتبع في
            // CloudflareD1Service.uploadData (copy.remove('id')) وفي
            // عقد الدفع العادي (buildPushOperation / _handlePush كلاهما
            // يُسقطان id الوارد). عقد الهوية هنا هو local_uuid حصراً.
            final payload = Map<String, dynamic>.from(row)..remove('id');

            // ✅ حرج لسلامة RU3: الطابع الزمني المُرسل يجب أن يعكس آخر
            // تعديل حقيقي مخزَّن في الصف (updated_at)، لا لحظة الضغط على
            // زر الرفع. resolveLwwDecision على الخادم (database.ts:993-
            // 1023) تقارن هذا الطابع بما هو مخزَّن فعلاً؛ إرسال «الآن»
            // بدل الطابع الحقيقي يُقنع الخادم زوراً أن كل صف — مهما قدُم
            // محلياً — عُدِّل للتو، فيُبطل الحارس تماماً ويعيد فتح ثغرة
            // RU3 من الباب الخلفي.
            final rowUpdatedAt =
                (row['updated_at'] as int?) ??
                (row['last_modified'] as int?) ??
                (DateTime.now().millisecondsSinceEpoch ~/ 1000);

            await outboxDao.merge(
              entity: t.name,
              op: 'update',
              localUuid: localUuid,
              payload: payload,
              clientTs: rowUpdatedAt,
              // ✅ source:'restore' — هذه إعادة إرسال حالة قائمة، وليست
              // تعديلاً محلياً جديداً. 'local' كان سيُضخّم الساعة المتجهة
              // للصف (OutboxDao._bumpVectorClockForLocalWrite) لكل صف
              // غير معدَّل فعلياً، فيصطنع سجل «تعديل» لم يحدث.
              source: 'restore',
            );
            rowsForTable++;
          }

          offset += chunk.length;
          rowsUploaded += chunk.length;
          onProgress?.call(
            CloudflareD1Progress(
              stage: 'رفع آمن عبر /push',
              currentTable: t.name,
              tableIndex: ti,
              tableCount: totalTables,
              rowsDone: rowsForTable,
              rowsTotal: t.rowCount,
            ),
          );

          // ✅ تفريغ outbox كل دفعة قراءة بدل تجميع كل الجداول في الذاكرة
          // أولاً — يمنح تقدماً حقيقياً ويحترم rate-limit الخادم
          // (CloudflareSyncManager._pushCooldownUntil) تدريجياً بدل صدمة
          // واحدة ضخمة.
          if (!_cancelled) {
            await _flush();
            flushCalls++;
          }
        }
        if (skippedNoUuid > 0) {
          warnings.add('${t.name}: تخطي $skippedNoUuid صف بلا local_uuid');
        }
        doneTables.add(t.name);
      } catch (e) {
        errors.add('${t.name}: $e');
      }
    }

    sw.stop();
    return CloudflareD1UploadResult(
      ok: errors.isEmpty && !_cancelled,
      cancelled: _cancelled,
      tablesDone: doneTables.length,
      rowsUploaded: rowsUploaded,
      apiCalls: flushCalls,
      errors: errors,
      warnings: warnings,
      elapsed: sw.elapsed,
    );
  }

  /// دفع outbox عبر البروتوكول الحقيقي (سحب مُعطَّل — نريد الدفع فقط هنا،
  /// السحب الدوري العادي مستقل تماماً عن هذه الشاشة).
  Future<void> _flush() async {
    try {
      await _syncManager.sync(pull: false, forcePull: true);
    } catch (_) {
      // ✅ فشل دورة دفع واحدة (شبكة/تهدئة 429) لا يوقف بقية الجداول —
      // السجلات تبقى في outbox وتُعاد محاولتها في دورة الدفع التلقائية
      // القادمة (نفس ضمان أي تعديل محلي عادي فشل رفعه أول مرة).
    }
  }
}
