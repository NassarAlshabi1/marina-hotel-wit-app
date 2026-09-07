import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/appwrite_providers.dart';

class SyncActionButton extends ConsumerStatefulWidget {
  const SyncActionButton({super.key});

  @override
  ConsumerState<SyncActionButton> createState() => _SyncActionButtonState();
}

class _SyncActionButtonState extends ConsumerState<SyncActionButton> {
  bool _isSyncing = false;
  String? _lastError;

  Future<void> _runSync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _lastError = null;
    });
    try {
      final result = await ref.read(appwriteSyncManagerProvider).sync();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (result.isSuccess) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.recordsPushed == 0 && result.recordsPulled == 0
                  ? 'لا توجد تغييرات جديدة'
                  : 'تمت المزامنة: رفع ${result.recordsPushed} / سحب ${result.recordsPulled}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() => _lastError = result.errorMessage);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'فشل في المزامنة: ${result.errorMessage ?? 'سبب غير معروف'}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastError = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل في المزامنة: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      } else {
        _isSyncing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _lastError != null;

    final tooltip = _isSyncing
        ? 'جاري المزامنة...'
        : hasError
        ? 'حدث خطأ في آخر مزامنة، اضغط لإعادة المحاولة'
        : 'مزامنة مع Cloudflare';

    return IconButton(
      onPressed: _isSyncing ? null : _runSync,
      tooltip: tooltip,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _isSyncing
            ? const SizedBox(
                key: ValueKey('syncing'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.sync,
                key: ValueKey(hasError ? 'error' : 'idle'),
                color: hasError ? Colors.redAccent : null,
              ),
      ),
    );
  }
}
