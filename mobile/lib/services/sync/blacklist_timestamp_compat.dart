// lib/services/sync/blacklist_timestamp_compat.dart
//
// ✅ (2026-11-25) طبقة توافق طوابع blacklist — إصلاح تحذير Kilo على PR #694.
//
// السحابة تعرّف createdAt/updatedAt/deletedAt في مجموعة blacklist كـ
// integer (epoch seconds) — مثبت بتحقق حي (تدقيق 2026-11-24، راجع
// collectionSchema['blacklist'] في appwrite_sync_utils.dart). مسار السحب
// في AppwriteSyncManager._syncBlacklist كان مكتوباً على العقد القديم
// (ISO strings): `data['createdAt'] as String?` ترمي TypeError على قيمة
// int، فيُبتلع الاستثناء (درع فقدان صامت) وتفشل دفعة blacklist كاملة
// عند كل سحب.
//
// هذه الطبقة تُطبِّع الطوابع الرقمية إلى ISO strings قبل وصولها للمدير
// فيعمل مسار السحب القديم دون تعديل — مقابل تعديل المدير الضخم. جهة
// الدفع (PayloadMapper.blacklistToRemote) تُرسل epoch integers مباشرة
// (مطابقة للمخطط)، فالمسار كله متسق: int في السحابة ↔ int عند الدفع،
// وint → ISO string عند السحب (توافق مع عقد المحلل القائم).

import 'package:appwrite/models.dart' as models;

/// طوابع blacklist التي تعرّفها السحابة integer ويقرؤها مسار السحب
/// كـ ISO strings.
const _kTimestampKeys = <String>{'createdAt', 'updatedAt', 'deletedAt'};

class BlacklistTimestampCompat {
  BlacklistTimestampCompat._();

  /// يُطبِّع مستندات blacklist: أي طابع رقمي (epoch seconds) في
  /// [models.Document.data] يُحوَّل إلى ISO string. القيم النصية الأصلية
  /// (وثائق قديمة كُتبت ISO قبل محاية المخطط) تبقى كما هي.
  static List<models.Document> normalizeDocs(List<models.Document> docs) {
    if (docs.isEmpty) return docs;
    return [for (final doc in docs) _normalizeDoc(doc)];
  }

  static models.Document _normalizeDoc(models.Document doc) {
    final data = doc.data;
    var changed = false;
    final normalized = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (_kTimestampKeys.contains(entry.key) && value is int) {
        normalized[entry.key] = DateTime.fromMillisecondsSinceEpoch(
          value * 1000,
          isUtc: true,
        ).toIso8601String();
        changed = true;
      } else {
        normalized[entry.key] = value;
      }
    }
    if (!changed) return doc;
    return models.Document(
      $id: doc.$id,
      $sequence: doc.$sequence,
      $collectionId: doc.$collectionId,
      $databaseId: doc.$databaseId,
      $createdAt: doc.$createdAt,
      $updatedAt: doc.$updatedAt,
      $permissions: doc.$permissions,
      data: normalized,
    );
  }
}
