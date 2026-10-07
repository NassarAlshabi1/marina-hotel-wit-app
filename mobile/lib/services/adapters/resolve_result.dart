class ResolveResult {
  const ResolveResult({
    this.bookingLocalId,
    this.bookingUuidCache,
    this.employeeLocalId,
    this.employeeRelatedId,
    this.salaryCycleLocalId,
    this.inventoryItemLocalId,
    this.createdAtEpoch,
    this.lastModifiedEpoch,
    this.shouldSkip = false,
    this.skipReason,
    this.suppressEmployeeLink = false,
  });

  final int? bookingLocalId;
  final String? bookingUuidCache;

  /// معرّف الموظف المحلي بعد الحل (لـ FK: salary_withdrawals, salary_cycles)
  final int? employeeLocalId;

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

  /// ✅ (m69 — استكمال عقد employeeLinkCleared) الصف المحلي يحمل إزالة
  /// رابط **صراحةً** (employeeLinkCleared=true)، والحمولة الواردة سجل ما
  /// قبل العقد (بلا مفتاح employeeLinkCleared أصلاً) ⇒ لا نسمح للحمولة
  /// القديمة بإحياء رابط أزاله المستخدم. يُكتب الصف وارداً بلا رابط
  /// (relation-incomplete) ويبقى العلم مرفوعاً حتى تصل نسخة ما بعد العقد
  /// تُصرّح بإعادة الربط (employeeLinkCleared=false + employeeUuid).
  final bool suppressEmployeeLink;

  static const empty = ResolveResult();

  ResolveResult copyWith({
    int? bookingLocalId,
    String? bookingUuidCache,
    int? employeeLocalId,
    int? employeeRelatedId,
    int? salaryCycleLocalId,
    int? inventoryItemLocalId,
    int? createdAtEpoch,
    int? lastModifiedEpoch,
    bool? shouldSkip,
    String? skipReason,
    bool? suppressEmployeeLink,
  }) {
    return ResolveResult(
      bookingLocalId: bookingLocalId ?? this.bookingLocalId,
      bookingUuidCache: bookingUuidCache ?? this.bookingUuidCache,
      employeeLocalId: employeeLocalId ?? this.employeeLocalId,
      employeeRelatedId: employeeRelatedId ?? this.employeeRelatedId,
      salaryCycleLocalId: salaryCycleLocalId ?? this.salaryCycleLocalId,
      inventoryItemLocalId: inventoryItemLocalId ?? this.inventoryItemLocalId,
      createdAtEpoch: createdAtEpoch ?? this.createdAtEpoch,
      lastModifiedEpoch: lastModifiedEpoch ?? this.lastModifiedEpoch,
      shouldSkip: shouldSkip ?? this.shouldSkip,
      skipReason: skipReason ?? this.skipReason,
      suppressEmployeeLink: suppressEmployeeLink ?? this.suppressEmployeeLink,
    );
  }
}
