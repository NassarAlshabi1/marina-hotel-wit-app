import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../services/drive_backup_service.dart';
import '../../services/providers.dart';

class SettingsDriveBackupScreen extends ConsumerWidget {
  const SettingsDriveBackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(driveBackupStateProvider);
    return AppScaffold(
      title: 'النسخ الاحتياطي عبر Google Drive',
      body: statusAsync.when(
        data: (status) => _DriveBackupContent(status: status),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString(), textAlign: TextAlign.center)),
      ),
    );
  }
}

class _DriveBackupContent extends ConsumerWidget {
  const _DriveBackupContent({required this.status});
  final DriveBackupStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(driveBackupServiceProvider);
    final theme = Theme.of(context);
    final tiles = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('حالة الخدمة', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              _InfoRow(label: 'الحساب المتصل', value: status.accountEmail ?? 'غير متصل'),
              const SizedBox(height: 12),
              _InfoRow(label: 'آخر نسخة احتياطية', value: _formatDate(status.lastBackup)),
              const SizedBox(height: 12),
              _InfoRow(label: 'النسخ الاحتياطي التلقائي', value: status.hasPendingBackup ? 'في الانتظار (${status.pendingReason})' : 'لا يوجد إجراء معلق'),
              const SizedBox(height: 12),
              _InfoRow(label: 'الحالة الحالية', value: status.isBackingUp ? 'جاري النسخ الاحتياطي' : status.isSignedIn ? 'جاهز' : 'غير متصل'),
              if (status.isBackingUp) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    ];

    if (status.lastError != null) {
      tiles.addAll([
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              status.lastError!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ),
      ]);
    }

    tiles.addAll([
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: status.isSignedIn && !status.isBackingUp ? () async {
          await service.backupNow(reason: 'manual');
        } : null,
        icon: status.isBackingUp ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
        label: Text(status.isBackingUp ? 'جارٍ تنفيذ النسخ الاحتياطي' : 'تشغيل النسخ الاحتياطي الآن'),
      ),
      const SizedBox(height: 12),
      if (!status.isSignedIn)
        OutlinedButton.icon(
          onPressed: status.isBackingUp ? null : () async {
            await service.signIn();
          },
          icon: const Icon(Icons.login),
          label: const Text('تسجيل الدخول إلى Google Drive'),
        )
      else
        TextButton.icon(
          onPressed: status.isBackingUp ? null : () async {
            await service.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج من الحساب'),
        ),
      const SizedBox(height: 24),
      Text(
        'بعد تسجيل الدخول، يتم إنشاء نسخة احتياطية تلقائياً عند إضافة الحجوزات أو المدفوعات أو أي تعديل مهم في البيانات.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Text(
        'سيتم حفظ النسخ الاحتياطية في مجلد التطبيق على Google Drive الخاص بك ويمكن تحميلها عند الحاجة.',
        style: theme.textTheme.bodySmall,
      ),
    ]);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: tiles,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'لا توجد نسخة';
  }
  final formatter = DateFormat('yyyy/MM/dd • HH:mm');
  return formatter.format(value.toLocal());
}
