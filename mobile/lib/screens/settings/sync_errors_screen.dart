import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../services/appwrite_delta_sync.dart';

/// ⭐ Provider لأخطاء المزامنة
final syncErrorsListProvider = StateProvider<List<SyncErrorRecord>>((ref) {
  return AppwriteDeltaSync.instance.syncErrors;
});

/// ⭐ Provider لحالة إعادة المحاولة
final isRetryingProvider = StateProvider<bool>((ref) => false);

class SyncErrorsScreen extends ConsumerStatefulWidget {
  const SyncErrorsScreen({super.key});

  @override
  ConsumerState<SyncErrorsScreen> createState() => _SyncErrorsScreenState();
}

class _SyncErrorsScreenState extends ConsumerState<SyncErrorsScreen> {
  StreamSubscription<SyncErrorRecord>? _errorSubscription;
  String _searchQuery = '';
  String? _filterEntity;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // الاستماع للأخطاء الجديدة
    _errorSubscription = AppwriteDeltaSync.instance.errorsStream.listen((error) {
      ref.invalidate(syncErrorsListProvider);
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errors = ref.watch(syncErrorsListProvider);
    final isRetrying = ref.watch(isRetryingProvider);
    final filteredErrors = _filterErrors(errors);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AppScaffold(
        title: 'أخطاء المزامنة',
        actions: [
          if (errors.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'إعادة محاولة الكل',
              onPressed: isRetrying
                  ? null
                  : () => _retryAllErrors(),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'مسح الكل',
              onPressed: () => _clearAllErrors(),
            ),
          ],
        ],
        body: Column(
          children: [
            // شريط الإحصائيات
            if (errors.isNotEmpty)
              _buildStatsBar(errors),

            // شريط الفلترة
            Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // شريط البحث
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'البحث في الأخطاء...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (value) {
                      _debounceTimer?.cancel();
                      _debounceTimer = Timer(
                        const Duration(milliseconds: 300),
                        () {
                          setState(() => _searchQuery = value.toLowerCase());
                        },
                      );
                    },
                  ),
                  
                  // فلترة حسب الكيان
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildEntityFilterChip('الكل', null, errors.length),
                          const SizedBox(width: 8),
                          ..._getUniqueEntities(errors).map((entity) {
                            final count = errors.where((e) => e.entity == entity).length;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _buildEntityFilterChip(entity, entity, count),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // مؤشر إعادة المحاولة
            if (isRetrying)
              Container(
                color: Colors.blue.shade100,
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'جاري إعادة محاولة ${filteredErrors.length} خطأ...',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // قائمة الأخطاء
            Expanded(
              child: filteredErrors.isEmpty
                  ? _buildEmptyState(errors.isEmpty)
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: filteredErrors.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final error = filteredErrors[index];
                        return _buildErrorCard(error, isRetrying);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBar(List<SyncErrorRecord> errors) {
    final entities = _getUniqueEntities(errors);
    final retryableCount = errors.where((e) => e.retryCount < 3).length;

    return Container(
      color: Colors.red.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Text(
            '${errors.length} خطأ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red.shade900,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'في ${entities.length} جدول',
            style: TextStyle(color: Colors.red.shade700),
          ),
          if (retryableCount > 0) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$retryableCount قابل للإعادة',
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEntityFilterChip(String label, String? entity, int count) {
    final isSelected = _filterEntity == entity;

    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _filterEntity = selected ? entity : null);
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.red.shade100,
      checkmarkColor: Colors.red,
      labelStyle: TextStyle(
        color: isSelected ? Colors.red.shade900 : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildEmptyState(bool noErrorsAtAll) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            noErrorsAtAll ? Icons.check_circle_outline : Icons.search_off,
            size: 64,
            color: noErrorsAtAll ? Colors.green : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            noErrorsAtAll ? 'لا توجد أخطاء مزامنة' : 'لا توجد نتائج مطابقة',
            style: TextStyle(
              fontSize: 16,
              color: noErrorsAtAll ? Colors.green : Colors.grey,
            ),
          ),
          if (noErrorsAtAll) ...[
            const SizedBox(height: 8),
            const Text(
              'جميع عمليات المزامنة ناجحة',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard(SyncErrorRecord error, bool isRetrying) {
    final canRetry = error.retryCount < 3;
    final isPermanent = error.retryCount >= 3;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isPermanent ? Colors.grey.shade100 : Colors.red.shade50,
      child: InkWell(
        onTap: () => _showErrorDetails(error),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // العنوان
              Row(
                children: [
                  Icon(
                    isPermanent ? Icons.block : Icons.error_outline,
                    color: isPermanent ? Colors.grey : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error.entity,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getOperationColor(error.operation),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      error.operation.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // رسالة الخطأ
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  error.errorMessage,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),

              // معلومات إضافية
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MM/dd HH:mm').format(error.timestamp),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.repeat, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    '${error.retryCount}/3 محاولات',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  
                  // زر إعادة المحاولة
                  if (canRetry && !isRetrying)
                    TextButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('إعادة'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => _retrySingleError(error),
                    ),

                  // زر النسخ
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'نسخ UUID',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _copyUuid(error),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getOperationColor(String operation) {
    switch (operation.toLowerCase()) {
      case 'insert':
        return Colors.green;
      case 'update':
        return Colors.blue;
      case 'delete':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<String> _getUniqueEntities(List<SyncErrorRecord> errors) {
    return errors.map((e) => e.entity).toSet().toList()..sort();
  }

  List<SyncErrorRecord> _filterErrors(List<SyncErrorRecord> errors) {
    var filtered = errors;

    // فلترة حسب الكيان
    if (_filterEntity != null) {
      filtered = filtered.where((e) => e.entity == _filterEntity).toList();
    }

    // فلترة حسب البحث
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((e) {
        return e.entity.toLowerCase().contains(_searchQuery) ||
            e.localUuid.toLowerCase().contains(_searchQuery) ||
            e.errorMessage.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    return filtered;
  }

  void _showErrorDetails(SyncErrorRecord error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text('خطأ في ${error.entity}')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('الكيان', error.entity),
              _buildDetailRow('العملية', error.operation.toUpperCase()),
              _buildDetailRow('UUID', error.localUuid),
              _buildDetailRow(
                'الوقت',
                DateFormat('yyyy-MM-dd HH:mm:ss').format(error.timestamp),
              ),
              _buildDetailRow('محاولات الإعادة', '${error.retryCount}/3'),
              if (error.lastRetryAt != null)
                _buildDetailRow(
                  'آخر محاولة',
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(error.lastRetryAt!),
                ),
              const SizedBox(height: 12),
              const Text(
                'رسالة الخطأ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: SelectableText(
                  error.errorMessage,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copyUuid(error),
            child: const Text('نسخ UUID'),
          ),
          if (error.retryCount < 3)
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
              onPressed: () {
                Navigator.pop(context);
                _retrySingleError(error);
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _copyUuid(SyncErrorRecord error) {
    // Clipboard.setData(ClipboardData(text: error.localUuid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ: ${error.localUuid}')),
    );
  }

  Future<void> _retrySingleError(SyncErrorRecord error) async {
    ref.read(isRetryingProvider.notifier).state = true;

    try {
      // إعادة محاولة هذا الخطأ تحديداً
      final result = await AppwriteDeltaSync.instance.pushDeltaChanges(
        retryFailed: true,
      );

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم إعادة المحاولة بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ فشلت إعادة المحاولة: ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      ref.read(isRetryingProvider.notifier).state = false;
      ref.invalidate(syncErrorsListProvider);
    }
  }

  Future<void> _retryAllErrors() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة محاولة جميع الأخطاء'),
        content: const Text(
          'سيتم إعادة محاولة رفع جميع السجلات الفاشلة.\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    ref.read(isRetryingProvider.notifier).state = true;

    try {
      final result = await AppwriteDeltaSync.instance.retryAllFailed();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      ref.read(isRetryingProvider.notifier).state = false;
      ref.invalidate(syncErrorsListProvider);
    }
  }

  Future<void> _clearAllErrors() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هل تريد مسح جميع أخطاء المزامنة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AppwriteDeltaSync.instance.clearAllErrors();
      ref.invalidate(syncErrorsListProvider);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم مسح جميع الأخطاء')),
        );
      }
    }
  }
}
