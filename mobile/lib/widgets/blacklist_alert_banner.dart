// ignore_for_file: discarded_futures, use_build_context_synchronously
// ═══════════════════════════════════════════════════════════════
//  blacklist_alert_banner.dart — بانر تحذير القائمة السوداء
//  يظهر على الشاشة الرئيسية عند مطابقة نزيل مع القائمة السوداء
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/blacklist_alert_service.dart';

/// بانر تحذيري يظهر على الشاشة الرئيسية عند وجود نزلاء مطابقين
/// للقائمة السوداء
class BlacklistAlertBanner extends ConsumerWidget {
  const BlacklistAlertBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(blacklistAlertsProvider);

    return alertsAsync.when(
      data: (alerts) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        return _BlacklistBanner(alerts: alerts);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _BlacklistBanner extends ConsumerStatefulWidget {
  const _BlacklistBanner({required this.alerts});
  final List<BlacklistAlert> alerts;

  @override
  ConsumerState<_BlacklistBanner> createState() => _BlacklistBannerState();
}

class _BlacklistBannerState extends ConsumerState<_BlacklistBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alerts;
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade700, width: 2),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Colors.red.shade900.withValues(alpha: 0.95),
            Colors.red.shade700.withValues(alpha: 0.9),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─── الرأس (always visible) ───
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // أيقونة نبض
                  Icon(
                        Icons.warning_rounded,
                        color: Colors.yellow.shade300,
                        size: 28,
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .shimmer(duration: 1200.ms, color: Colors.yellow.withValues(alpha: 0.5)),
                  const SizedBox(width: 12),
                  // نص التحذير
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🚨 تنبيه أمني — القائمة السوداء',
                          style: TextStyle(
                            color: Colors.yellow.shade100,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          alerts.length == 1
                              ? 'نزيل مطابق: ${alerts.first.guestName} — غرفة ${alerts.first.roomNumber}'
                              : '${alerts.length} نزلاء مطابقين للقائمة السوداء',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // زر التوسيع
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
          // ─── التفاصيل (expandable) ───
          if (_expanded)
            Container(
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: alerts.map((alert) {
                  return _AlertCard(
                    alert: alert,
                    onDismiss: () {
                      ref.read(blacklistAlertServiceProvider).dismissAlert(alert.bookingId);
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    ).animate().slideY(begin: -1, duration: 400.ms, curve: Curves.easeOut).fadeIn(duration: 300.ms);
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onDismiss});
  final BlacklistAlert alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.red.shade400.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // اسم النزيل + الغرفة
            Row(
              children: [
                const Icon(Icons.person, color: Colors.yellow, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert.guestName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade900.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'غرفة ${alert.roomNumber}',
                    style: TextStyle(
                      color: Colors.yellow.shade100,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // بيانات القائمة السوداء
            _InfoRow(
              icon: Icons.person_off,
              label: 'الاسم في القائمة',
              value: alert.blacklistEntry.name,
            ),
            if (alert.blacklistEntry.nationalId != null)
              _InfoRow(
                icon: Icons.badge,
                label: 'رقم الهوية',
                value: alert.blacklistEntry.nationalId!,
              ),
            if (alert.blacklistEntry.phone != null)
              _InfoRow(
                icon: Icons.phone,
                label: 'الهاتف',
                value: alert.blacklistEntry.phone!,
              ),
            _InfoRow(
              icon: Icons.report,
              label: 'السبب',
              value: alert.reasonText,
              valueColor: Colors.yellow.shade200,
            ),
            if (alert.blacklistEntry.notes != null && alert.blacklistEntry.notes!.isNotEmpty)
              _InfoRow(
                icon: Icons.note,
                label: 'ملاحظات',
                value: alert.blacklistEntry.notes!,
              ),
            const SizedBox(height: 8),
            // أزرار
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('إغلاق التنبيه', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
