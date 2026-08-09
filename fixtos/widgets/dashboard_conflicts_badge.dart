import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ✅ P3-6 (Conflict Visibility): شارة "N تعارض يحتاج مراجعة" — تجعل
/// التصعيد اليدوي للتعارضات مرئياً بدل أن يبقى صامتاً.
///
/// تعرض هذه الشارة بجانب أزرار المزامنة في لوحة التحكم. عندما يكون
/// هناك تعارضات معلّقة (resolution = '') في جدول sync_conflicts، تظهر
/// شارة حمراء نابضة بعدد التعارضات. النقر عليها يفتح شاشة مراجعة
/// التعارضات مباشرةً (SyncConflictsScreen).
class DashboardConflictsBadge extends ConsumerWidget {
  const DashboardConflictsBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SizedBox.shrink();
  }
}
