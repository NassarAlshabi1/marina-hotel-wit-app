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

import 'cloudflare_d1_identity_validator.dart';
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

    // Validate the complete selected dataset before creating restore outbox
    // entries or sending the first push request. A partial first upload could
    // otherwise strand financial rows with broken portable UUID references.
    final preflightIssues = await CloudflareD1IdentityValidator.inspect(
      db: db,
      selectedTables: tables.map((table) => table.name).toSet(),
    );
    if (preflightIssues.isNotEmpty) {
      sw.stop();
      return CloudflareD1UploadResult(
        ok: false,
        cancelled: false,
        tablesDone: 0,
        rowsUploaded: 0,
        apiCalls: 0,
        errors: preflightIssues,
        warnings: const [],
        elapsed: sw.elapsed,
      );
    }

    var rowsUploaded = 0;
    var flushCalls = 0;
    final errors = <String>[];
    final warnings = <String>[];
    final doneTables = <String>[];
    final totalTables = tables.length;
    // ✅ (2026-09-28 — عطل مُلاحَظ) دائرة توقف مبكر: أول فشل دفع شبكي
    // (timeout/DNS/إلخ) يوقف الرفع بالكامل بدل الاستمرار عبر كل صف/جدول
    // متبقٍّ وكل واحد منها يهدر مهلة شبكة أخرى (30 ثانية) بلا فائدة —
    // لوحظ ذلك فعلياً: 4 محاولات منفصلة فشلت جميعها بعد 30ث كل واحدة
    // بدل التوقف عند أول فشل. لا فقدان بيانات هنا: الصفوف المُرسَلة
    // بالفعل تبقى آمنة في outbox وتُعاد محاولتها في دورة المزامنة
    // التلقائية القادمة تماماً كأي تعديل محلي عادي فشل رفعه أول مرة.
    var networkFailed = false;

    for (var ti = 0; ti < totalTables; ti++) {
      if (_cancelled || networkFailed) break;
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
        while (offset < t.rowCount) {
          if (_cancelled || networkFailed) break;
          final chunk = await t.readChunk(_readChunkSize, offset);
          if (chunk.isEmpty) break;

          for (final row in chunk) {
            final localUuid = row['local_uuid'];
            if (localUuid is! String ||
                localUuid.isEmpty ||
                localUuid.trim() != localUuid) {
              errors.add(
                '${t.name}: ظهر صف بلا local_uuid صالح بعد الفحص المسبق؛ '
                'أُوقف الرفع لمنع إسقاطه أو إرساله بهوية بديلة.',
              );
              networkFailed = true;
              break;
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

          if (networkFailed) break;

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
            final flushError = await _flush();
            flushCalls++;
            if (flushError != null) {
              networkFailed = true;
              errors.add(
                'توقف الرفع عند ${t.name} (صف $offset تقريباً): $flushError '
                '— الصفوف المُرسَلة فعلاً آمنة في outbox وستُعاد محاولتها '
                'تلقائياً، لا حاجة لإعادة الرفع من الصفر.',
              );
              break;
            }
          }
        }
        if (!networkFailed) doneTables.add(t.name);
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

  /// ✅ (2026-09-28) عدد محاولات إعادة الدفع عند تصادم عابر مع مزامنة
  /// أخرى شغّالة بالتوازي (زر مزامنة يدوي آخر، أو مؤقّت الخلفية) — هذا
  /// ليس عطلاً شبكياً ولا يستحق إيقاف الرفع بالكامل، فقط انتظاراً قصيراً
  /// حتى تُحرَّر القفلة (P0-I re-entrancy) في cloudflare_sync_manager.dart.
  static const int _reentrancyRetries = 3;
  static const String _reentrancyMessage = 'Sync already in progress';

  /// دفع outbox عبر البروتوكول الحقيقي (سحب مُعطَّل — نريد الدفع فقط هنا،
  /// السحب الدوري العادي مستقل تماماً عن هذه الشاشة).
  ///
  /// ✅ (2026-09-28) يُعيد رسالة الخطأ (لا يكتفي بابتلاعها) — sync() لا
  /// يرمي استثناءً عند فشل الدفع (يلتقطه داخلياً ويُرجعه عبر
  /// SyncResult.errorMessage)، فالاعتماد على try/catch وحده هنا كان
  /// يُخفي كل فشل شبكي عن upload() ويترك حلقة القراءة تُكرر نفس الخطأ
  /// (30 ثانية timeout) على كل دفعة/جدول متبقٍّ دون توقف.
  ///
  /// ✅ يُميّز بين فشلين مختلفين تماماً بنفس isSuccess=false:
  ///   - «Sync already in progress» (قفل re-entrancy، cloudflare_sync_
  ///     manager.dart:1299-1308): تصادم عابر لا علاقة له بالشبكة أو
  ///     صحة البيانات — إيقاف الرفع كله بسببه كان سيُجهض عملية سليمة
  ///     تماماً لمجرد أن المستخدم ضغط زر مزامنة يدوي في نفس اللحظة.
  ///     يُعاد المحاولة بعد انتظار قصير بدل اعتباره فشلاً.
  ///   - أي فشل آخر (شبكة/تعطيل عن بعد/تعطيل محلي): توقف فوري كما هو،
  ///     لأن إعادة المحاولة لن تُغيّر شيئاً.
  Future<String?> _flush() async {
    for (var attempt = 0; attempt <= _reentrancyRetries; attempt++) {
      String? errorMessage;
      try {
        final result = await _syncManager.sync(pull: false, forcePull: true);
        if (result.isSuccess) return null;
        errorMessage = result.errorMessage ?? 'فشل غير معروف';
      } catch (e) {
        errorMessage = e.toString();
      }

      if (errorMessage != _reentrancyMessage || attempt == _reentrancyRetries) {
        return errorMessage;
      }
      // ✅ تصادم عابر — انتظار قصير متصاعد ثم إعادة محاولة فورية (ليست
      // فشلاً يُسجَّل ولا يُوقف الرفع).
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    return null; // لا يُصل إليه فعلياً — للاكتمال النوعي فقط
  }
}
