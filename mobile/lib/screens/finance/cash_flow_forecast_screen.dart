import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/finance_kpi_providers.dart';
import '../../src/finance/finance_models.dart';
import '../../utils/currency_formatter.dart';

/// شاشة نموذج التدفقات النقدية لـ13 أسبوعاً.
///
/// تعرض توقعاً أسبوعياً بثلاث طبقات يقين مع السيناريوهات الثلاثة
/// (أساسي / متحفظ / ضغط) وحد السيولة الأدنى الديناميكي واحتياج التمويل.
class CashFlowForecastScreen extends ConsumerStatefulWidget {
  const CashFlowForecastScreen({super.key});

  @override
  ConsumerState<CashFlowForecastScreen> createState() =>
      _CashFlowForecastScreenState();
}

class _CashFlowForecastScreenState
    extends ConsumerState<CashFlowForecastScreen> {
  String _selectedScenarioKey = 'base';

  @override
  Widget build(BuildContext context) {
    final scenarios = ref.watch(scenarioSettingsProvider);
    final forecastAsync = ref.watch(forecastResultProvider(_selectedScenarioKey));

    return AppScaffold(
      title: 'التدفقات النقدية — 13 أسبوعاً',
      subtitle: 'توقع أسبوعي حي من بيانات الفندق مع سيناريوهات',
      actions: [
        IconButton(
          tooltip: 'تعديل معاملات السيناريو',
          icon: const Icon(Icons.tune),
          onPressed: () => _showScenarioEditor(context, scenarios),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(financeDataBundleProvider);
          ref.invalidate(paymentProfileProvider);
          ref.invalidate(forecastResultProvider);
          await ref.read(forecastResultProvider(_selectedScenarioKey).future);
        },
        child: forecastAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(message: '$e', onRetry: () {
            ref.invalidate(financeDataBundleProvider);
            ref.invalidate(forecastResultProvider);
          }),
          data: (result) => _buildBody(context, result, scenarios),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ForecastResult result,
    List<ScenarioParams> scenarios,
  ) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        // ── اختيار السيناريو ──────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Wrap(
              spacing: 6,
              children: [
                for (final s in scenarios)
                  ChoiceChip(
                    label: Text(
                        '${s.name} (${_pctText(s.revenueFactor)}٪ / ${_pctText(s.collectionFactor)}٪)'),
                    selected: s.key == _selectedScenarioKey,
                    onSelected: (_) =>
                        setState(() => _selectedScenarioKey = s.key),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // ── بطاقات الملخص ─────────────────────────────────────────
        _SummaryGrid(result: result),
        const SizedBox(height: 8),

        // ── مخطط الرصيد الختامي مقابل الحد الأدنى ─────────────────
        if (result.weeks.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'الرصيد الختامي المتوقع مقابل الحد الأدنى',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 170,
                    child: _BalanceChart(result: result),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),

        // ── الأسابيع الـ13 ─────────────────────────────────────────
        for (final w in result.weeks) ...[
          _WeekCard(week: w),
          const SizedBox(height: 6),
        ],

        // ── ملف التحصيل المستخرج من البيانات ─────────────────────
        _PaymentProfileCard(profile: result.paymentProfile),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'يبدأ النموذج أول يوم من الشهر القادم ليتطابق مع الدورة المالية. '
            'حد السيولة الأدنى ديناميكي: متوسط الخارج الأسبوعي × '
            '${result.coverageTargetWeeks} أسابيع. حدّث النموذج أسبوعياً '
            'بمراجعة الأسابيع الحمراء والصفراء أولًا.',
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ),
      ],
    );
  }

  String _pctText(double v) {
    final scaled = v * 100;
    return scaled.toStringAsFixed(
      scaled == scaled.roundToDouble() ? 0 : 1,
    );
  }

  // ── محرر معاملات السيناريو ──────────────────────────────────────
  Future<void> _showScenarioEditor(
    BuildContext context,
    List<ScenarioParams> scenarios,
  ) async {
    final controller = ref.read(scenarioSettingsProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'معاملات السيناريوهات',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'معامل الإيراد يضرب التدفق الداخل كلياً، ومعامل التحصيل '
                  'يضرب الجزء المرجّح والتقديري (المؤكد لا يتأثر).',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final s in scenarios) ...[
                  _ScenarioEditorTile(initial: s, onSave: controller.update),
                  const SizedBox(height: 8),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('استعادة الافتراضي'),
                  onPressed: () async {
                    await controller.reset();
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── بطاقات الملخص العلوي ────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.result});

  final ForecastResult result;

  @override
  Widget build(BuildContext context) {
    final worst = result.worstWeek;
    return Column(
      children: [
        Row(
          children: [
            _SummaryCard(
              title: 'رصيد البداية',
              value: _money(result.openingBalance),
              icon: Icons.account_balance_wallet,
              color: result.openingBalance >= 0
                  ? Colors.green
                  : Colors.red,
            ),
            const SizedBox(width: 8),
            _SummaryCard(
              title: 'الحد الأدنى للسيولة',
              value: _money(result.liquidityThreshold),
              icon: Icons.horizontal_rule,
              color: Colors.deepOrange,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _SummaryCard(
              title: 'الداخل / الخارج (13 أسبوعاً)',
              value:
                  '${_money(result.totalInflow)} ← ${_money(result.totalOutflow)}',
              icon: Icons.swap_vert,
              color: Colors.indigo,
              smallText: true,
            ),
            const SizedBox(width: 8),
            _SummaryCard(
              title: 'التمويل المطلوب',
              value: result.financingNeed > 0
                  ? _money(result.financingNeed)
                  : 'لا حاجة',
              icon: Icons.warning_amber_rounded,
              color: result.financingNeed > 0 ? Colors.red : Colors.green,
              subtitle: worst == null
                  ? null
                  : 'أدنى رصيد: ${_money(worst.closingBalance)} (أسبوع ${worst.index})',
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.smallText = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final bool smallText;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: smallText ? 13 : 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── مخطط الرصيد ─────────────────────────────────────────────────────

class _BalanceChart extends StatelessWidget {
  const _BalanceChart({required this.result});

  final ForecastResult result;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      FlSpot(0, result.openingBalance),
      for (final w in result.weeks) FlSpot(w.index.toDouble(), w.closingBalance),
    ];
    final allClosing = [result.openingBalance, ...spots.map((s) => s.y)];
    final maxY = allClosing.reduce((a, b) => a > b ? a : b) * 1.05;
    final minY = [result.liquidityThreshold, ...allClosing]
        .reduce((a, b) => a < b ? a : b) *
        0.95;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: result.liquidityThreshold,
              color: Colors.red,
              strokeWidth: 1.2,
              dashArray: [6, 4],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            barWidth: 2.2,
            color: Colors.indigo,
          ),
        ],
      ),
    );
  }
}

// ── بطاقة الأسبوع ───────────────────────────────────────────────────

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week});

  final WeeklyForecast week;

  @override
  Widget build(BuildContext context) {
    final statusColor = _colorOf(week.status);
    final fmt = (DateTime d) => '${d.day}/${d.month}';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: CircleAvatar(
            radius: 13,
            backgroundColor: statusColor.withValues(alpha: 0.15),
            child: Text(
              '${week.index}',
              style: TextStyle(fontSize: 11, color: statusColor),
            ),
          ),
          title: Text(
            'الأسبوع ${week.index}  (${fmt(week.start)} — ${fmt(week.end)})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'صافي: ${_money(week.netFlow)}  •  الرصيد: ${_money(week.closingBalance)}  •  تغطية: ${week.coverageWeeks.toStringAsFixed(1)} أسبوع',
            style: TextStyle(
                fontSize: 11, color: Colors.grey[600]),
          ),
          trailing: Icon(
            week.status == AlertLevel.danger
                ? Icons.error
                : week.status == AlertLevel.warning
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle,
            color: statusColor,
            size: 20,
          ),
          children: [
            _FlowRow(
              label: 'داخل مؤكد (نزلاء حاليون / دفعت عربون)',
              value: week.inflow.confirmed,
              color: Colors.green,
            ),
            _FlowRow(
              label: 'داخل مرجّح (حجوزات مؤكدة غير مدفوعة)',
              value: week.inflow.probable,
              color: Colors.orange,
            ),
            _FlowRow(
              label: 'داخل تقديري (ليالي غير محجوزة)',
              value: week.inflow.estimated,
              color: Colors.blueGrey,
            ),
            const Divider(height: 12),
            _FlowRow(label: 'إجمالي الداخل', value: week.inflow.total, color: Colors.indigo),
            const SizedBox(height: 4),
            _FlowRow(label: 'خارج — رواتب', value: week.outflow.salaries, color: Colors.red.shade300),
            _FlowRow(label: 'خارج — ديزل', value: week.outflow.diesel, color: Colors.red.shade300),
            _FlowRow(label: 'خارج — كهرباء ومياه', value: week.outflow.utilities, color: Colors.red.shade300),
            _FlowRow(label: 'خارج — صيانة', value: week.outflow.maintenance, color: Colors.red.shade300),
            _FlowRow(label: 'خارج — أخرى', value: week.outflow.other, color: Colors.red.shade300),
            _FlowRow(label: 'إجمالي الخارج', value: week.outflow.total, color: Colors.red),
            const Divider(height: 12),
            _TwoColRow(
              leftLabel: 'رصيد بداية',
              leftValue: _money(week.openingBalance),
              rightLabel: 'رصيد نهاية',
              rightValue: _money(week.closingBalance),
            ),
            _TwoColRow(
              leftLabel: 'الفائض عن الحد الأدنى',
              leftValue: _money(week.surplusOverThreshold),
              rightLabel: week.surplusOverThreshold < 0
                  ? 'احتياج تمويل: ${_money(week.financingNeed)}'
                  : 'وضع مستقر',
              rightValue: '',
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorOf(AlertLevel level) {
    switch (level) {
      case AlertLevel.good:
        return Colors.green;
      case AlertLevel.warning:
        return Colors.orange;
      case AlertLevel.danger:
        return Colors.red;
      case AlertLevel.unknown:
        return Colors.grey;
    }
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 11.5)),
          ),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoColRow extends StatelessWidget {
  const _TwoColRow({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
  });

  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$leftLabel: $leftValue',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          if (rightValue.isNotEmpty)
            Expanded(
              child: Text(
                '$rightLabel: $rightValue',
                style: const TextStyle(fontSize: 11.5),
                textAlign: TextAlign.left,
              ),
            )
          else
            Expanded(
              child: Text(
                rightLabel,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.left,
              ),
            ),
        ],
      ),
    );
  }
}

// ── ملف وسائل الدفع ─────────────────────────────────────────────────

class _PaymentProfileCard extends StatelessWidget {
  const _PaymentProfileCard({required this.profile});

  final PaymentProfile profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ملف التحصيل (من التاريخ الفعلي)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in profile.methods)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${m.method}: ${(m.share * 100).toStringAsFixed(0)}٪ — تأخر ${m.lagDays} يوم',
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'إشغال تاريخي: ${(profile.historicalOccupancy * 100).toStringAsFixed(0)}٪ — '
              'ADR تاريخي: ${_money(profile.historicalAdr)} — '
              'آخر ${profile.sampleDays} يوماً',
              style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── محرر سيناريو ────────────────────────────────────────────────────

class _ScenarioEditorTile extends StatefulWidget {
  const _ScenarioEditorTile({required this.initial, required this.onSave});

  final ScenarioParams initial;
  final Future<void> Function(ScenarioParams) onSave;

  @override
  State<_ScenarioEditorTile> createState() => _ScenarioEditorTileState();
}

class _ScenarioEditorTileState extends State<_ScenarioEditorTile> {
  late final TextEditingController _revenue =
      TextEditingController(text: (widget.initial.revenueFactor * 100).toStringAsFixed(0));
  late final TextEditingController _collection =
      TextEditingController(text: (widget.initial.collectionFactor * 100).toStringAsFixed(0));

  @override
  void dispose() {
    _revenue.dispose();
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            widget.initial.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _revenue,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'إيراد ٪',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _collection,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'تحصيل ٪',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.save_outlined, size: 20),
          onPressed: () {
            final r = (double.tryParse(_revenue.text.trim()) ?? 100) / 100;
            final c = (double.tryParse(_collection.text.trim()) ?? 100) / 100;
            unawaited(
              widget.onSave(
                widget.initial.copyWith(
                  revenueFactor: r.clamp(0.1, 2.0),
                  collectionFactor: c.clamp(0.1, 2.0),
                ),
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم حفظ معاملات «${widget.initial.name}»')),
            );
          },
        ),
      ],
    );
  }
}

// ── عرض الخطأ ───────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(
              'تعذر بناء النموذج',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}

// ── تنسيق المبالغ ───────────────────────────────────────────────────

String _money(double v) => CurrencyFormatter.formatCurrency(v);
