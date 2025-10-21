import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../components/app_scaffold.dart';
import '../../services/drive_backup_service.dart';
import '../../services/local_db.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';

class SettingsMaintenanceScreen extends ConsumerStatefulWidget {
  const SettingsMaintenanceScreen({super.key});

  @override
  ConsumerState<SettingsMaintenanceScreen> createState() => _SettingsMaintenanceScreenState();
}

class _SettingsMaintenanceScreenState extends ConsumerState<SettingsMaintenanceScreen> {
  bool _loadingInfo = true;
  bool _syncInProgress = false;
  _MaintenanceInfo _info = _MaintenanceInfo.empty();
  StreamSubscription<SyncStatus>? _syncSub;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    final syncService = ref.read(syncServiceProvider);
    _syncSub = syncService.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _syncInProgress = status == SyncStatus.pushing || status == SyncStatus.pulling;
      });
      if (status == SyncStatus.idle) {
        _loadInfo();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    setState(() => _loadingInfo = true);
    final info = await _MaintenanceInfo.collect(ref.read(databaseProvider));
    if (!mounted) return;
    setState(() {
      _info = info;
      _loadingInfo = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'صيانة النظام',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info, color: Colors.blue, size: 24),
                      const SizedBox(width: 8),
                      Text('معلومات النظام', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (_syncInProgress)
                        const Chip(avatar: Icon(Icons.sync, size: 16), label: Text('جارٍ المزامنة'))
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loadingInfo)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else
                    Column(
                      children: [
                        _buildInfoRow('إصدار التطبيق', '1.2.0+3'),
                        _buildInfoRow('آخر مزامنة', _info.formattedLastSync),
                        _buildInfoRow('مساحة قاعدة البيانات', _info.formattedStorage),
                        _buildInfoRow('الغرف', _info.rooms.toString()),
                        _buildInfoRow('الحجوزات', _info.bookings.toString()),
                        _buildInfoRow('الموظفون', _info.employees.toString()),
                        _buildInfoRow('المصروفات', _info.expenses.toString()),
                        _buildInfoRow('المدفوعات', _info.payments.toString()),
                        _buildInfoRow('ملاحظات الحجوزات', _info.notes.toString()),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('أدوات الصيانة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildMaintenanceCard(
            'تنظيف البيانات المؤقتة',
            'حذف السجلات المحذوفة نهائياً وتنفيذ VACUUM',
            Icons.cleaning_services,
            Colors.blue,
            () => _showCleanupDialog(context),
          ),
          _buildMaintenanceCard(
            'فحص قاعدة البيانات',
            'تشغيل PRAGMA quick_check والتحقق من سلامة الجداول',
            Icons.storage,
            Colors.green,
            () => _showDatabaseCheckDialog(context),
          ),
          _buildMaintenanceCard(
            'إعادة تعيين المزامنة',
            'مسح بيانات التزامن وإعادة تشغيل الخدمة',
            Icons.sync_problem,
            Colors.orange,
            () => _showResetSyncDialog(context),
          ),
          _buildMaintenanceCard(
            'تصدير البيانات',
            'إنشاء نسخة احتياطية كملف مضغوط محلي',
            Icons.download,
            Colors.purple,
            () => _showExportDialog(context),
          ),
          _buildMaintenanceCard(
            'استيراد البيانات',
            'استعادة البيانات من ملف نسخة احتياطية',
            Icons.upload,
            Colors.indigo,
            () => _showImportDialog(context),
          ),
          const SizedBox(height: 16),
          Text(
            'أدوات متقدمة',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.red),
          ),
          const SizedBox(height: 12),
          _buildMaintenanceCard(
            'إعادة تشغيل الخدمات',
            'إعادة تهيئة المزودات وإعادة تحميل البيانات',
            Icons.restart_alt,
            Colors.red,
            () => _showRestartDialog(context),
          ),
          _buildMaintenanceCard(
            'إعادة تعيين التطبيق',
            'حذف جميع البيانات المحلية وتهيئة قواعد البيانات',
            Icons.settings_backup_restore,
            Colors.red,
            () => _showResetAppDialog(context),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red),
                    SizedBox(width: 8),
                    Text('تحذير مهم', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ],
                ),
                SizedBox(height: 8),
                Text('استخدام الأدوات المتقدمة قد يؤدي إلى فقد البيانات. تأكد من وجود نسخة احتياطية محدثة قبل المتابعة.', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runTask(BuildContext context, {
    required String progressMessage,
    required Future<String> Function() action,
  }) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(message: progressMessage),
    );
    try {
      final result = await action();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack(result);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('حدث خطأ: $e', isError: true);
    } finally {
      await _loadInfo();
    }
  }

  void _showCleanupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تنظيف البيانات المؤقتة'),
          content: const Text('سيتم حذف العناصر المحذوفة نهائياً وتفريغ المخزن المؤقت. هل ترغب بالمتابعة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _runTask(context, progressMessage: 'جاري تنظيف البيانات...', action: _performCleanup);
              },
              child: const Text('تنظيف'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDatabaseCheckDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('فحص قاعدة البيانات'),
          content: const Text('سيتم تشغيل فحص سريع لسلامة قاعدة البيانات. قد يستغرق ذلك بضع ثوانٍ.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _runTask(context, progressMessage: 'جاري فحص قاعدة البيانات...', action: _performDatabaseCheck);
              },
              child: const Text('بدء الفحص'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعادة تعيين المزامنة'),
          content: const Text('سيتم إعادة تعيين حالة المزامنة ومسح قائمة الانتظار ثم بدء مزامنة جديدة.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _runTask(context, progressMessage: 'جاري إعادة ضبط المزامنة...', action: _resetSync);
              },
              child: const Text('إعادة التعيين'),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تصدير البيانات'),
          content: const Text('سيتم إنشاء ملف نسخة احتياطية مضغوط في مجلد التخزين المحدد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _runTask(context, progressMessage: 'جاري إنشاء النسخة الاحتياطية...', action: _exportData);
              },
              child: const Text('تصدير'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final pathController = TextEditingController(text: '/storage/emulated/0/marina-hotel-backups/');
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استيراد البيانات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('أدخل المسار الكامل لملف النسخة الاحتياطية (.json.gz)'),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(labelText: 'المسار الكامل'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                final path = pathController.text.trim();
                Navigator.pop(ctx);
                if (path.isEmpty) {
                  _showSnack('لم يتم إدخال مسار الملف', isError: true);
                  return;
                }
                _runTask(context, progressMessage: 'جاري استيراد البيانات...', action: () => _importDataFromPath(path));
              },
              child: const Text('استيراد'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعادة تشغيل الخدمات'),
          content: const Text('سيتم تحديث جميع المزودات وإعادة تحميل البيانات من قاعدة البيانات.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(ctx);
                _runTask(context, progressMessage: 'جاري إعادة تشغيل الخدمات...', action: _restartServices);
              },
              child: const Text('إعادة تشغيل'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetAppDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعادة تعيين التطبيق'),
          content: const Text('تحذير: سيؤدي هذا إلى حذف جميع البيانات المحلية وإعادة تهيئة النظام. لا يمكن التراجع عن هذه العملية.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                Navigator.pop(ctx);
                _runTask(context, progressMessage: 'جاري إعادة تهيئة التطبيق...', action: _resetApplication);
              },
              child: const Text('إعادة تعيين'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _performCleanup() async {
    final dbInstance = ref.read(databaseProvider);
    await dbInstance.transaction(() async {
      await dbInstance.customStatement('DELETE FROM rooms WHERE deleted_at IS NOT NULL');
      await dbInstance.customStatement('DELETE FROM bookings WHERE deleted_at IS NOT NULL');
      await dbInstance.customStatement('DELETE FROM booking_notes WHERE deleted_at IS NOT NULL');
      await dbInstance.customStatement('DELETE FROM employees WHERE deleted_at IS NOT NULL');
      await dbInstance.customStatement('DELETE FROM expenses WHERE deleted_at IS NOT NULL');
      await dbInstance.customStatement('DELETE FROM cash_transactions WHERE deleted_at IS NOT NULL');
      await dbInstance.customStatement('DELETE FROM payments WHERE deleted_at IS NOT NULL');
      await dbInstance.customStatement('DELETE FROM outbox WHERE last_error IS NOT NULL OR attempts >= 5');
    });
    await dbInstance.customStatement('VACUUM');
    return 'تم تنظيف البيانات المؤقتة وإعادة تنظيم قاعدة البيانات';
  }

  Future<String> _performDatabaseCheck() async {
    final dbInstance = ref.read(databaseProvider);
    final result = await dbInstance.customSelect('PRAGMA quick_check').get();
    final messages = result.map((row) => row.data.values.first.toString()).toList();
    if (messages.length == 1 && messages.first == 'ok') {
      return 'تم فحص قاعدة البيانات، ولم يتم العثور على أخطاء';
    }
    return 'انتهى الفحص مع الملاحظات التالية:\n${messages.join('\n')}';
  }

  Future<String> _resetSync() async {
    final dbInstance = ref.read(databaseProvider);
    await dbInstance.transaction(() async {
      await dbInstance.customStatement('DELETE FROM outbox');
      await dbInstance.customStatement('DELETE FROM sync_state');
      await dbInstance.into(dbInstance.syncState).insertOnConflictUpdate(
        SyncStateCompanion(
          id: Value(1),
          lastServerTs: Value(0),
          lastPullTs: Value(0),
          lastPushTs: Value(0),
          isSyncing: Value(0),
          version: Value(1),
        ),
      );
    });
    await ref.read(syncServiceProvider).runSync();
    return 'تمت إعادة تعيين المزامنة بنجاح وبدء مزامنة جديدة';
  }

  Future<String> _exportData() async {
    final directory = await _preferredBackupDirectory();
    final file = await ref.read(driveBackupServiceProvider).exportToDirectory(directory, reason: 'maintenance');
    return 'تم إنشاء النسخة الاحتياطية في ${file.path}';
  }

  Future<String> _importDataFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('الملف غير موجود: $path');
    }
    final bytes = await file.readAsBytes();
    await ref.read(driveBackupServiceProvider).restoreFromArchive(bytes);
    ref.invalidate(roomsListProvider);
    ref.invalidate(bookingsListProvider);
    ref.invalidate(employeesListProvider);
    ref.invalidate(expensesListProvider);
    ref.invalidate(paymentsRepoProvider);
    ref.invalidate(cashTransactionsListProvider);
    return 'تم استيراد البيانات بنجاح من الملف المحدد';
  }

  Future<String> _restartServices() async {
    ref.invalidate(roomsListProvider);
    ref.invalidate(bookingsListProvider);
    ref.invalidate(employeesListProvider);
    ref.invalidate(expensesListProvider);
    ref.invalidate(cashTransactionsListProvider);
    ref.invalidate(paymentsRepoProvider);
    ref.invalidate(activeNotesProvider);
    await ref.read(syncServiceProvider).runSync();
    return 'تم إعادة تشغيل الخدمات وتحديث البيانات';
  }

  Future<String> _resetApplication() async {
    final dbInstance = ref.read(databaseProvider);
    await dbInstance.transaction(() async {
      await dbInstance.customStatement('DELETE FROM rooms');
      await dbInstance.customStatement('DELETE FROM bookings');
      await dbInstance.customStatement('DELETE FROM booking_notes');
      await dbInstance.customStatement('DELETE FROM employees');
      await dbInstance.customStatement('DELETE FROM expenses');
      await dbInstance.customStatement('DELETE FROM cash_transactions');
      await dbInstance.customStatement('DELETE FROM payments');
      await dbInstance.customStatement('DELETE FROM outbox');
      await dbInstance.customStatement('DELETE FROM sync_state');
      await dbInstance.into(dbInstance.syncState).insert(
        SyncStateCompanion(
          id: Value(1),
          lastServerTs: Value(0),
          lastPullTs: Value(0),
          lastPushTs: Value(0),
          isSyncing: Value(0),
          version: Value(1),
        ),
      );
    });
    await dbInstance.customStatement('VACUUM');
    ref.invalidate(roomsListProvider);
    ref.invalidate(bookingsListProvider);
    ref.invalidate(employeesListProvider);
    ref.invalidate(expensesListProvider);
    ref.invalidate(cashTransactionsListProvider);
    ref.invalidate(paymentsRepoProvider);
    ref.invalidate(activeNotesProvider);
    return 'تم حذف جميع البيانات المحلية وإعادة تهيئة التطبيق';
  }

  Future<Directory> _preferredBackupDirectory() async {
    final primary = Directory('/storage/emulated/0/marina-hotel-backups');
    try {
      if (!await primary.exists()) {
        await primary.create(recursive: true);
      }
      return primary;
    } catch (_) {}

    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        final nested = Directory('${downloads.path}/marina-hotel-backups');
        if (!await nested.exists()) {
          await nested.create(recursive: true);
        }
        return nested;
      }
    } catch (_) {}

    final docs = await getApplicationDocumentsDirectory();
    final fallback = Directory('${docs.path}/marina-hotel-backups');
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }

  Widget _buildMaintenanceCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceInfo {
  const _MaintenanceInfo({
    required this.rooms,
    required this.bookings,
    required this.employees,
    required this.expenses,
    required this.payments,
    required this.notes,
    required this.databaseSizeBytes,
    required this.lastSync,
  });

  final int rooms;
  final int bookings;
  final int employees;
  final int expenses;
  final int payments;
  final int notes;
  final int databaseSizeBytes;
  final DateTime? lastSync;

  String get formattedStorage => _formatBytes(databaseSizeBytes);
  String get formattedLastSync => lastSync == null
      ? 'لم تتم مزامنة بعد'
      : DateFormat('yyyy/MM/dd • HH:mm').format(lastSync!.toLocal());

  static _MaintenanceInfo empty() => const _MaintenanceInfo(
        rooms: 0,
        bookings: 0,
        employees: 0,
        expenses: 0,
        payments: 0,
        notes: 0,
        databaseSizeBytes: 0,
        lastSync: null,
      );

  static Future<_MaintenanceInfo> collect(AppDatabase db) async {
    final rooms = await _countActive(db, 'rooms');
    final bookings = await _countActive(db, 'bookings');
    final employees = await _countActive(db, 'employees');
    final expenses = await _countActive(db, 'expenses');
    final payments = await _countActive(db, 'payments');
    final notes = await _countActive(db, 'booking_notes');

    DateTime? lastSync;
    final syncRow = await (db.select(db.syncState)..where((tbl) => tbl.id.equals(1))).getSingleOrNull();
    if (syncRow != null && syncRow.lastPullTs > 0) {
      lastSync = DateTime.fromMillisecondsSinceEpoch(syncRow.lastPullTs * 1000);
    }

    final dbFile = await _resolveDatabaseFile();
    final sizeBytes = dbFile != null && await dbFile.exists() ? await dbFile.length() : 0;

    return _MaintenanceInfo(
      rooms: rooms,
      bookings: bookings,
      employees: employees,
      expenses: expenses,
      payments: payments,
      notes: notes,
      databaseSizeBytes: sizeBytes,
      lastSync: lastSync,
    );
  }
}

Future<int> _countActive(AppDatabase db, String table) async {
  try {
    final result = await db.customSelect('SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL').getSingleOrNull();
    if (result == null) return 0;
    final value = result.data['c'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<File?> _resolveDatabaseFile() async {
  try {
    final base = await getDatabasesPath();
    final primary = File('$base/marina_hotel.db');
    if (await primary.exists()) {
      return primary;
    }
  } catch (_) {}
  try {
    final docs = await getApplicationDocumentsDirectory();
    final alt = File('${docs.path}/marina_hotel.db');
    if (await alt.exists()) {
      return alt;
    }
  } catch (_) {}
  return null;
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
}
