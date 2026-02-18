// ignore_for_file: avoid_print, use_build_context_synchronously

/// مثال على استخدام نظام قائمة الانتظار للعمليات دون اتصال
///
/// هذا الملف يوضح كيفية استخدام OfflineQueueManager في سيناريوهات مختلفة

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/offline_queue_provider.dart';
import '../../widgets/offline_queue_widget.dart';
import 'offline_queue_manager.dart';
import 'offline_queue_processor.dart';

// ============================================================
// المثال 1: إنشاء حجز جديد مع دفع
// ============================================================

class BookingCreationExample {
  Future<void> createBookingWithPayment(
    BuildContext context,
    Map<String, dynamic> bookingData,
    Map<String, dynamic> paymentData,
  ) async {
    final manager = OfflineQueueManager.instance;

    // إضافة الحجز بأولوية عالية
    final bookingId = await manager.enqueue(
      entity: 'bookings',
      operation: OfflineOperationType.create,
      payload: bookingData,
      priority: OfflinePriority.high,
    );

    print('✅ تمت إضافة الحجز للقائمة: $bookingId');

    // إضافة الدفع مع نفس UUID للتجميع
    final paymentId = await manager.enqueue(
      entity: 'payments',
      operation: OfflineOperationType.create,
      payload: {
        ...paymentData,
        'bookingRef': bookingId,
      },
      priority: OfflinePriority.high,
      groupId: bookingId, // تجميع مع الحجز
    );

    print('✅ تمت إضافة الدفع للقائمة: $paymentId');

    // إظهار رسالة للمستخدم
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('سيتم حفظ الحجز والدفع عند عودة الاتصال'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

// ============================================================
// المثال 2: تحديثات متعددة للغرف
// ============================================================

class BatchRoomUpdateExample {
  Future<void> updateMultipleRooms(
    List<Map<String, dynamic>> roomUpdates,
  ) async {
    final manager = OfflineQueueManager.instance;

    // إنشاء عناصر دفعية
    final batchItems = roomUpdates.map((room) {
      return OfflineQueueBatchItem(
        entity: 'rooms',
        operation: OfflineOperationType.update,
        payload: room,
        priority: OfflinePriority.normal,
        uuid: room['uuid'] as String,
      );
    }).toList();

    // إضافة كمجموعة واحدة
    final batchIds = await manager.enqueueBatch(batchItems);

    print('✅ تمت إضافة ${batchIds.length} تحديث للغرف');

    // انتظار اكتمال المجموعة (اختياري)
    await manager.waitForGroup(
      batchIds.first,
      timeout: const Duration(minutes: 2),
    );

    print('✅ اكتملت جميع تحديثات الغرف');
  }
}

// ============================================================
// المثال 3: معالج مخصص لرفع الملفات
// ============================================================

class CustomFileUploadHandler {
  void registerFileUploadHandler() {
    final processor = OfflineQueueProcessor.instance;

    processor.registerHandler(
      OfflineOperationType.upload,
      (item) async {
        try {
          final filePath = item.payload['filePath'] as String?;
          final fileType = item.payload['fileType'] as String? ?? 'image';

          if (filePath == null) {
            return OfflineQueueResult.failure(
              'مسار الملف غير موجود',
              shouldRetry: false,
            );
          }

          print('📤 رفع الملف: $filePath');

          // محاكاة رفع الملف
          await Future.delayed(const Duration(seconds: 2));

          // تحقق من حجم الملف
          final fileSize = item.payload['size'] as int? ?? 0;
          if (fileSize > 10 * 1024 * 1024) {
            // > 10MB
            return OfflineQueueResult.failure(
              'حجم الملف كبير جداً',
              shouldRetry: false,
            );
          }

          print('✅ تم رفع الملف بنجاح');
          return OfflineQueueResult.success({'url': 'https://example.com/file'});
        } catch (e) {
          return OfflineQueueResult.failure(
            'فشل في رفع الملف: $e',
            shouldRetry: true,
          );
        }
      },
    );
  }
}

// ============================================================
// المثال 4: شاشة مع عرض حالة القائمة
// ============================================================

class OfflineAwareScreen extends ConsumerWidget {
  const OfflineAwareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(offlineQueueStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الحجوزات'),
        actions: [
          // عرض حالة القائمة في شريط التطبيق
          const OfflineQueueWidget(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // شريط إشعار عند وجود عمليات معلقة
          const OfflineQueueBanner(),

          Expanded(
            child: statusAsync.when(
              data: (status) {
                if (!status.isOnline && status.pendingCount > 0) {
                  return _buildOfflineMode(context, status);
                }
                return _buildNormalMode(context);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('خطأ: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: const OfflineQueueFab(),
    );
  }

  Widget _buildOfflineMode(BuildContext context, OfflineQueueStatus status) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.offline_bolt, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          Text(
            'وضع عدم الاتصال',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${status.pendingCount} عملية في قائمة الانتظار',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showPendingItems(context),
            icon: const Icon(Icons.list),
            label: const Text('عرض العمليات المعلقة'),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalMode(BuildContext context) {
    return const Center(
      child: Text('المحتوى العادي هنا'),
    );
  }

  void _showPendingItems(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const OfflineQueueDetailsSheet(),
    );
  }
}

// ============================================================
// المثال 5: مزامنة يدوية مع التقدم
// ============================================================

class ManualSyncExample extends StatefulWidget {
  const ManualSyncExample({super.key});

  @override
  State<ManualSyncExample> createState() => _ManualSyncExampleState();
}

class _ManualSyncExampleState extends State<ManualSyncExample> {
  bool _isSyncing = false;
  String _status = '';

  Future<void> _performManualSync() async {
    setState(() {
      _isSyncing = true;
      _status = 'جاري المزامنة...';
    });

    final manager = OfflineQueueManager.instance;

    try {
      // الحصول على الإحصائيات قبل المزامنة
      final beforeStats = await manager.getStats();
      print('قبل المزامنة: ${beforeStats.pendingCount} عملية');

      // بدء المعالجة
      await manager.processQueue();

      // انتظار قصير للمعالجة
      await Future.delayed(const Duration(seconds: 2));

      // الحصول على الإحصائيات بعد المزامنة
      final afterStats = await manager.getStats();
      print('بعد المزامنة: ${afterStats.pendingCount} عملية');

      setState(() {
        _status = 'تمت مزامنة ${beforeStats.pendingCount - afterStats.pendingCount} عملية';
      });

      if (afterStats.failedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${afterStats.failedCount} عملية فشلت'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              onPressed: () => manager.retryFailed(),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = 'فشلت المزامنة: $e';
      });
    } finally {
      setState(() {
        _isSyncing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _isSyncing ? null : _performManualSync,
          icon: _isSyncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(_isSyncing ? 'جاري المزامنة...' : 'مزامنة الآن'),
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_status),
        ],
      ],
    );
  }
}

// ============================================================
// المثال 6: تنظيف دوري للعمليات المكتملة
// ============================================================

class QueueMaintenanceExample {
  Future<void> performMaintenance() async {
    final manager = OfflineQueueManager.instance;

    // مسح العمليات المكتملة الأقدم من 7 أيام
    final clearedCount = await manager.clearCompleted(
      olderThan: const Duration(days: 7),
    );
    print('🧹 تم مسح $clearedCount عملية مكتملة قديمة');

    // محاولة إعادة معالجة العمليات الفاشلة
    await manager.retryFailed();

    // الحصول على إحصائيات محدثة
    final stats = await manager.getStats();
    print('📊 حالة القائمة: ${stats.pendingCount} معلقة, ${stats.failedCount} فاشلة');
  }
}

// ============================================================
// المثال 7: التعامل مع أخطاء محددة
// ============================================================

class ErrorHandlingExample {
  void registerSmartHandler() {
    final processor = OfflineQueueProcessor.instance;

    processor.registerHandler(
      OfflineOperationType.create,
      (item) async {
        try {
          print('معالجة: ${item.entity} - ${item.uuid}');

          // محاكاة معالجة
          await Future.delayed(const Duration(milliseconds: 500));

          // كشف أخطاء محددة
          if (item.payload.containsKey('invalidField')) {
            // خطأ دائم - لا يجب إعادة المحاولة
            return OfflineQueueResult.failure(
              'حقل غير صالح: ${item.payload['invalidField']}',
              shouldRetry: false,
            );
          }

          if (item.attempts >= 3) {
            // تجاوز عدد المحاولات
            return OfflineQueueResult.failure(
              'تجاوز عدد المحاولات',
              shouldRetry: false,
            );
          }

          // محاكاة خطأ مؤقت (مثل انقطاع الاتصال)
          if (item.payload['simulateError'] == true) {
            return OfflineQueueResult.failure(
              'خطأ مؤقت في الشبكة',
              shouldRetry: true,
            );
          }

          return OfflineQueueResult.success({'id': 'new-id-123'});
        } catch (e) {
          return OfflineQueueResult.failure(
            'خطأ غير متوقع: $e',
            shouldRetry: true,
          );
        }
      },
    );
  }
}

// ============================================================
// المثال 8: استخدام مع Riverpod (نموذج كامل)
// ============================================================

class CompleteExample extends ConsumerWidget {
  const CompleteExample({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // مراقبة جميع حالات القائمة
    final manager = ref.watch(offlineQueueManagerProvider);
    final statsAsync = ref.watch(offlineQueueStatsProvider);
    final pendingCount = ref.watch(offlineQueuePendingCountProvider);
    final isProcessing = ref.watch(offlineQueueProcessingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام قائمة الانتظار'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بطاقة الحالة العامة
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: statsAsync.when(
                  data: (stats) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'حالة القائمة',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _buildStatRow('إجمالي العمليات', stats.totalCount),
                      _buildStatRow('معلقة', stats.pendingCount, Colors.orange),
                      _buildStatRow('فاشلة', stats.failedCount, Colors.red),
                      _buildStatRow('مكتملة', stats.completedCount, Colors.green),
                      const Divider(height: 24),
                      _buildStatRow(
                        'الاتصال',
                        stats.isOnline ? 'متصل' : 'غير متصل',
                        stats.isOnline ? Colors.green : Colors.grey,
                      ),
                    ],
                  ),
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (err, _) => Text('خطأ: $err'),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // أزرار التحكم
            Text(
              'أدوات التحكم',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _addSampleItem(manager),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة عملية'),
                ),
                ElevatedButton.icon(
                  onPressed: () => manager.processQueue(),
                  icon: const Icon(Icons.sync),
                  label: const Text('مزامنة'),
                ),
                ElevatedButton.icon(
                  onPressed: () => manager.retryFailed(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
                ElevatedButton.icon(
                  onPressed: () => manager.clearCompleted(),
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('تنظيف'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // عرض العدد المعلق
            pendingCount.when(
              data: (count) => Text(
                'العمليات المعلقة: $count',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              loading: () => const Text('جاري التحميل...'),
              error: (err, _) => Text('خطأ: $err'),
            ),

            const SizedBox(height: 8),

            // عرض حالة المعالجة
            isProcessing.when(
              data: (processing) => processing
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('جاري معالجة العمليات...'),
                      ],
                    )
                  : const Text('لا توجد عمليات قيد التنفيذ'),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, dynamic value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addSampleItem(OfflineQueueManager manager) async {
    await manager.enqueue(
      entity: 'sample',
      operation: OfflineOperationType.create,
      payload: {
        'name': 'عنصر تجريبي',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}

// ============================================================
// ملخص الاستخدام
// ============================================================

/*
ملخص سريع:

1. التهيئة (مرة واحدة في main):
   await container.read(offlineQueueInitProvider.future);

2. إضافة عملية:
   await manager.enqueue(...);

3. مراقبة الحالة:
   final status = ref.watch(offlineQueueStatusProvider);

4. عرض في الواجهة:
   - OfflineQueueWidget() - عرض مصغر
   - OfflineQueueFab() - زر عائم
   - OfflineQueueBanner() - شريط إشعار
   - OfflineQueueDetailsSheet() - شاشة تفاصيل

5. مزامنة يدوية:
   await manager.processQueue();

6. صيانة:
   await manager.clearCompleted();
   await manager.retryFailed();
*/

// مثال: كيفية تشغيل المثال الكامل
void runExample() {
  // انسخ هذا الملف واستورد المكتبات اللازمة
  // ثم استخدم أي من الأمثلة أعلاه
}
