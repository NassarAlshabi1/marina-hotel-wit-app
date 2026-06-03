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
      final localUuid = json['localUuid'] as String? ??
          json['local_uuid'] as String?;
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
    // لكن كحماية إضافية، نستخدم insertOnConflictUpdate
    // مع تحذير واضح عن المخاطر
    developer.log(
      'WARNING: Falling back to insertOnConflictUpdate for ${table.actualTableName} — '
      'this may overwrite an unrelated local record with the same primary key!',
      name: 'BaseRepository',
    );
    return db.into(table).insertOnConflictUpdate(comp);
  }

  Map<String, dynamic> toJsonForSource(D row, {required Source src}) {
    return adapter.toJson(row, src: src);
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

  String _targetLabel(List<Column> target) {
    return target.map((column) => column.name).join(',');
  }

  bool _isUniqueConstraintError(Object error) {
    return error.toString().contains('UNIQUE constraint failed');
  }

  /// البحث عن id المحلي بواسطة localUuid
  /// يُستخدم لحل تصادمات id عند المزامنة من السيرفر
  Future<int?> _findByLocalUuid(String localUuid) async {
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
}
