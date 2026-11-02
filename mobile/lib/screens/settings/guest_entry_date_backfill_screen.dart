import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart' as ap;
import '../../services/guest_entry_date_backfill_service.dart';

class GuestEntryDateBackfillScreen extends ConsumerStatefulWidget {
  const GuestEntryDateBackfillScreen({super.key});

  @override
  ConsumerState<GuestEntryDateBackfillScreen> createState() =>
      _GuestEntryDateBackfillScreenState();
}

class _GuestEntryDateBackfillScreenState
    extends ConsumerState<GuestEntryDateBackfillScreen> {
  final ValueNotifier<_BackfillViewState> _viewState = ValueNotifier(
    const _BackfillViewState(),
  );

  @override
  void dispose() {
    _viewState.dispose();
    super.dispose();
  }

  Future<void> _startBackfill() async {
    if (_viewState.value.running) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تعبئة entryDate'),
        content: const Text(
          'سيتم فحص جميع مستندات guest_infos في Appwrite Cloud على صفحات. '
          r'سيُملأ entryDate الفارغ فقط بتاريخ $createdAt بصيغة yyyy-mm-dd. '
          'لن تُستبدل التواريخ الموجودة، وستُستثنى السجلات المحذوفة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ابدأ التعبئة'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    _viewState.value = const _BackfillViewState(running: true);
    try {
      final result =
          await GuestEntryDateBackfillService(
            ref.read(ap.appwriteServiceProvider),
          ).fillMissingEntryDates(
            onProgress: (progress) {
              if (!mounted) {
                return;
              }
              _viewState.value = _BackfillViewState(
                running: true,
                progress: progress,
              );
            },
          );
      if (!mounted) {
        return;
      }
      _viewState.value = _BackfillViewState(progress: result, result: result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _viewState.value = _BackfillViewState(
        progress: _viewState.value.progress,
        errorMessage: error.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تعبئة entryDate القديمة',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_available, color: Colors.deepPurple),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سجلات الضيوف على Appwrite Cloud',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    r'يُستخدم تاريخ إنشاء المستند الأصلي $createdAt، ويُحفظ في entryDate بصيغة yyyy-mm-dd.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'تُحدّث هذه الأداة الحقل الناقص وحده، ولا تستبدل أي تاريخ موجود أو تغيّر بقية الحقول. السجلات المحذوفة تُستثنى.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'تعمل على صفحات صغيرة ويمكن إعادة تشغيلها بأمان إذا انقطع الاتصال؛ اترك التطبيق مفتوحاً حتى ظهور النتيجة.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<_BackfillViewState>(
            valueListenable: _viewState,
            builder: (context, state, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.running) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    _buildCountsCard(state.progress, running: true),
                    const SizedBox(height: 16),
                  ],
                  if (state.result != null) ...[
                    _buildResultCard(state.result!),
                    const SizedBox(height: 16),
                  ],
                  if (state.errorMessage != null) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'تعذّر إكمال العملية: ${state.errorMessage}\n'
                          'يمكن إعادة تشغيلها؛ ستتخطى القيم التي عُبئت بالفعل.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: state.running ? null : _startBackfill,
                    icon: state.running
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(
                      state.running
                          ? 'جاري فحص السجلات وتعبئتها...'
                          : state.result == null
                          ? 'بدء تعبئة السجلات'
                          : 'إعادة فحص السجلات',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCountsCard(
    GuestEntryDateBackfillProgress progress, {
    required bool running,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'تم فحص ${progress.scanned} مستنداً، وتعبئة ${progress.updated}.'
          '${running ? '\nتستمر العملية تلقائياً على الصفحة التالية.' : ''}',
        ),
      ),
    );
  }

  Widget _buildResultCard(GuestEntryDateBackfillResult result) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'اكتملت العملية',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('إجمالي المستندات المفحوصة: ${result.scanned}'),
            Text('تمت تعبئة entryDate: ${result.updated}'),
            Text('كان entryDate موجوداً: ${result.alreadyHadEntryDate}'),
            Text('سجلات محذوفة تم تجاوزها: ${result.deletedSkipped}'),
            Text('مستندات بلا \$createdAt صالح: ${result.missingCreatedAt}'),
            if (result.updated == 0 && result.missingCreatedAt == 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('لا توجد سجلات نشطة تحتاج إلى تعبئة.'),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackfillViewState {
  const _BackfillViewState({
    this.running = false,
    this.progress = const GuestEntryDateBackfillProgress(),
    this.result,
    this.errorMessage,
  });

  final bool running;
  final GuestEntryDateBackfillProgress progress;
  final GuestEntryDateBackfillResult? result;
  final String? errorMessage;
}
