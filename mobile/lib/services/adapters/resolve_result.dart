class ResolveResult {
  const ResolveResult({
    this.bookingLocalId,
    this.bookingUuidCache,
    this.employeeLocalId,
    this.employeeUuid,
    this.employeeRelatedId,
    this.salaryCycleLocalId,
    this.inventoryItemLocalId,
    this.createdAtEpoch,
    this.lastModifiedEpoch,
    this.shouldSkip = false,
    this.skipReason,
  });

  final int? bookingLocalId;
  final String? bookingUuidCache;

  /// معرّف الموظف المحلي بعد الحل (لـ FK: salary_withdrawals, salary_cycles)
  final int? employeeLocalId;

  /// ✅ (2026-09-19) uuid الموظف المستقر عبر الأجهزة — يخزَّن في عمود
  /// employee_uuid الجديد (migration 68) ويُعاد إرساله في دفعات المزامنة
  /// (toJson) فيصل رابط الموظف عبر الأجهزة. يُستخرج من جدول employees
  /// المحلي عند حل الموظف، أو من الحمولة القادمة كاحتياط.
  final String? employeeUuid;

  /// معرّف الموظف المحلي بعد الحل (لـ FK: expenses.relatedId في مصروفات الرواتب)
  /// يُستخدم فقط عندما يكون expenseType مرتبطاً بالرواتب
  final int? employeeRelatedId;

  /// معرّف دورة الراتب المحلي بعد الحل (لـ FK: salary_payments)
  final int? salaryCycleLocalId;

  /// معرّف الصنف المحلي بعد حل حركة المخزون عبر itemLocalUuid.
  final int? inventoryItemLocalId;

  final int? createdAtEpoch;
  final int? lastModifiedEpoch;

  /// ✅ إصلاح: علامة لتخطي السجل عندما يفشل حل المرجع الخارجي (FK)
  /// يُستخدم عندما لا يمكن العثور على السجل الأب (مثل حجز غير موجود لليالي)
  /// بدلاً من إدراج سجل بقيمة Value.absent() في حقل مطلوب مما يسبب InvalidDataException
  final bool shouldSkip;

  /// سبب التخطي (للتسجيل في السجلات)
  final String? skipReason;

  static const empty = ResolveResult();

  ResolveResult copyWith({
    int? bookingLocalId,
    String? bookingUuidCache,
    int? employeeLocalId,
    String? employeeUuid,
    int? employeeRelatedId,
    int? salaryCycleLocalId,
    int? inventoryItemLocalId,
    int? createdAtEpoch,
    int? lastModifiedEpoch,
    bool? shouldSkip,
    String? skipReason,
  }) {
    return ResolveResult(
      bookingLocalId: bookingLocalId ?? this.bookingLocalId,
      bookingUuidCache: bookingUuidCache ?? this.bookingUuidCache,
      employeeLocalId: employeeLocalId ?? this.employeeLocalId,
      employeeUuid: employeeUuid ?? this.employeeUuid,
      employeeRelatedId: employeeRelatedId ?? this.employeeRelatedId,
      salaryCycleLocalId: salaryCycleLocalId ?? this.salaryCycleLocalId,
      inventoryItemLocalId: inventoryItemLocalId ?? this.inventoryItemLocalId,
      createdAtEpoch: createdAtEpoch ?? this.createdAtEpoch,
      lastModifiedEpoch: lastModifiedEpoch ?? this.lastModifiedEpoch,
      shouldSkip: shouldSkip ?? this.shouldSkip,
      skipReason: skipReason ?? this.skipReason,
    );
  }
}
