/// منطق حساب دورة راتب واحدة دون ارتباط بواجهة المستخدم أو قاعدة البيانات.
///
/// القاعدة المحاسبية المستخدمة في النظام الحالي:
/// - السلفة مبلغ استلمه الموظف فعلاً، لذلك تُخصم من استحقاق الدورة.
/// - قسط السلفة يسدد رصيد السلفة، ولا يُخصم مرة ثانية من صافي الدورة.
/// - الترحيل السابق يُخصم من الدورة الحالية.
/// - العجز في نهاية الدورة يُرحّل إلى الدورة التالية مرة واحدة.
///
/// جميع القيم المالية هنا أعداد صحيحة متوافقة مع سياسة الفندق.
class SalaryCycleInput {
  const SalaryCycleInput({
    required this.basicSalary,
    this.withdrawals = 0,
    this.advances = 0,
    this.installmentsPaid = 0,
    this.deductions = 0,
    this.carriedOverFromPrevious = 0,
  });

  final num basicSalary;
  final num withdrawals;
  final num advances;
  final num installmentsPaid;
  final num deductions;
  final num carriedOverFromPrevious;
}

class SalaryCycleResult {
  const SalaryCycleResult({
    required this.basicSalary,
    required this.withdrawals,
    required this.advances,
    required this.installmentsPaid,
    required this.deductions,
    required this.carriedOverFromPrevious,
    required this.totalBeforeCarryOver,
    required this.remainingBalance,
    required this.carryOverToNext,
    required this.advanceBalance,
  });

  final int basicSalary;
  final int withdrawals;
  final int advances;
  final int installmentsPaid;
  final int deductions;
  final int carriedOverFromPrevious;
  final int totalBeforeCarryOver;
  final int remainingBalance;
  final int carryOverToNext;
  final int advanceBalance;

  bool get hasExceeded => carryOverToNext > 0;
  bool get isFullySettled => remainingBalance == 0 && !hasExceeded;
}

class SalaryCycleCalculator {
  const SalaryCycleCalculator._();

  /// يحسب دورة الراتب وفق القاعدة الحالية دون إنشاء أي سجل أو Outbox.
  static SalaryCycleResult calculate(SalaryCycleInput input) {
    final basicSalary = _money(input.basicSalary);
    final withdrawals = _money(input.withdrawals);
    final advances = _money(input.advances);
    final installmentsPaid = _money(input.installmentsPaid);
    final deductions = _money(input.deductions);
    final carriedOver = _money(input.carriedOverFromPrevious);

    final totalBeforeCarryOver =
        withdrawals + advances + deductions + carriedOver;
    final signedRemaining = basicSalary - totalBeforeCarryOver;
    final remainingBalance = signedRemaining > 0 ? signedRemaining : 0;
    final carryOverToNext = signedRemaining < 0 ? -signedRemaining : 0;

    final advanceBalance = (advances - installmentsPaid)
        .clamp(0, advances)
        .toInt();

    return SalaryCycleResult(
      basicSalary: basicSalary,
      withdrawals: withdrawals,
      advances: advances,
      installmentsPaid: installmentsPaid,
      deductions: deductions,
      carriedOverFromPrevious: carriedOver,
      totalBeforeCarryOver: totalBeforeCarryOver,
      remainingBalance: remainingBalance,
      carryOverToNext: carryOverToNext,
      advanceBalance: advanceBalance,
    );
  }

  /// يحوّل قيمة قديمة من SQLite/Drift إلى مبلغ صحيح.
  /// يتم التقريب مرة واحدة عند حدود النظام، وليس أثناء الجمع المتكرر.
  static int _money(num value) => value.round().clamp(0, 0x7fffffff).toInt();
}
