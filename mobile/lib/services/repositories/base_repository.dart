import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../adapters/entity_adapter.dart';
import '../adapters/source.dart';
import '../local_db.dart';

class BaseRepository<D extends DataClass, C extends UpdateCompanion<D>> {
  BaseRepository({
    required this.db,
    required this.table,
    required this.adapter,
  });

  static final Map<String, List<List<Column>>> _conflictTargetCache = {};

  final AppDatabase db;
  final TableInfo<Table, D> table;
  final EntityAdapter<D, C> adapter;

  // ✅ N+1 FIX: Optional batch UUID cache for single upserts
  // When called from batchUpsertFromJson, pass the pre-computed map to avoid N round-trips
  Map<String, int>? _batchUuidCache;

  void setBatchUuidCache(Map<String, int> cache) {
    _batchUuidCache = cache;
  }

  void clearBatchUuidCache() {
    _batchUuidCache = null;
  }

  Future<int> upsertFromJson(
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    // ✅ إصلاح حرج: إزالة id البعيد عند المزامنة من السيرفر
    // id هو auto-increment محلي — تمرير id البعيد يسبب تصادم:
    // UNIQUE constraint failed: table.id
    // مثال: جهاز A أنشأ سجل id=505 وجهاز B أنشأ سجل آخر id=505
    // عند السحب، INSERT بـ id=505 يصطدم بالسجل المحلي المختلف
    // الحل: إزالة id من البيانات ليقوم SQLite بتعيين id تلقائي
    // للسجلات الجديدة، أو استخدام id المحلي الموجود للتحديث.
    if (src == Source.appwrite || src == Source.drive) {
      final localUuid =
          json['localUuid'] as String? ?? json['local_uuid'] as String?;
      if (localUuid != null) {
        // تحقق هل يوجد سجل محلي بنفس local_uuid
        final existing = await _findByLocalUuid(localUuid);
        if (existing == null) {
          // سجل جديد من السيرفر — إزالة id ليُعيّنه SQLite تلقائياً
          json.remove('id');
        } else {
          // سجل موجود محلياً — استخدم id المحلي لضمان التحديث الصحيح
          json['id'] = existing;
        }
      } else {
        // ✅ إصلاح حرج: إذا لم يكن localUuid موجوداً في بيانات السيرفر،
        // يجب إزالة id البعيد لمنع تصادم UNIQUE constraint مع سجل محلي مختلف
        // له نفس id — بدون هذه الإزالة سيحاول INSERT بـ id البعيد
        // ويفشل لأن id المحلي التلقائي قد يكون مأخوذاً بالفعل
        json.remove('id');
      }
    }

    final refs = await adapter.resolveRefs(db, json, src: src);

    // ✅ إصلاح حرج: تخطي السجل إذا تعذر حل مرجع خارجي مطلوب (FK)
    // يحدث عند استعادة نسخة احتياطية من Google Drive حيث لا يوجد الحجز المرتبط
    // بدلاً من إدراج سجل بقيمة Value.absent() في حقل NOT NULL مما يسبب InvalidDataException
    if (refs.shouldSkip) {
      developer.log(
        'Skipping upsert for ${table.actualTableName}: ${refs.skipReason ?? "unresolved FK reference"}',
        name: 'BaseRepository',
      );
      return -1; // إشارة إلى أن السجل تم تخطيه
    }

    final comp = adapter.fromJson(json, src: src, refs: refs);
    final targets = await _resolveConflictTargets();
    Object? lastError;
    StackTrace? lastStack;

    for (final target in targets) {
      try {
        return await db
            .into(table)
            .insert(comp, onConflict: DoUpdate((_) => comp, target: target));
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (_isUniqueConstraintError(e)) {
          developer.log(
            'Upsert conflict on ${table.actualTableName} with target ${_targetLabel(target)}',
            error: e,
            stackTrace: st,
            name: 'BaseRepository',
          );
          continue;
        }
        developer.log(
          'Upsert failed for ${table.actualTableName}',
          error: e,
          stackTrace: st,
          name: 'BaseRepository',
        );
        rethrow;
      }
    }

    // ✅ إصلاح حرج: إذا استنفدنا جميع أهداف conflict ولم ننجح،
    // لا نستخدم insertOnConflictUpdate لأنه سيكتب فوق سجل محلي مختلف
    // له نفس id (فقدان بيانات!). بدلاً من ذلك، نرمي الخطأ ليُعالج
    // بشكل صحيح في طبقة المزامنة (تأجيل أو تسجيل).
    if (lastError != null && lastStack != null) {
      developer.log(
        'Upsert exhausted conflict targets for ${table.actualTableName}',
        error: lastError,
        stackTrace: lastStack,
        name: 'BaseRepository',
      );
      Error.throwWithStackTrace(lastError, lastStack);
    }

    // هذه النقطة لا يمكن الوصول إليها نظرياً لأنه:
    // 1. إذا نجحت إحدى المحاولات → نعود مبكراً من الحلقة
    // 2. إذا فشلت جميع المحاولات → lastError != null ونرمي أعلاه
    // كحماية إضافية: نرمي خطأ بدلاً من_insertOnConflictUpdate_ الصامت
    // الذي قد يكتب فوق سجل محلي مختلف لنفس المفتاح الرئيسي.
    throw StateError(
      'upsertFromJson exhausted all conflict targets for ${table.actualTableName} — '
      'refusing silent overwrite via insertOnConflictUpdate',
    );
  }

  Map<String, dynamic> toJsonForSource(D row, {required Source src}) {
    return adapter.toJson(row, src: src);
  }

  /// ✅ N+1 FIX: Optimized _findByLocalUuid with optional cache
  /// Uses O(1) cache lookup when available (set by batchUpsertFromJson)
  Future<int?> _findByLocalUuid(String localUuid) async {
    // ✅ Use cached batch lookup if available (O(1) instead of SQL round-trip)
    if (_batchUuidCache != null) {
      return _batchUuidCache![localUuid];
    }

    // Fallback to individual query (for non-batch callers)
    final tableName = table.actualTableName;
    final sanitized = tableName.replaceAll("'", "''");
    final result = await db
        .customSelect(
          "SELECT id FROM '$sanitized' WHERE local_uuid = ? LIMIT 1",
          variables: [Variable.withString(localUuid)],
          readsFrom: {table},
        )
        .getSingleOrNull();
    if (result == null) return null;
    return result.data['id'] as int?;
  }

  Future<List<List<Column>>> _resolveConflictTargets() async {
    final tableName = table.actualTableName;
    final cached = _conflictTargetCache[tableName];
    if (cached != null) {
      return cached;
    }

    final columnsByName = <String, Column>{
      for (final column in table.$columns) column.$name: column,
    };
    final targets = <List<Column>>[];
    final sanitizedName = tableName.replaceAll("'", "''");

    final indexRows = await db
        .customSelect("PRAGMA index_list('$sanitizedName')")
        .get();
    for (final row in indexRows) {
      final isUnique = row.data['unique'] == 1 || row.data['unique'] == true;
      if (!isUnique) {
        continue;
      }
      final indexName = row.data['name']?.toString();
      if (indexName == null || indexName.isEmpty) {
        continue;
      }
      final sanitizedIndex = indexName.replaceAll("'", "''");
      final infoRows = await db
          .customSelect("PRAGMA index_info('$sanitizedIndex')")
          .get();
      final cols = <Column>[];
      for (final info in infoRows) {
        final name = info.data['name']?.toString();
        final column = name != null ? columnsByName[name] : null;
        if (column != null) {
          cols.add(column);
        }
      }
      if (cols.isNotEmpty) {
        targets.add(cols);
      }
    }

    final deduped = _dedupeTargets(targets);

    // ✅ إصلاح حرج: إضافة المفتاح الرئيسي (PRIMARY KEY) كـ fallback دائماً
    // وليس فقط عندما لا توجد أهداف أخرى.
    // السبب: عند السحب من Appwrite، قد يأتي سجل بـ id=505 و localUuid=xyz
    // بينما محلياً يوجد سجل مختلف بـ id=505 و localUuid=abc.
    // INSERT ON CONFLICT("local_uuid") يحاول إدراج صف جديد (لأن localUuid غير موجود)،
    // لكن يصطدم بـ id=505 الموجود مسبقاً → UNIQUE constraint failed!
    // بإضافة PRIMARY KEY كـ fallback، المحاولة الثانية بـ ON CONFLICT("id")
    // تُحدّث السجل المحلي الموجود.
    final pk = table.$primaryKey.toList();
    if (pk.isNotEmpty) {
      final pkLabel = _targetLabel(pk);
      if (!deduped.any((t) => _targetLabel(t) == pkLabel)) {
        deduped.add(pk);
      }
    }

    _conflictTargetCache[tableName] = deduped;
    return deduped;
  }

  List<List<Column>> _dedupeTargets(List<List<Column>> targets) {
    final seen = <String>{};
    final deduped = <List<Column>>[];
    for (final target in targets) {
      final label = _targetLabel(target);
      if (seen.add(label)) {
        deduped.add(target);
      }
    }
    return deduped;
  }

  bool _isUniqueConstraintError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('unique constraint failed') ||
        message.contains('constraint failed') ||
        message.contains('duplicate entry');
  }

  String _targetLabel(List<Column> target) {
    return target.map((c) => c.toString()).join(',');
  }

  /// ✅ N+1 FIX: Batch UUID lookup for external callers
  /// يقلل N استعلامات منفصلة إلى استعلام واحد بـ IN clause
  Future<Map<String, int>> batchFindByLocalUuids(List<String> uuids) async {
    if (uuids.isEmpty) return {};

    final tableName = table.actualTableName;
    final sanitized = tableName.replaceAll("'", "''");
    final result = <String, int>{};

    // chunking لتجنب SQLITE_MAX_VARIABLE_COUNT (999 افتراضياً)
    const chunkSize = 500;
    for (var i = 0; i < uuids.length; i += chunkSize) {
      final end = (i + chunkSize < uuids.length) ? i + chunkSize : uuids.length;
      final chunk = uuids.sublist(i, end);

      // بناء placeholders (?, ?, ?, ...)
      final placeholders = List.filled(chunk.length, '?').join(',');
      final variables = chunk.map(Variable.withString).toList();

      final rows = await db
          .customSelect(
            "SELECT local_uuid, id FROM '$sanitized' WHERE local_uuid IN ($placeholders)",
            variables: variables,
            readsFrom: {table},
          )
          .get();

      for (final row in rows) {
        final uuid = row.data['local_uuid'] as String?;
        final id = row.data['id'] as int?;
        if (uuid != null && id != null) {
          result[uuid] = id;
        }
      }
    }

    return result;
  }

  /// ✅ إصلاح P3-16: إدراج جماعي (batch upsert) لقائمة من سجلات JSON.
  ///
  /// هذا الأسلوب البديل لـ `upsertFromJson` (الذي يُعالج صف واحد في كل مرة)
  /// مُحسَّن لحالة الاستعادة من نسخة احتياطية حيث نريد إدراج آلاف الصفوف
  /// بكفاءة. بدلاً من تنفيذ INSERT منفصل لكل صف (مع round-trip كامل لـ SQLite)،
  /// نُجمّع جميع الـ INSERTs في `db.batch` واحد — مما يقلّل round-trips من N
  /// إلى 1 (لـ chunk واحد من 500 صف).
  ///
  /// **الفرق عن `upsertFromJson`:**
  /// - `upsertFromJson` يُستخدم في المزامنة (sync) حيث قد يكون السجل موجوداً
  ///   محلياً → يحتاج DoUpdate مع conflict targets متعددة
  /// - `batchUpsertFromJson` يُستخدم في الاستعادة (restore) بعد DELETE كامل
  ///   → الجدول فارغ → INSERT OR REPLACE كافٍ (لا توجد تعارضات محتملة)
  ///
  /// **الخطوات:**
  /// 1. لكل صف: حل localUuid + FK references (SELECTs منفصلة لكل صف)
  /// 2. تخطّي الصفوف ذات FK غير محلول (مع تسجيل السبب)
  /// 3. تجميع الـ companions الناجحة في chunks من 500 صف
  /// 4. تنفيذ `db.batch.insertAll` واحد لكل chunk (mode: insertOrReplace)
  Future<({int inserted, int skipped})> batchUpsertFromJson(
    List<Map<String, dynamic>> jsons, {
    required Source src,
  }) async {
    if (jsons.isEmpty) {
      return (inserted: 0, skipped: 0);
    }

    // ✅ إصلاح PR review (N+1 query): اقرأ جميع UUIDs دفعة واحدة بدلاً من
    // استدعاء _findByLocalUuid لكل صف. هذا يقلّل N round-trips إلى 1.
    // نُجمع كل localUuids من الـ jsons، نستعلم مرة واحدة بـ IN clause،
    // ثم نُخزّن النتائج في Map للوصول O(1) داخل الحلقة.
    Map<String, int> existingUuidToId = {};
    if (src == Source.appwrite || src == Source.drive) {
      try {
        final allUuids = jsons
            .map((j) => j['localUuid'] as String? ?? j['local_uuid'] as String?)
            .whereType<String>()
            .toSet()
            .toList();
        if (allUuids.isNotEmpty) {
          existingUuidToId = await _batchFindByLocalUuid(allUuids);
        }
      } catch (e) {
        developer.log(
          'Batch UUID lookup failed for ${table.actualTableName}, '
          'falling back to per-row lookup: $e',
          name: 'BaseRepository.batch',
        );
        // fallback: per-row lookup سيُستخدم (existingUuidToId فارغة)
      }
    }

    // ✅ N+1 FIX: Set cache for single upsert calls within this batch
    setBatchUuidCache(existingUuidToId);

    // المرحلة 1: pre-resolve لكل صف (UUID + FK) على حدة
    // هذا ضروري لأن كل صف له FK references مختلفة
    final companions = <C>[];
    var skipped = 0;

    for (final json in jsons) {
      try {
        // نسخة احتياطية لعدم تعديل الـ Map الأصلي
        final jsonCopy = Map<String, dynamic>.from(json);

        // حل localUuid + id باستخدام الـ batch lookup المُسبق
        if (src == Source.appwrite || src == Source.drive) {
          final localUuid =
              jsonCopy['localUuid'] as String? ??
              jsonCopy['local_uuid'] as String?;
          if (localUuid != null) {
            // ✅ استخدم الـ Map المُسبق التحضير (O(1)) بدلاً من استعلام SQL
            final existing =
                existingUuidToId[localUuid] ??
                (existingUuidToId.isEmpty
                    ? await _findByLocalUuid(localUuid)
                    : null);
            if (existing == null) {
              jsonCopy.remove('id');
            } else {
              jsonCopy['id'] = existing;
            }
          } else {
            jsonCopy.remove('id');
          }
        }

        final refs = await adapter.resolveRefs(db, jsonCopy, src: src);

        if (refs.shouldSkip) {
          developer.log(
            'Skipping row in batch upsert for ${table.actualTableName}: '
            '${refs.skipReason ?? "unresolved FK reference"}',
            name: 'BaseRepository.batch',
          );
          skipped++;
          continue;
        }

        final comp = adapter.fromJson(jsonCopy, src: src, refs: refs);
        companions.add(comp);
      } catch (e, st) {
        developer.log(
          'Pre-resolve failed for row in ${table.actualTableName}',
          error: e,
          stackTrace: st,
          name: 'BaseRepository.batch',
        );
        skipped++;
      }
    }

    // Clear cache after batch
    clearBatchUuidCache();

    if (companions.isEmpty) {
      return (inserted: 0, skipped: skipped);
    }

    // المرحلة 2: batch insert في chunks من 500
    // chunking ضروري لأن SQLite له حد لعدد المتغيرات في استعلام واحد
    // (SQLITE_MAX_VARIABLE_COUNT = 999 افتراضياً، وكل صف قد يستخدم 20-50 متغير)
    const chunkSize = 500;
    var inserted = 0;

    for (var i = 0; i < companions.length; i += chunkSize) {
      final end = (i + chunkSize < companions.length)
          ? i + chunkSize
          : companions.length;
      final chunk = companions.sublist(i, end);

      try {
        await db.batch(
          (b) => b.insertAll(table, chunk, mode: InsertMode.insertOrReplace),
        );
        inserted += chunk.length;
      } catch (e, st) {
        // ✅ fallback: عند فشل chunk كامل، نتراجع للإدراج صف-بصف
        // للحفاظ على عزل الأخطاء (skip bad row, continue)
        developer.log(
          'Batch insert failed for ${table.actualTableName} chunk $i-$end, '
          'falling back to per-row insert',
          error: e,
          stackTrace: st,
          name: 'BaseRepository.batch',
        );

        for (final comp in chunk) {
          try {
            await db.into(table).insert(comp, mode: InsertMode.insertOrReplace);
            inserted++;
          } catch (e2) {
            developer.log(
              'Per-row fallback failed for a row in ${table.actualTableName}',
              error: e2,
              name: 'BaseRepository.batch',
            );
            skipped++;
          }
        }
      }
    }

    return (inserted: inserted, skipped: skipped);
  }

  /// ✅ Helper: batch UUID lookup with chunking
  Future<Map<String, int>> _batchFindByLocalUuid(List<String> uuids) async {
    if (uuids.isEmpty) return {};

    final tableName = table.actualTableName;
    final sanitized = tableName.replaceAll("'", "''");
    final result = <String, int>{};

    // chunking لتجنب SQLITE_MAX_VARIABLE_COUNT
    const chunkSize = 500;
    for (var i = 0; i < uuids.length; i += chunkSize) {
      final end = (i + chunkSize < uuids.length) ? i + chunkSize : uuids.length;
      final chunk = uuids.sublist(i, end);

      // بناء placeholders (?, ?, ?, ...)
      final placeholders = List.filled(chunk.length, '?').join(',');
      final variables = chunk.map(Variable.withString).toList();

      final rows = await db
          .customSelect(
            "SELECT local_uuid, id FROM '$sanitized' WHERE local_uuid IN ($placeholders)",
            variables: variables,
            readsFrom: {table},
          )
          .get();

      for (final row in rows) {
        final uuid = row.data['local_uuid'] as String?;
        final id = row.data['id'] as int?;
        if (uuid != null && id != null) {
          result[uuid] = id;
        }
      }
    }

    return result;
  }
}
