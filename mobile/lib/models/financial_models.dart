class AppliedAdjustment {

  const AppliedAdjustment({
    required this.uuid,
    required this.type,
    required this.amount,
    this.reason,
    this.appliedBy,
  });
  final String uuid;
  final String type;
  final int amount;
  final String? reason;
  final String? appliedBy;

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'type': type,
    'amount': amount,
    'reason': reason,
    'appliedBy': appliedBy,
  };
}

class NightlyBreakdown {

  const NightlyBreakdown({
    required this.hotelDayKey,
    required this.nightStart,
    required this.nightEnd,
    required this.baseRate,
    required this.adjustmentAmount,
    required this.finalRate,
    required this.appliedAdjustments,
  });
  final String hotelDayKey;
  final DateTime nightStart;
  final DateTime nightEnd;
  final int baseRate;
  final int adjustmentAmount;
  final int finalRate;
  final List<AppliedAdjustment> appliedAdjustments;
}

class FinancialSummary {

  const FinancialSummary({
    required this.subtotal,
    required this.totalAdjustments,
    required this.totalDue,
    required this.totalPaid,
    required this.remainingBalance,
    required this.totalNights,
    required this.isFullyPaid,
  });
  final int subtotal;
  final int totalAdjustments;
  final int totalDue;
  final int totalPaid;
  final int remainingBalance;
  final int totalNights;
  final bool isFullyPaid;
}
