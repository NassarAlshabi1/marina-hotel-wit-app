import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../components/admin_layout.dart';
import '../../services/providers.dart';
import '../../services/local_db.dart';
import '../../utils/time.dart';
import '../../utils/currency_formatter.dart';

class DebtsListScreen extends ConsumerWidget {
  const DebtsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(debtsListProvider);
    return AppScaffold(
      title: 'الديون',
      actions: [
        IconButton(
          onPressed: () => _openDebtForm(context, ref),
          icon: const Icon(Icons.add),
        ),
      ],
      body: debtsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('حدث خطأ: $error')),
        data: (debts) {
          if (debts.isEmpty) {
            return const Center(child: Text('لا توجد ديون مسجلة حتى الآن'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminCard(
                title: 'سجل الديون',
                child: AdminTable(
                  headers: const [
                    'اسم النزيل',
                    'تاريخ الدخول',
                    'تاريخ الخروج',
                    'إجمالي الدين',
                    'المبلغ المدفوع',
                    'المبلغ المتبقي',
                    'تاريخ الدفع',
                    'الرهن',
                    'نوع الرهن',
                    'ملاحظة',
                    'إجراءات',
                  ],
                  rows: debts
                      .map(
                        (debt) => [
                          Text(debt.guestName),
                          Text(_formatDate(debt.checkinDate)),
                          Text(_formatDate(debt.checkoutDate)),
                          Text(_formatAmount(debt.totalAmount)),
                          Text(_formatAmount(debt.paidAmount)),
                          Text(_formatAmount(debt.remainingAmount)),
                          Text(_formatDate(debt.paymentDate)),
                          Text(debt.pledge?.isNotEmpty == true ? debt.pledge! : '-'),
                          Text(debt.pledgeType?.isNotEmpty == true ? debt.pledgeType! : '-'),
                          Text(debt.note?.isNotEmpty == true ? debt.note! : '-'),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _openDebtForm(context, ref, existing: debt),
                                tooltip: 'تعديل',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () => _deleteDebt(context, ref, debt),
                                tooltip: 'حذف',
                              ),
                            ],
                          ),
                        ],
                      )
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatDate(String value) {
    return Time.safeIsoToDateString(value);
  }

  static String _formatAmount(double value) {
    return CurrencyFormatter.formatAmount(value);
  }

  Future<void> _openDebtForm(BuildContext context, WidgetRef ref, {Debt? existing}) async {
    final guestNameCtrl = TextEditingController(text: existing?.guestName ?? '');
    final checkinCtrl = TextEditingController(text: Time.safeIsoToDateString(existing?.checkinDate));
    final checkoutCtrl = TextEditingController(text: Time.safeIsoToDateString(existing?.checkoutDate));
    final totalCtrl = TextEditingController(text: existing != null ? CurrencyFormatter.formatAmount(existing.totalAmount) : '0');
    final paidCtrl = TextEditingController(text: existing != null ? CurrencyFormatter.formatAmount(existing.paidAmount) : '0');
    final remainingCtrl = TextEditingController(text: existing != null ? CurrencyFormatter.formatAmount(existing.remainingAmount) : '0');
    final paymentDateCtrl = TextEditingController(text: Time.safeIsoToDateString(existing?.paymentDate));
    final pledgeCtrl = TextEditingController(text: existing?.pledge ?? '');
    final pledgeTypeCtrl = TextEditingController(text: existing?.pledgeType ?? '');
    final noteCtrl = TextEditingController(text: existing?.note ?? '');

    void recalculate() {
      final total = double.tryParse(totalCtrl.text.replaceAll(',', '')) ?? 0;
      final paid = double.tryParse(paidCtrl.text.replaceAll(',', '')) ?? 0;
      final remaining = (total - paid).clamp(0, double.infinity).toDouble();
      remainingCtrl.text = CurrencyFormatter.formatAmount(remaining);
    }

    totalCtrl.addListener(recalculate);
    paidCtrl.addListener(recalculate);
    recalculate();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(existing == null ? 'إضافة دين' : 'تعديل دين'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: guestNameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم النزيل'),
                  ),
                  TextField(
                    controller: checkinCtrl,
                    decoration: const InputDecoration(labelText: 'تاريخ الدخول YYYY-MM-DD'),
                  ),
                  TextField(
                    controller: checkoutCtrl,
                    decoration: const InputDecoration(labelText: 'تاريخ الخروج YYYY-MM-DD'),
                  ),
                  TextField(
                    controller: totalCtrl,
                    decoration: const InputDecoration(labelText: 'إجمالي الدين'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: paidCtrl,
                    decoration: const InputDecoration(labelText: 'المبلغ المدفوع'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: remainingCtrl,
                    decoration: const InputDecoration(labelText: 'المبلغ المتبقي'),
                    readOnly: true,
                    enableInteractiveSelection: false,
                  ),
                  TextField(
                    controller: paymentDateCtrl,
                    decoration: const InputDecoration(labelText: 'تاريخ الدفع YYYY-MM-DD'),
                  ),
                  TextField(
                    controller: pledgeCtrl,
                    decoration: const InputDecoration(labelText: 'الرهن'),
                  ),
                  TextField(
                    controller: pledgeTypeCtrl,
                    decoration: const InputDecoration(labelText: 'نوع الرهن'),
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'ملاحظة'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final guestName = guestNameCtrl.text.trim();
    final checkinDate = checkinCtrl.text.trim().isEmpty ? Time.nowDateString() : checkinCtrl.text.trim();
    final checkoutDate = checkoutCtrl.text.trim().isEmpty ? Time.nowDateString() : checkoutCtrl.text.trim();
    final totalAmount = double.tryParse(totalCtrl.text.replaceAll(',', '')) ?? 0;
    final paidAmount = double.tryParse(paidCtrl.text.replaceAll(',', '')) ?? 0;
    final paymentDate = paymentDateCtrl.text.trim().isEmpty ? Time.nowDateString() : paymentDateCtrl.text.trim();
    final pledge = pledgeCtrl.text.trim().isEmpty ? null : pledgeCtrl.text.trim();
    final pledgeType = pledgeTypeCtrl.text.trim().isEmpty ? null : pledgeTypeCtrl.text.trim();
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    if (guestName.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال اسم النزيل')));
      }
      return;
    }

    final repo = ref.read(debtsRepoProvider);
    if (existing == null) {
      await repo.create(
        guestName: guestName,
        checkinDate: checkinDate,
        checkoutDate: checkoutDate,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
        paymentDate: paymentDate,
        pledge: pledge,
        pledgeType: pledgeType,
        note: note,
      );
    } else {
      await repo.update(
        id: existing.id,
        guestName: guestName,
        checkinDate: checkinDate,
        checkoutDate: checkoutDate,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
        paymentDate: paymentDate,
        pledge: pledge,
        pledgeType: pledgeType,
        note: note,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ البيانات بنجاح')));
    }
  }

  Future<void> _deleteDebt(BuildContext context, WidgetRef ref, Debt debt) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تأكيد الحذف'),
            content: Text('هل أنت متأكد من حذف الدين الخاص بـ ${debt.guestName}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) {
      return;
    }

    final repo = ref.read(debtsRepoProvider);
    await repo.delete(debt.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الدين')));
    }
  }
}
