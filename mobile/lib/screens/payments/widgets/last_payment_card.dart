import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/local_db.dart' as db;
import '../../../utils/date_parser.dart';

/// بطاقة صغيرة تعرض آخر مبلغ مدفوع على الحجز في شاشة معالجة المدفوعات.
///
/// - تختار أحدث دفعة غير ملغاة ([db.Payment.isVoided]) حسب تاريخ الدفع.
/// - تعرض المبلغ وطريقة الدفع وتاريخ/وقت الدفع في سطر واحد مضغوط.
/// - تُخفى بالكامل ([SizedBox.shrink]) إذا لم توجد أي دفعة صالحة،
///   حتى لا تشغل مساحة في الحجوزات التي لم تُسدَّد فيها مدفوعات بعد.
///
/// الودجت عرضي بحت (read-only): يقرأ من قائمة المدفوعات الممرَّرة إليه
/// ولا يعدّل أي بيانات ولا يستدعي أي مستودع.
class LastPaymentCard extends StatelessWidget {
  const LastPaymentCard({
    required this.payments,
    required this.currencyFmt,
    super.key,
  });

  /// مدفوعات الحجز (قد تشمل مدفوعات ملغاة؛ تُستبعد داخلياً).
  final List<db.Payment> payments;

  /// منسق الأرقام المستخدم في بقية الشاشة (تنسيق موحد).
  final NumberFormat currencyFmt;

  /// أحدث دفعة غير ملغاة؛ `null` إن لم توجد أي دفعة صالحة.
  ///
  /// المفاضلة على التاريخ تتم عبر [DateParser] لتوافق صيغ التخزين
  /// المختلفة (ISO بـ T أو بمسافة، مع/بدون ثوانٍ) — نفس الأداة
  /// المستخدمة في بقية الشاشة.
  db.Payment? _latestValidPayment() {
    db.Payment? latest;
    DateTime? latestDate;
    for (final p in payments) {
      if (p.isVoided) continue;
      final d = DateParser.parse(p.paymentDate);
      if (d == null) continue;
      if (latest == null || latestDate == null || d.isAfter(latestDate)) {
        latest = p;
        latestDate = d;
      }
    }
    return latest;
  }

  /// أيقونة مناسبة لطريقة الدفع المخزنة نصياً في قاعدة البيانات.
  IconData _methodIcon(String method) {
    switch (method) {
      case 'نقدي':
      case 'نقداً':
        return Icons.payments;
      case 'بطاقة':
      case 'بطاقة ائتمان':
        return Icons.credit_card;
      case 'تحويل':
      case 'تحويل بنكي':
        return Icons.account_balance;
      case 'شيك':
        return Icons.receipt_long;
      case 'تقسيط':
        return Icons.calendar_month;
      default:
        return Icons.payments;
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _latestValidPayment();
    // لا مدفوعات صالحة → لا بطاقة (توفير مساحة عمودية).
    if (last == null) return const SizedBox.shrink();

    final methodText = last.paymentMethod.trim();
    final date = DateParser.parse(last.paymentDate);
    final parts = <String>[
      if (methodText.isNotEmpty) methodText,
      if (date != null) DateFormat('yyyy/MM/dd • HH:mm').format(date),
    ];
    final detailsText = parts.join(' • ');

    // هوية بصرية موحّدة مع بطاقة الملخص (تدرجات أخضر للدفع المسدد).
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(
            _methodIcon(last.paymentMethod),
            size: 20,
            color: Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            'آخر مبلغ مدفوع',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              detailsText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            currencyFmt.format(last.amount),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
