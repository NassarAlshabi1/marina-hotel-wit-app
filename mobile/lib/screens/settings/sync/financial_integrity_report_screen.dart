import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/app_scaffold.dart';
import '../../../providers/repository_providers.dart';
import '../../../services/repositories/financial_integrity_repository.dart';

/// ✅ «وثيقة الربط والمزامنة Appwrite الموحدة» — §11 تقرير سلامة دائم.
///
/// شاشة صيانة **قراءة فقط**: تعرض أدلة مشاكل الربط والمزامنة المالية
/// (مصروف بلا مرآة، مرآة يتيمة، مسحوب بلا موظف، روابط رقمية متقادمة،
/// مرايا مكررة، pending links، outbox متعثر، والإجماليات المحلية لكل
/// موظف للمقارنة مع السحابة). «لا يقوم التقرير بأي حذف أو تصحيح تلقائي؛
/// يعرض الأدلة ويتيح إصلاحاً صريحاً ومدققاً» (§11).
class FinancialIntegrityReportScreen extends ConsumerStatefulWidget {
  const FinancialIntegrityReportScreen({super.key});

  @override
  ConsumerState<FinancialIntegrityReportScreen> createState() =>
      _FinancialIntegrityReportScreenState();
}

class _FinancialIntegrityReportScreenState
    extends ConsumerState<FinancialIntegrityReportScreen> {
  Future<FinancialIntegrityReport>? _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = _load();
  }

  Future<FinancialIntegrityReport> _load() async {
    final db = ref.read(databaseProvider);
    return FinancialIntegrityRepository(db).build();
  }

  void _refresh() {
    setState(() => _reportFuture = _load());
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تقرير سلامة الروابط المالية',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'تحديث',
          onPressed: _refresh,
        ),
      ],
      body: FutureBuilder<FinancialIntegrityReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'فشل بناء التقرير: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final report = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _headerCard(report),
              const SizedBox(height: 12),
              _section(
                title: 'مصروفات رواتب نشطة بلا مرآة',
                icon: Icons.receipt_long,
                rows: report.salaryExpensesWithoutMirror,
              ),
              _section(
                title: 'مرايا نشطة بلا مصروف',
                icon: Icons.link_off,
                rows: report.activeMirrorsWithoutExpense,
              ),
              _section(
                title: 'مسحوبات بلا employeeUuid',
                icon: Icons.person_off,
                rows: report.withdrawalsWithoutEmployeeUuid,
              ),
              _section(
                title: 'employeeUuid لا يطابق موظفاً',
                icon: Icons.person_search,
                rows: report.unknownEmployeeUuidRefs,
              ),
              _section(
                title: 'اختلاف employeeId عمّا يحله UUID',
                icon: Icons.rule,
                rows: report.employeeIdMismatches,
              ),
              _section(
                title: 'اختلاف relatedId عمّا يحله UUID',
                icon: Icons.rule_folder,
                rows: report.relatedIdMismatches,
              ),
              _section(
                title: 'اختلاف expenseId عمّا يحله UUID',
                icon: Icons.rule_sharp,
                rows: report.expenseIdMismatches,
              ),
              _section(
                title: 'أكثر من مرآة نشطة لنفس expenseUuid',
                icon: Icons.copy_all,
                rows: report.duplicateActiveMirrors,
              ),
              _section(
                title: 'pending links (روابط معلّقة)',
                icon: Icons.schedule,
                rows: report.pendingLinks,
              ),
              _section(
                title: 'outbox المتعثر وسبب عدم الرفع',
                icon: Icons.outbox,
                rows: report.stuckOutbox,
              ),
              const SizedBox(height: 12),
              _totalsCard(report),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard(FinancialIntegrityReport report) {
    final clean = report.isClean;
    return Card(
      color: clean ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              clean ? Icons.verified : Icons.warning_amber,
              color: clean ? Colors.green : Colors.orange,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                clean
                    ? 'لا توجد مشاكل ربط مكتشفة في البيانات المحلية.'
                    : 'توجد مشاكل ربط تحتاج مراجعة — اعرض الأقسام أدناه. '
                          'هذا التقرير قراءة فقط ولا يُصلح شيئاً تلقائياً (وثيقة §11).',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<String> rows,
  }) {
    final count = rows.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(
          count == 0 ? Icons.check_circle : Icons.error_outline,
          color: count == 0 ? Colors.green : Colors.redAccent,
        ),
        title: Text(title),
        subtitle: Text(
          count == 0 ? 'سليم — لا سجلات' : '$count سجل',
          style: TextStyle(
            color: count == 0 ? Colors.green : Colors.redAccent,
            fontSize: 12,
          ),
        ),
        initiallyExpanded: false,
        children: count == 0
            ? const []
            : [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 16,
                    end: 16,
                    bottom: 12,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SelectableText(
                      rows.join('\n'),
                      style: const TextStyle(fontSize: 11.5, height: 1.6),
                    ),
                  ),
                ),
              ],
      ),
    );
  }

  Widget _totalsCard(FinancialIntegrityReport report) {
    final entries = report.localTotalsByEmployee.entries.toList()
      ..sort(
        (a, b) => b.value.withdrawalAmount.compareTo(a.value.withdrawalAmount),
      );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الإجماليات المحلية حسب employeeUuid '
              '(جانب المقارنة مع السحابة — §11)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text(
              'استخدم هذه الأرقام للمقارنة مع export السحابة عبر السكربت '
              'المدقق — لا يقارن التطبيق مع Appwrite مباشرة هنا (§10.7).',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty) const Text('لا توجد إجماليات مرتبطة بموظفين.'),
            ...entries.map((e) {
              final t = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${e.key.substring(0, e.key.length.clamp(0, 13))}… — '
                  'مصروفات: ${t.expenseCount} (${t.expenseAmount.toStringAsFixed(2)}) — '
                  'مسحوبات: ${t.withdrawalCount} '
                  '(${t.withdrawalAmount.toStringAsFixed(2)})',
                  style: const TextStyle(fontSize: 11.5, height: 1.5),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
