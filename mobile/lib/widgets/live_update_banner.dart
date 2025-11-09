import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ❌ تمت إزالة الـ imports المتعلقة بـ Supabase Realtime

/// بانر التحديثات الفورية (معطل بعد إزالة Supabase)
class LiveUpdateBanner extends ConsumerWidget {
  const LiveUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ❌ تم تعطيل LiveUpdateBanner بعد إزالة Supabase Realtime
    return const SizedBox.shrink();
  }
}