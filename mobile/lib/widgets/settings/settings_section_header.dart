import 'package:flutter/material.dart';

/// ✅ (2026-09-17) طلب المستخدم: إلغاء آلية «الأقسام المخفية».
///
/// كان القسم السابق (CollapsibleSection) يطوي المحتوى خلف نقرة —
/// بديلاً عنه هذا العنوان الثابت: يُعرض دائماً فوق محتواه المكشوف
/// بلا أي طيّ أو إخفاء. نفس الحقول (title/icon/count/subtitle) حتى
/// تبقى الشاشات المُستهلكة بلا أي تغيير في وظائفها.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    required this.title,
    required this.icon,
    super.key,
    this.count,
    this.subtitle,
  });

  final String title;
  final IconData icon;

  /// عدّاد اختياري يظهر في شارة صغيرة بجانب العنوان.
  final int? count;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const headerColor = Colors.blue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: headerColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: headerColor,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: headerColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
