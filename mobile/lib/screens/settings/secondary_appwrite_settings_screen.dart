// lib/screens/settings/secondary_appwrite_settings_screen.dart
//
// ✅ Wave 5 (2026-08-12): شاشة مبسّطة بعد إزالة secondary sync بالكامل.
//
// SecondarySyncManager و SecondarySyncTracker و secondary_sync_provider
// أُزيلوا بالكامل. Appwrite primary هو authority الوحيد للمزامنة.
//
// هذه الشاشة محفوظة كـ placeholder لأن:
// 1. settings_screen.dart يفتحها عند الضغط على "Appwrite الثانوي"
// 2. لعرض رسالة توضيحية للمستخدم بدلاً من UI قديم لا يعمل
// 3. الإزالة الكاملة للشاشة تتطلب refactor settings_screen.dart
//
// SecondaryAppwriteConfig و SecondaryAppwriteService ما زالا موجودتين
// لأن AppwriteHealthChecker يستخدمهما لفحص الـ failover (مسار قراءة فقط).

// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// شاشة إعدادات الوجهة الثانوية لـ Appwrite
///
/// ⚠️ **معطّلة بالكامل** — Secondary sync مُزال من الموجة 5 (2026-08-12).
/// Appwrite primary هو authority الوحيد.
class SecondaryAppwriteSettingsScreen extends ConsumerStatefulWidget {
  const SecondaryAppwriteSettingsScreen({super.key});

  @override
  ConsumerState<SecondaryAppwriteSettingsScreen> createState() =>
      _SecondaryAppwriteSettingsScreenState();
}

class _SecondaryAppwriteSettingsScreenState
    extends ConsumerState<SecondaryAppwriteSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('وجهة Appwrite الثانوية'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'المزامنة الثانوية معطّلة',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'تم تعطيل المزامنة الثانوية بالكامل في هذه النسخة. '
              'Appwrite الأساسي هو المصدر الوحيد للبيانات.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'لماذا تم التعطيل؟',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'تعطيل secondary sync يبسّط المعمارية ويمنع:\n'
                            '• التداخل والـ race conditions بين مزامنتين متوازيتين\n'
                            '• تعقيدات coalescing وتتبع التسليم المزدوج\n'
                            '• احتمالات silent data loss في مسارات الـ ack\n'
                            '• تعقيد الصيانة في outbox dual-delivery\n\n'
                            'Appwrite الأساسي يوفر موثوقية كافية للبيانات، '
                            'ولم يعد هناك حاجة لوجهة ثانوية.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'ما الذي تغيّر؟',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• SecondarySyncManager أُزيل بالكامل\n'
                      '• SecondarySyncTracker أُزيل بالكامل\n'
                      '• secondarySyncProvider أُزيل بالكامل\n'
                      '• outbox dual-delivery تبسّط لـ single-destination\n'
                      '• AppwriteHealthChecker ما زال يفحص الـ endpoint '
                      'الثانوي لأغراض الفشل (failover) فقط',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
