// سياسة حسم التعارض المعتمدة في وثيقة الربط (§7.5): **Cloud Wins**.
//
// القاعدة الحاكمة: نسخة Appwrite هي المرجع والفائزة دائماً عند اختلاف
// الأجهزة. لا دمج حقول، ولا اختيار نسخة الجهاز، ولا مقارنة ساعات.
// هذا الملف يحمل **القرار النقي** (بلا شبكة ولا قاعدة بيانات) ليُختبر
// منفصلاً، ويُستدعى من مسار الرفع قبل أي كتابة سحابية.

/// سبب اعتماد نسخة السحابة على السجل المحلي.
enum CloudWinsReason {
  /// لا تعارض: السحابة ليست أحدث — يكمل الرفع بشكل طبيعي.
  none,

  /// السحابة تحمل `version` أعلى من النسخة المحلية ⇒ نسخة الجهاز متقادمة.
  cloudNewerVersion,

  /// السحابة تحمل Tombstone (deletedAt) والمحلي غير محذوف ⇒ الحذف السحابي
  /// يفوز ويمنع إعادة إحياء السجل من Outbox قديم.
  cloudTombstone,
}

/// نتيجة تقييم سياسة Cloud Wins لعنصر Outbox واحد.
class CloudWinsDecision {
  const CloudWinsDecision(this.reason, {this.cloudData});

  final CloudWinsReason reason;

  /// نسخة السحابة الواجب تطبيقها محلياً عند [supersededLocal].
  final Map<String, dynamic>? cloudData;

  /// هل يجب إلغاء الرفع المحلي وإعلانه `superseded_by_cloud`؟
  bool get supersededLocal => reason != CloudWinsReason.none;
}

/// قرار Cloud Wins النقي + خرائط الكيانات/الجداول المستخدمة في التشخيص.
abstract final class CloudWinsPolicy {
  /// حالة عنصر Outbox الذي أُلغي بسبب نسخة سحابية أحدث.
  ///
  /// ليست `pending` ولا `failed` ولا `completed`: لا تُعاد المحاولة أبداً
  /// (لأنها لو أُعيدت لكتبت فوق السحابة) ولا تُحذف كأنها نجحت بلا تأكيد
  /// (تبقى أثراً تشخيصياً دائماً كما تنص §7.5).
  static const String supersededStatus = 'superseded_by_cloud';

  /// الحالات النهائية لعنصر Outbox (لا تُحسب «معلّقة» ولا تُعاد محاولتها).
  static const Set<String> finalStatuses = {
    'completed',
    'dead',
    supersededStatus,
  };

  /// كيان Outbox ← جدول SQLite المحلي (لقراءة النسخة المحلية عند الحسم).
  static const Map<String, String> tableByEntity = {
    'rooms': 'rooms',
    'bookings': 'bookings',
    'payments': 'payments',
    'expenses': 'expenses',
    'debts': 'debts',
    'employees': 'employees',
    'booking_notes': 'booking_notes',
    'booking_nights': 'booking_nights',
    'cash_transactions': 'cash_transactions',
    'shift_notes': 'shift_notes',
    'salary_cycles': 'salary_cycles',
    'salary_payments': 'salary_payments',
    'salary_withdrawals': 'salary_withdrawals',
    'salary_carry_over_logs': 'salary_carry_over_logs',
    'guest_infos': 'guest_infos',
    'blacklist': 'blacklist',
    'booking_price_adjustments': 'booking_price_adjustments',
    'price_adjustments': 'price_adjustments',
    'payment_voids': 'payment_voids',
    'audit_logs': 'audit_logs',
    'app_users': 'app_users',
    'inventory_items': 'inventory_items',
    'inventory_transactions': 'inventory_transactions',
  };

  static String? tableForEntity(String entity) => tableByEntity[entity];

  /// يقارن النسخة المحلية بنسخة السحابة ويعيد القرار.
  ///
  /// [localVersion] — `version` للصف المحلي (صف SyncFields).
  /// [localDeletedAt] — `deleted_at` المحلي (null = غير محذوف).
  /// [cloud] — بيانات وثيقة Appwrite (`null` = غير موجودة سحابياً ⇒ لا تعارض).
  ///
  /// ⚠️ لا يُعتمد في الحسم على `updatedAt`/ساعة الجهاز، بل على `version`
  /// الذي يرفعه الخادم/الأجهزة مع كل تعديل، وعلى Tombstone.
  static CloudWinsDecision decide({
    required int localVersion,
    required int? localDeletedAt,
    required Map<String, dynamic>? cloud,
  }) {
    if (cloud == null) {
      return const CloudWinsDecision(CloudWinsReason.none);
    }

    final cloudDeletedAt = deletedAtOf(cloud);
    if (cloudDeletedAt != null && localDeletedAt == null) {
      return CloudWinsDecision(
        CloudWinsReason.cloudTombstone,
        cloudData: cloud,
      );
    }

    final cloudVersion = versionOf(cloud);
    if (cloudVersion > localVersion) {
      return CloudWinsDecision(
        CloudWinsReason.cloudNewerVersion,
        cloudData: cloud,
      );
    }

    return const CloudWinsDecision(CloudWinsReason.none);
  }

  /// `version` من وثيقة سحابية — يقبل int أو نصاً رقمياً؛ غير ذلك 0
  /// (غياب الحقل يعني «لا دليل على حداثة السحابة» ⇒ لا إلغاء للرفع).
  static int versionOf(Map<String, dynamic> cloud) {
    final raw = cloud['version'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  /// `deletedAt` من وثيقة سحابية — 0/سلسلة فارغة تُعامل كغير محذوف.
  static int? deletedAtOf(Map<String, dynamic> cloud) {
    final raw = cloud['deletedAt'];
    final parsed = switch (raw) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}
