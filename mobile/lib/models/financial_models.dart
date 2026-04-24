class AppliedAdjustment {
  final String uuid;
  final String type;
  final int amount;
  final String? reason;
  final String? appliedBy;

  const AppliedAdjustment({
    required this.uuid,
    required this.type,
    required this.amount,
    this.reason,
    this.appliedBy,
  });

  factory AppliedAdjustment.fromJson(Map<String, dynamic> json) {
    return AppliedAdjustment(
      uuid: (json['uuid'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String?,
      appliedBy: json['appliedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'type': type,
    'amount': amount,
    'reason': reason,
    'appliedBy': appliedBy,
  };
}

class NightlyBreakdown {
  final String hotelDayKey;
  final DateTime nightStart;
  final DateTime nightEnd;
  final int baseRate;
  final int adjustmentAmount;
  final int finalRate;
  final List<AppliedAdjustment> appliedAdjustments;

  const NightlyBreakdown({
    required this.hotelDayKey,
    required this.nightStart,
    required this.nightEnd,
    required this.baseRate,
    required this.adjustmentAmount,
    required this.finalRate,
    required this.appliedAdjustments,
  });

  factory NightlyBreakdown.fromJson(Map<String, dynamic> json) {
    return NightlyBreakdown(
      hotelDayKey: (json['hotelDayKey'] as String?) ?? '',
      nightStart: _parseDateTime(json['nightStart']),
      nightEnd: _parseDateTime(json['nightEnd']),
      baseRate: (json['baseRate'] as num?)?.toInt() ?? 0,
      adjustmentAmount: (json['adjustmentAmount'] as num?)?.toInt() ?? 0,
      finalRate: (json['finalRate'] as num?)?.toInt() ?? 0,
      appliedAdjustments: (json['appliedAdjustments'] as List<dynamic>?)
              ?.map((e) => AppliedAdjustment.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'hotelDayKey': hotelDayKey,
    'nightStart': nightStart.toIso8601String(),
    'nightEnd': nightEnd.toIso8601String(),
    'baseRate': baseRate,
    'adjustmentAmount': adjustmentAmount,
    'finalRate': finalRate,
    'appliedAdjustments':
        appliedAdjustments.map((a) => a.toJson()).toList(),
  };
}

class FinancialSummary {
  final int subtotal;
  final int totalAdjustments;
  final int totalDue;
  final int totalPaid;
  final int remainingBalance;
  final int totalNights;
  final bool isFullyPaid;

  const FinancialSummary({
    required this.subtotal,
    required this.totalAdjustments,
    required this.totalDue,
    required this.totalPaid,
    required this.remainingBalance,
    required this.totalNights,
    required this.isFullyPaid,
  });

  factory FinancialSummary.fromJson(Map<String, dynamic> json) {
    return FinancialSummary(
      subtotal: (json['subtotal'] as num?)?.toInt() ?? 0,
      totalAdjustments:
          (json['totalAdjustments'] as num?)?.toInt() ?? 0,
      totalDue: (json['totalDue'] as num?)?.toInt() ?? 0,
      totalPaid: (json['totalPaid'] as num?)?.toInt() ?? 0,
      remainingBalance:
          (json['remainingBalance'] as num?)?.toInt() ?? 0,
      totalNights: (json['totalNights'] as num?)?.toInt() ?? 0,
      isFullyPaid: (json['isFullyPaid'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'subtotal': subtotal,
    'totalAdjustments': totalAdjustments,
    'totalDue': totalDue,
    'totalPaid': totalPaid,
    'remainingBalance': remainingBalance,
    'totalNights': totalNights,
    'isFullyPaid': isFullyPaid,
  };
}

/// مساعد لتحليل التواريخ من JSON (يدعم String و DateTime)
DateTime _parseDateTime(dynamic value) {
  if (value == null) return DateTime.now();
  if (value is DateTime) return value;
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }
  return DateTime.now();
}
