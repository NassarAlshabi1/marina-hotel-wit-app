import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auto_backup_manager.dart';
import '../../services/google_drive_backup_service.dart';
import '../../providers/auto_backup_provider.dart';

class AutoBackupSettingsScreen extends ConsumerStatefulWidget {
  const AutoBackupSettingsScreen({super.key});

  @override
  ConsumerState<AutoBackupSettingsScreen> createState() => _AutoBackupSettingsScreenState();
}

class _AutoBackupSettingsScreenState extends ConsumerState<AutoBackupSettingsScreen> {
  late TextEditingController _maxBackupsController;
  late TextEditingController _retentionDaysController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _maxBackupsController = TextEditingController();
    _retentionDaysController = TextEditingController();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _maxBackupsController.dispose();
    _retentionDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    final manager = AutoBackupManager.instance;
    final maxBackups = await manager.getMaxBackupCount();
    final retentionDays = await manager.getRetentionDays();
    
    setState(() {
      _maxBackupsController.text = maxBackups.toString();
      _retentionDaysController.text = retentionDays.toString();
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final manager = AutoBackupManager.instance;
      final maxBackups = int.tryParse(_maxBackupsController.text) ?? 25;
      final retentionDays = int.tryParse(_retentionDaysController.text) ?? 45;
      
      await manager.setMaxBackupCount(maxBackups);
      await manager.setRetentionDays(retentionDays);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم حفظ الإعدادات بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في حفظ الإعدادات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _toggleAutoBackup(bool enabled) async {
    setState(() => _isLoading = true);
    
    try {
      final manager = AutoBackupManager.instance;
      await manager.setEnabled(enabled);
      
      ref.invalidate(autoBackupStatusProvider);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? '✅ تم تفعيل النسخ التلقائي' : '⏸️ تم إيقاف النسخ التلقائي'),
          backgroundColor: enabled ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في تغيير حالة النسخ التلقائي: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _performCleanupNow() async {
    setState(() => _isLoading = true);
    
    try {
      final manager = AutoBackupManager.instance;
      await manager.cleanupNow();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🧹 تم تنظيف النسخ القديمة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ في تنظيف النسخ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(autoBackupStatusProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي التلقائي الذكي'),
        centerTitle: true,
        elevation: 0,
      ),
      body: statusAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('خطأ في تحميل الإعدادات: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(autoBackupStatusProvider),
                child: const Text('إعادة تحميل'),
              ),
            ],
          ),
        ),
        data: (status) => _buildSettingsUI(status),
      ),
    );
  }

  Widget _buildSettingsUI(Map<String, dynamic> status) {
    final isEnabled = status['enabled'] as bool;
    final isBackingUp = status['is_backing_up'] as bool;
    final pendingChanges = status['pending_changes'] as int;
    final lastBackup = status['last_auto_backup'] as String?;
    final maxBackups = status['max_backups'] as int;
    final retentionDays = status['retention_days'] as int;
    final isSignedIn = status['signed_in'] as bool;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // معلومات الحالة
          _buildStatusCard(isEnabled, isBackingUp, pendingChanges, lastBackup, isSignedIn),
          
          const SizedBox(height: 20),
          
          // إعدادات التفعيل/الإيقاف
          _buildToggleCard(isEnabled),
          
          const SizedBox(height: 20),
          
          // إعدادات التنظيف
          _buildCleanupSettingsCard(maxBackups, retentionDays),
          
          const SizedBox(height: 20),
          
          // أزرار الإجراءات
          _buildActionButtons(isEnabled, isSignedIn),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isEnabled, bool isBackingUp, int pendingChanges, String? lastBackup, bool isSignedIn) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEnabled ? Icons.cloud_sync : Icons.cloud_off,
                  color: isEnabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'حالة النسخ التلقائي',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            _buildStatusRow('الحالة', isEnabled ? 'مُفعل ✅' : 'معطل ⏸️'),
            _buildStatusRow('تسجيل الدخول', isSignedIn ? 'متصل ✅' : 'غير متصل ❌'),
            if (isBackingUp) 
              _buildStatusRow('النشاط', 'جارِ إنشاء نسخة احتياطية... 🔄'),
            if (pendingChanges > 0)
              _buildStatusRow('تغييرات معلقة', '$pendingChanges تغيير 📝'),
            if (lastBackup != null)
              _buildStatusRow('آخر نسخة تلقائية', _formatDateTime(DateTime.parse(lastBackup))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildToggleCard(bool isEnabled) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إعدادات التفعيل',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'النسخ التلقائي الذكي ينشئ نسخة احتياطية تلقائياً بعد كل تغيير في البيانات (حجوزات، مدفوعات، إلخ) بعد انتظار 30 ثانية لتجميع التغييرات.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('تفعيل النسخ التلقائي'),
              subtitle: Text(isEnabled ? 'مُفعل - ينشئ نسخ تلقائية' : 'معطل - لا ينشئ نسخ تلقائية'),
              value: isEnabled,
              onChanged: _isLoading ? null : _toggleAutoBackup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanupSettingsCard(int maxBackups, int retentionDays) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إعدادات التنظيف التلقائي',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            
            TextFormField(
              controller: _maxBackupsController,
              decoration: const InputDecoration(
                labelText: 'عدد النسخ القصوى للاحتفاظ',
                hintText: '25',
                suffixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),
            
            TextFormField(
              controller: _retentionDaysController,
              decoration: const InputDecoration(
                labelText: 'فترة الاحتفاظ بالأيام',
                hintText: '45',
                suffixIcon: Icon(Icons.calendar_today),
              ),
              keyboardType: TextInputType.number,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),
            
            const Text(
              'ملاحظة: سيتم حذف النسخ التي تزيد عن العدد المحدد أو الأقدم من فترة الاحتفاظ تلقائياً كل 6 ساعات.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool isEnabled, bool isSignedIn) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _saveSettings,
            icon: _isLoading ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ) : const Icon(Icons.save),
            label: const Text('حفظ الإعدادات'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_isLoading || !isSignedIn) ? null : _performCleanupNow,
            icon: const Icon(Icons.cleaning_services),
            label: const Text('تنظيف النسخ القديمة الآن'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        
        if (!isSignedIn) ...[
          const SizedBox(height: 8),
          const Text(
            '⚠️ يجب تسجيل الدخول في Google Drive أولاً',
            style: TextStyle(color: Colors.orange, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}