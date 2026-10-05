// ignore_for_file: lines_longer_than_80_chars
//
// ✅ اختبارات انحدار لمسار الرفع (push path) — بنود تدقيق AUDIT المتبقيان:
//
//   P0.5 (R6) — سحبة راتب بموظف غائب محلياً:
//     المعالِج يُعيد false → العنصر يبقى في الطابور (processing) بلا علامة
//     تسليم، وصفر كتابات سحابية، وreclaimForPush يُعيده إلى pending فينجح
//     تلقائياً بعد وصول الموظف عبر المزامنة.
//     (السلوك القديم return true كان يُسقط العنصر من الطابور فيختفي من
//     السحابة إلى الأبد — البند الوحيد من الستة بلا تغطية حتى اليوم.)
//
//   blacklist — عطل _processBlacklistEntry المُصلَح (تدقيق D1-path 2026-10-04):
//     رفع إنشاء/تحديث لصف القائمة السوداء يجب أن يرفع (upsert) فقط ولا
//     يحذف المستند السحابي أبداً. العلة القديمة: الجلب عبر مُلقٍ بفلتر
//     createdBy='user' يعيد NULL لكل صفوف blacklist → سقوط الرفع في
//     _handleDeleteOp → تومستون/حذف السحابي عند كل رفع إنشاء/تحديث.
//
// المنهجية نفسها (المرحلة 0): الكود الإنتاجي نفسه بلا محاكاة منطقية —
// فقط AppwriteService مُسجِّل (recording fake) يجيب 404 على القراءة
// ويسجّل الكتابات، فلا شبكة إطلاقاً، وأي استدعاء غير متوقع يفجّر الاختبار.

import 'package:appwrite/appwrite.dart' show AppwriteException;
import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AppwriteService مُسجِّل بلا شبكة.
///
/// ⚠️ AppwriteService singleton بمُنشئ factory خاص (_internal) — لا يمكن
/// وراثته، لذا نستخدم implements + noSuchMethod: الأعضاء غير المكْسَوضون
/// هنا يرمون StateError صاخباً — أي لمسة شبكة غير متوقعة تُفشل الاختبار.
class _RecordingAppwriteService implements AppwriteService {
  final upsertedDocuments = <({String collectionId, String documentId})>[];
  final upsertedBlacklist = <String>[];
  final deletedBlacklist = <String>[];
  int getDocumentCalls = 0;

  @override
  Future<models.Document> getDocument({
    required String collectionId,
    required String documentId,
    bool suppressErrorLog = false,
  }) async {
    getDocumentCalls++;
    // المستند البعيد غير موجود → مسار create نظيف (نفس سلوك OCC مع 404).
    throw AppwriteException('document_not_found', 404, 'document_not_found');
  }

  @override
  Future<models.Document> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    upsertedDocuments.add((collectionId: collectionId, documentId: documentId));
    return _fakeDoc(documentId, collectionId, data);
  }

  @override
  Future<models.Document> upsertBlacklist(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    upsertedBlacklist.add(documentId);
    return _fakeDoc(documentId, 'blacklist', data);
  }

  @override
  Future<void> deleteBlacklist(String documentId) async {
    deletedBlacklist.add(documentId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
        'FakeAppwriteService: استدعاء غير متوقع '
        '${invocation.memberName} — راجع مسار الاختبار',
      );

  models.Document _fakeDoc(
    String id,
    String collectionId,
    Map<String, dynamic> data,
  ) =>
      models.Document(
        $id: id,
        $sequence: 1,
        $collectionId: collectionId,
        $databaseId: 'marina',
        $createdAt: '2026-10-05T00:00:00.000Z',
        $updatedAt: '2026-10-05T00:00:00.000Z',
        $permissions: const <String>[],
        data: data,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outboxDao;
  late _RecordingAppwriteService fakeService;
  late AppwriteSyncManager manager;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
    outboxDao = OutboxDao(db);
    fakeService = _RecordingAppwriteService();
    // ⚠️ المدير singleton بمُنشئ factory يتجاهل المعاملات بعد أول إنشاء
    // (نفس قيد phase0_data_integrity_test) — الإنشاء الأول هنا بالخدمة
    // المزيفة، فكل مسارات هذا الملف آمنة من الشبكة.
    manager = AppwriteSyncManager(
      appwriteService: fakeService,
      database: db,
    );
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    // نظافة قبل كل اختبار (أبناء قبل آباء لقيود FK).
    await db.delete(db.outbox).go();
    await db.delete(db.salaryWithdrawals).go();
    await db.delete(db.shiftNotes).go();
    await db.delete(db.employees).go();
    fakeService.upsertedDocuments.clear();
    fakeService.upsertedBlacklist.clear();
    fakeService.deletedBlacklist.clear();
    fakeService.getDocumentCalls = 0;
  });

  Future<int> addEmployeeWithServerId({int id = 42, String uuid = 'uuid-42'}) =>
      db.into(db.employees).insert(
            EmployeesCompanion(
              id: d.Value(id),
              name: const d.Value('أحمد'),
              basicSalary: const d.Value(6000),
              status: const d.Value('active'),
              hireDate: const d.Value('2026-01-01'),
              localUuid: d.Value(uuid),
              serverId: d.Value(id),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );

  /// سحبة يتيمة بموظف ميت — إدراج SQL خام مع إطفاء FK مؤقتاً
  /// (نفس منهجية employee_link_consistency_test — اليتائم الواقعية
  /// موجودة في قواعد الأجهزة من مسارات ما قبل القيد).
  Future<String> createOrphanWithdrawalRaw({required int deadEmployeeId}) async {
    final localUuid = 'sw-orphan-${DateTime.now().microsecondsSinceEpoch}';
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.customStatement(
        'INSERT INTO salary_withdrawals '
        '(employee_id, amount, withdraw_date, withdrawal_type, hotel_day_key, '
        'reason, local_uuid, created_at, updated_at, last_modified, '
        'version, origin) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 1000, 1000, 1000, 1, ?)',
        [
          deadEmployeeId,
          5000.0,
          '2026-10-01',
          'سحب راتب',
          '2026-10-01',
          null,
          localUuid,
          'local',
        ],
      );
    } finally {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }
    return localUuid;
  }

  Future<int> enqueueOutbox({
    required String entity,
    required String localUuid,
    String op = 'create',
  }) =>
      db.into(db.outbox).insert(
            OutboxCompanion(
              entity: d.Value(entity),
              op: d.Value(op),
              localUuid: d.Value(localUuid),
              payload: const d.Value('{}'),
              clientTs: d.Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            ),
          );

  Future<OutboxData?> outboxByLocalUuid(String localUuid) =>
      (db.select(db.outbox)..where((t) => t.localUuid.equals(localUuid)))
          .getSingleOrNull();

  // ═══════════════════════════════════════════════════════════════════════
  group('P0.5 (R6): سحبة راتب بموظف غائب تبقى في الطابور', () {
    test(
      'return false + صفر كتابات سحابية + العنصر يبقى محجوزاً بلا تسليم',
      () async {
        final uuid = await createOrphanWithdrawalRaw(deadEmployeeId: 999);
        await enqueueOutbox(entity: 'salary_withdrawals', localUuid: uuid);

        // حجز العنصر من الطابور كما تفعل حلقة الدفع الحقيقية (takeBatch).
        final batch = await outboxDao.takeBatch(5, sources: const ['local']);
        expect(batch, hasLength(1));

        final ok = await manager.processSalaryWithdrawalEntryForTesting(
          batch.first,
        );

        expect(ok, isFalse, reason: 'الموظف غائب → العنصر لم يُسلَّم');

        final row = await outboxByLocalUuid(uuid);
        expect(row, isNotNull, reason: 'العنصر يجب أن يبقى في الطابور');
        expect(
          row!.processingStatus,
          'processing',
          reason: 'يبقى محجوزاً حتى يسترجعه reclaimForPush في الدورة التالية',
        );
        expect(
          row.deliveredToPrimary,
          isFalse,
          reason: 'لا علامة تسليم — السجل لم يُرفع ولم يُحذف من الطابور',
        );
        expect(
          fakeService.upsertedDocuments,
          isEmpty,
          reason: 'صفر كتابات سحابية — لا رفع سحبة بلا موظف (FK)',
        );
        expect(
          fakeService.getDocumentCalls,
          0,
          reason: 'حارس غياب الموظف يسبق أي وصول للشبكة',
        );
      },
    );

    test(
      'reclaimForPush يُعيده إلى pending ثم ينجح الرفع بعد وصول الموظف',
      () async {
        final uuid = await createOrphanWithdrawalRaw(deadEmployeeId: 42);
        await enqueueOutbox(entity: 'salary_withdrawals', localUuid: uuid);
        final batch = await outboxDao.takeBatch(5, sources: const ['local']);
        expect(
          await manager.processSalaryWithdrawalEntryForTesting(batch.first),
          isFalse,
        );
        expect(fakeService.upsertedDocuments, isEmpty);

        // تقادم الحجز ثم الاسترجاع — محاكاة الدورة التالية للمزامنة.
        await (db.update(db.outbox)..where((t) => t.localUuid.equals(uuid)))
            .write(const OutboxCompanion(processingStartedAt: d.Value(1000)));
        final reclaimed = await outboxDao.reclaimForPush(
          stuckAfter: const Duration(seconds: 1),
        );
        expect(reclaimed, 1, reason: 'العنصر العالق يُسترجع');
        final pendingRow = await outboxByLocalUuid(uuid);
        expect(pendingRow!.processingStatus, 'pending');

        // ✅ وصول الموظف (عبر المزامنة) ثم إعادة المحاولة → نجاح كامل.
        await addEmployeeWithServerId(id: 42, uuid: 'uuid-42');
        final ok = await manager.processSalaryWithdrawalEntryForTesting(
          pendingRow,
        );
        expect(ok, isTrue, reason: 'بعد وصول الموظف تُرفع السحبة بنجاح');
        expect(
          fakeService.upsertedDocuments
              .where((u) => u.documentId == uuid),
          hasLength(1),
          reason: 'السحبة وصلت السحابة مرة واحدة بالضبط',
        );
        expect(
          fakeService.getDocumentCalls,
          1,
          reason: 'فحص OCC واحد قبل الرفع (404 → create)',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  group('blacklist: رفع القائمة السوداء بلا حذف سحابي', () {
    Future<int> addBlacklistRow({String uuid = 'bl-1'}) =>
        db.into(db.shiftNotes).insert(
              ShiftNotesCompanion(
                title: const d.Value('أورمو محمد'),
                content: const d.Value(
                  '{"nationality":"EG","nationalId":"123","phone":"010",'
                  '"reason":"اختبار","notes":"","reportedBy":"police",'
                  '"active":true}',
                ),
                createdBy: const d.Value('blacklist'),
                localUuid: d.Value(uuid),
                createdAt: const d.Value(1000),
                updatedAt: const d.Value(1000),
                lastModified: const d.Value(1000),
              ),
            );

    test(
      'رفع إنشاء صف blacklist → upsert واحد، صفر حذف، والعنصر يُسلَّم',
      () async {
        await addBlacklistRow();
        await enqueueOutbox(entity: 'blacklist', localUuid: 'bl-1');
        final batch = await outboxDao.takeBatch(5, sources: const ['local']);

        final ok = await manager.processBlacklistEntryForTesting(batch.first);

        expect(ok, isTrue, reason: 'الصف موجود محلياً → يُرفع بنجاح');
        expect(
          fakeService.upsertedBlacklist,
          ['bl-1'],
          reason: 'رفع واحد للمستند السحابي',
        );
        expect(
          fakeService.deletedBlacklist,
          isEmpty,
          reason:
              'العلة القديمة كانت تحذف المستند السحابي عند كل رفع إنشاء/تحديث',
        );
        expect(
          fakeService.getDocumentCalls,
          1,
          reason: 'فحص OCC واحد قبل الرفع (404 → create)',
        );
      },
    );

    test('رفع تحديث صف blacklist → upsert ولا حذف (نفس حارس العلة)', () async {
      await addBlacklistRow();
      await enqueueOutbox(entity: 'blacklist', localUuid: 'bl-1', op: 'update');
      final batch = await outboxDao.takeBatch(5, sources: const ['local']);

      final ok = await manager.processBlacklistEntryForTesting(batch.first);

      expect(ok, isTrue);
      expect(fakeService.upsertedBlacklist, ['bl-1']);
      expect(fakeService.deletedBlacklist, isEmpty);
    });

    test(
      'فلاتر المُلقّين: مُلقٍ blacklist يرى الصف ومُلقٍ shift_notes لا يراه',
      () async {
        await addBlacklistRow(uuid: 'bl-2');

        final viaBlacklist =
            await manager.blacklistEntryByLocalUuidForTesting('bl-2');
        final viaShiftNote = await manager.shiftNoteByLocalUuidForTesting(
          'bl-2',
        );

        expect(
          viaBlacklist,
          isNotNull,
          reason:
              "المُلقٍ المخصص (createdBy='blacklist') يجد الصف → الرفع يكمل "
              'مسار upsert بدل السقوط في مسار الحذف',
        );
        expect(
          viaShiftNote,
          isNull,
          reason:
              "المُلقٍ القديم (createdBy='user') أعمى عن الصف — هذه العمى "
              'كانت مصدر علة الحذف قبل إصلاح 2026-10-04',
        );
      },
    );
  });
}
