import 'package:flutter/material.dart';

/// ✅ (2026-09-10) مهمة إعادة تنظيم UI/UX — عنصر تقني للعرض فقط.
///
/// قسم قابل للطيّ (Progressive Disclosure): يُظهر العنوان دائماً مع
/// عدّاد الخيارات، والمحتوى يُفتح عند الطلب — بلا أي تغيير في وظائف
/// العناصر بداخله (كل الأبناء يُبنون بنفس المُنشئات السابقة تماماً).
///
/// قواعد المهمة: لا حذف ولا تعطيل — نقل بصري وتنظيم تنقل فقط.
class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
    this.initiallyExpanded = false,
    this.count,
    this.subtitle,
  });

  final String title;
  final IconData icon;

  /// محتوى القسم — تُبنى بنفس دوال البناء السابقة حرفياً.
  final List<Widget> children;

  /// ✅ الافتراضي مطوي — يعرض الشاشة الرئيسية نظيفة، والخيارات
  /// تبقى على بعد نقرة واحدة (إخفاء فقط، لا حذف).
  final bool initiallyExpanded;

  /// عدّاد يظهر في الشارة — يطمئن المستخدم أن الخيارات موجودة مطوية.
  final int? count;
  final String? subtitle;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const headerColor = Colors.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(widget.icon, color: headerColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
                if (widget.count != null) ...[
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
                      '${widget.count}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: headerColor,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.subtitle != null && !_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              widget.subtitle!,
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
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          sizeCurve: Curves.easeInOut,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.children,
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
        ),
      ],
    );
  }
}
