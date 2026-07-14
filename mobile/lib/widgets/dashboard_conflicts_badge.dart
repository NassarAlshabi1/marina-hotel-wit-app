import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sync_providers.dart';
import '../screens/settings/sync_conflicts_screen.dart';

/// ✅ P3-6 (Conflict Visibility): شارة "N تعارض يحتاج مراجعة" — تجعل
/// التصعيد اليدوي للتعارضات مرئياً بدل أن يبقى صامتاً.
///
/// تعرض هذه الشارة بجانب أزرار المزامنة في لوحة التحكم. عندما يكون
/// هناك تعارضات معلّقة (resolution = '') في جدول sync_conflicts، تظهر
/// شارة حمراء نابضة بعدد التعارضات. النقر عليها يفتح شاشة مراجعة
/// التعارضات مباشرةً (SyncConflictsScreen).
///
/// مصدر البيانات: [pendingConflictsCountProvider] — يراقب الجدول عبر
/// drift's `.watch()`، فيُحدّث العدد فوراً عند تسجيل تعارض جديد أو حلّه.
class DashboardConflictsBadge extends ConsumerWidget {
  const DashboardConflictsBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(pendingConflictsCountProvider);

    return countAsync.when(
      data: (count) => _buildBadge(context, count),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildBadge(BuildContext context, int count) {
    if (count <= 0) {
      // لا توجد تعارضات — لا نعرض شيئاً. هذا يعني أن كل شيء على ما يرام،
      // ولا داعي لإزعاج المستخدم بشارة فارغة.
      return const SizedBox.shrink();
    }

    // ✅ شارة حمراء نابضة لجذب الانتباه. النبض خفيف (1.0 ↔ 1.1) لمدة
    // 1.2 ثانية لكل دورة — كافٍ للجذب دون أن يكون مزعجاً.
    return Tooltip(
      message: '$count تعارض يحتاج مراجعة — اضغط للعرض',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const SyncConflictsScreen(),
            ),
          );
        },
        child: _PulsingBadge(count: count),
      ),
    );
  }
}

/// شارة نابضة بحجم صغير (مطابق لحجم شارة pending changes في الأزرار).
class _PulsingBadge extends StatefulWidget {
  const _PulsingBadge({required this.count});
  final int count;

  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayCount = widget.count > 99 ? '99+' : '${widget.count}';
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.redAccent, Colors.red],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.4),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              displayCount,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
