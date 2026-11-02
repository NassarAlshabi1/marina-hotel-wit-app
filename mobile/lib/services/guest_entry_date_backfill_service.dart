import 'package:appwrite/appwrite.dart';

import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'secondary_appwrite_config.dart';

/// تقدم عملية تعبئة entryDate في سجلات الضيوف على Appwrite Cloud.
class GuestEntryDateBackfillProgress {
  const GuestEntryDateBackfillProgress({
    this.scanned = 0,
    this.updated = 0,
    this.alreadyHadEntryDate = 0,
    this.deletedSkipped = 0,
    this.missingCreatedAt = 0,
  });

  final int scanned;
  final int updated;
  final int alreadyHadEntryDate;
  final int deletedSkipped;
  final int missingCreatedAt;
}

/// ملخص نهائي لعملية backfill.
class GuestEntryDateBackfillResult extends GuestEntryDateBackfillProgress {
  const GuestEntryDateBackfillResult({
    super.scanned,
    super.updated,
    super.alreadyHadEntryDate,
    super.deletedSkipped,
    super.missingCreatedAt,
  });
}

/// يملأ الحقول القديمة الناقصة مباشرةً في مجموعة guest_infos على Appwrite.
///
/// العملية مقسمة إلى صفحات ثابتة الترتيب، ويمكن إعادة تشغيلها بأمان؛ فهي
/// لا تستبدل entryDate الموجود ولا تغيّر أي حقل آخر.
class GuestEntryDateBackfillService {
  GuestEntryDateBackfillService(this._appwriteService);

  static const int pageSize = AppwriteConfig.batchSize;

  final AppwriteService _appwriteService;

  Future<GuestEntryDateBackfillResult> fillMissingEntryDates({
    void Function(GuestEntryDateBackfillProgress progress)? onProgress,
  }) async {
    if (_isSecondaryPullFailoverActive) {
      throw StateError(
        'أوقف التحويل إلى قاعدة Appwrite الثانوية قبل تعديل سجلات السحابة الأساسية.',
      );
    }

    var scanned = 0;
    var updated = 0;
    var alreadyHadEntryDate = 0;
    var deletedSkipped = 0;
    var missingCreatedAt = 0;
    String? cursor;

    void reportProgress() {
      onProgress?.call(
        GuestEntryDateBackfillProgress(
          scanned: scanned,
          updated: updated,
          alreadyHadEntryDate: alreadyHadEntryDate,
          deletedSkipped: deletedSkipped,
          missingCreatedAt: missingCreatedAt,
        ),
      );
    }

    while (true) {
      final queries = <String>[
        Query.orderAsc(r'$id'),
        Query.limit(pageSize),
        if (cursor != null && cursor.isNotEmpty) Query.cursorAfter(cursor),
      ];
      final documents = await _appwriteService.listDocumentsPage(
        collectionId: AppwriteConfig.guestInfosCollectionId,
        queries: queries,
      );

      if (documents.isEmpty) {
        break;
      }

      for (final document in documents) {
        cursor = document.$id;
        scanned++;

        if (isSoftDeleted(document.data)) {
          deletedSkipped++;
          continue;
        }
        if (!isEntryDateMissing(document.data['entryDate'])) {
          alreadyHadEntryDate++;
          continue;
        }

        try {
          // إعادة القراءة قرب الكتابة تمنع استبدال قيمة ملأها جهاز آخر
          // بعد جلب صفحة المستندات.
          final latestDocument = await _appwriteService.getDocument(
            collectionId: AppwriteConfig.guestInfosCollectionId,
            documentId: document.$id,
            suppressErrorLog: true,
          );
          if (isSoftDeleted(latestDocument.data)) {
            deletedSkipped++;
            continue;
          }
          if (!isEntryDateMissing(latestDocument.data['entryDate'])) {
            alreadyHadEntryDate++;
            continue;
          }

          final entryDate = entryDateFromCreatedAt(latestDocument.$createdAt);
          if (entryDate == null) {
            missingCreatedAt++;
            continue;
          }

          // إرسال الحقل المستهدف وحده يحافظ على بقية بيانات المستند.
          await _appwriteService.updateDocument(
            collectionId: AppwriteConfig.guestInfosCollectionId,
            documentId: document.$id,
            data: {'entryDate': entryDate},
          );
          updated++;
        } catch (_) {
          reportProgress();
          rethrow;
        }

        // تحديث واجهة التقدم على دفعات صغيرة دون إعادة بناء الشاشة لكل سجل.
        if (scanned % 5 == 0) {
          reportProgress();
        }
      }

      reportProgress();
      if (documents.length < pageSize) {
        break;
      }
    }

    return GuestEntryDateBackfillResult(
      scanned: scanned,
      updated: updated,
      alreadyHadEntryDate: alreadyHadEntryDate,
      deletedSkipped: deletedSkipped,
      missingCreatedAt: missingCreatedAt,
    );
  }

  /// يُعدّ الحقل ناقصاً فقط إذا كان null أو نصاً فارغاً/مسافات.
  /// الأنواع أو القيم الأخرى لا تُستبدل احتياطياً.
  static bool isEntryDateMissing(Object? value) {
    return value == null || (value is String && value.trim().isEmpty);
  }

  /// يتعرف على علامات الحذف المستخدمة في السجلات القديمة والحالية.
  static bool isSoftDeleted(Map<String, dynamic> data) {
    final rawDeletedAt = data['deletedAt'] ?? data['deleted_at'];
    final deletedAt = rawDeletedAt is num
        ? rawDeletedAt
        : num.tryParse(rawDeletedAt?.toString() ?? '');
    if (deletedAt != null && deletedAt > 0) {
      return true;
    }

    final deletedAtIso = data['deletedAtIso'] ?? data['deleted_at_iso'];
    return deletedAtIso is String && deletedAtIso.trim().isNotEmpty;
  }

  /// يحتفظ بتاريخ UTC كما أعاده Appwrite ويحوّله إلى yyyy-MM-dd.
  static String? entryDateFromCreatedAt(String? createdAt) {
    if (createdAt == null || createdAt.length < 10) {
      return null;
    }

    final date = createdAt.substring(0, 10);
    final parsedDate = DateTime.tryParse('${date}T00:00:00Z');
    if (!_datePattern.hasMatch(date) || parsedDate == null) {
      return null;
    }
    final year = int.parse(date.substring(0, 4));
    final month = int.parse(date.substring(5, 7));
    final day = int.parse(date.substring(8, 10));
    if (parsedDate.year != year ||
        parsedDate.month != month ||
        parsedDate.day != day) {
      return null;
    }
    return date;
  }

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static bool get _isSecondaryPullFailoverActive =>
      SecondaryAppwriteConfig.isFailoverActive &&
      SecondaryAppwriteConfig.isPullEnabled &&
      SecondaryAppwriteConfig.isEnabled &&
      SecondaryAppwriteConfig.isConfigured;
}
