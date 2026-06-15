import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/database_fixer.dart';
import '../../services/local_db.dart';

class DatabaseFixerScreen extends ConsumerStatefulWidget {
  const DatabaseFixerScreen({super.key});

  @override
  State<DatabaseFixerScreen> createState() => _DatabaseFixerScreenState();
}

class _DatabaseFixerScreenState extends ConsumerState<DatabaseFixerScreen> {
  ValidationReport? _validationReport;
  FixResult? _fixResult;
  bool _isLoading = false;
  bool _isFixing = false;

  late final DatabaseFixer _fixer;

  @override
  void initState() {
    super.initState();
    _fixer = DatabaseFixer(DatabaseManager.instance);
    _runValidation();
  }

  Future<void> _runValidation() async {
    setState(() {
      _isLoading = true;
      _validationReport = null;
    });

    try {
      final report = await _fixer.validate();
      setState(() {
        _validationReport = report;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في التحقق: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runFix() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الإصلاح'),
        content: const Text(
          'سيتم إصلاح البيانات الفاسدة في قاعدة البيانات.\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<bool>(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop<bool>(context, true),
            child: const Text('إصلاح'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isFixing = true;
      _fixResult = null;
    });

    try {
      final result = await _fixer.fixAllIssues();
      setState(() {
        _fixResult = result;
      });

      if (result.success && result.totalFixed > 0) {
        // إعادة التحقق بعد الإصلاح
        await _runValidation();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إصلاح ${result.totalFixed} مشكلة ✓'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result.success && result.totalFixed == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد مشاكل للإصلاح')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الإصلاح: $e')));
      }
    } finally {
      setState(() {
        _isFixing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إصلاح قاعدة البيانات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _runValidation,
            tooltip: 'إعادة التحقق',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  if (_validationReport != null) ...[
                    _buildValidationCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_fixResult != null) ...[
                    _buildFixResultCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_validationReport?.hasIssues ?? false) _buildFixButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'معلومات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'هذه الأداة تقوم بالتحقق من صحة البيانات في قاعدة البيانات وإصلاح المشاكل التالية:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildInfoItem('• serverId تحتوي على UUID بدلاً من أرقام'),
            _buildInfoItem('• مدفوعات تشير لحجوزات غير موجودة'),
            _buildInfoItem('• مصروفات تشير لبيانات غير موجودة'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      ),
    );
  }

  Widget _buildValidationCard() {
    final report = _validationReport!;

    return Card(
      color: report.hasIssues ? Colors.orange[50] : Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.hasIssues ? Icons.warning : Icons.check_circle,
                  color: report.hasIssues ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  'نتيجة التحقق',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: report.hasIssues
                        ? Colors.orange[900]
                        : Colors.green[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.error != null)
              Text(
                'خطأ: ${report.error}',
                style: const TextStyle(color: Colors.red),
              )
            else if (!report.hasIssues)
              const Text(
                '✓ قاعدة البيانات صحيحة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              )
            else ...[
              _buildIssueItem(
                'serverId فاسدة',
                report.invalidServerIds,
                Icons.key,
              ),
              _buildIssueItem(
                'مدفوعات يتيمة',
                report.orphanPayments,
                Icons.payment,
              ),
              _buildIssueItem(
                'مصروفات يتيمة',
                report.orphanExpenses,
                Icons.money_off,
              ),
              const Divider(height: 24),
              Text(
                'الإجمالي: ${report.totalIssues} مشكلة',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIssueItem(String label, int count, IconData icon) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 14)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.orange[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixResultCard() {
    final result = _fixResult!;

    return Card(
      color: result.success ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.success ? Icons.check_circle : Icons.error,
                  color: result.success ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'نتيجة الإصلاح',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: result.success ? Colors.green[900] : Colors.red[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result.error != null)
              Text(
                'خطأ: ${result.error}',
                style: const TextStyle(color: Colors.red),
              )
            else if (result.success) ...[
              _buildFixItem('serverId', result.serverIdFixed),
              _buildFixItem('مدفوعات يتيمة', result.orphanPaymentsFixed),
              _buildFixItem('مصروفات يتيمة', result.orphanExpensesFixed),
              const Divider(height: 24),
              Text(
                '✓ تم إصلاح ${result.totalFixed} مشكلة',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFixItem(String label, int count) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.build, size: 20, color: Colors.green),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 14)),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.green[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isFixing ? null : _runFix,
        icon: _isFixing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.build),
        label: Text(_isFixing ? 'جاري الإصلاح...' : 'إصلاح المشاكل'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}
