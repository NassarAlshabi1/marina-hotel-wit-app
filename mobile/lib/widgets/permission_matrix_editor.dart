import 'package:flutter/material.dart';

import '../services/permission_catalog.dart';

/// محرر صلاحيات مضغوط: صف لكل وحدة × رقائق العمليات الأربع
/// (عرض/إضافة/تعديل/حذف) + رقاقة «الكل» تمنح مفتاح الوحدة القديم.
///
/// لا يملك منطق التخزين — يستدعي [onToggle] بكل تبديل، والمستدعي
/// يقرر قواعده (مثل «صلاحية واحدة على الأقل» أو وضع القراءة فقط).
class PermissionMatrixEditor extends StatelessWidget {
  const PermissionMatrixEditor({
    required this.selected,
    required this.onToggle,
    super.key,
    this.enabled = true,
  });

  /// مجموعة مفاتيح الصلاحيات المحددة حالياً (module أو module.action).
  final Set<String> selected;

  /// يُستدعى عند كل تبديل: (المفتاح, القيمة الجديدة).
  final void Function(String key, bool value) onToggle;

  /// تعطيل التعديل يجعل كل الرقائق للعرض فقط.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final module in PermissionCatalog.modules)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    module.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _MiniChip(
                        label: 'الكل',
                        selected: selected.contains(module.key),
                        enabled: enabled,
                        onSelected: (v) => onToggle(module.key, v),
                      ),
                      for (final action in PermissionCatalog.actions)
                        _MiniChip(
                          label: action.label,
                          tooltip: '${action.label} ${module.label}',
                          selected: selected.contains(
                            '${module.key}.${action.key}',
                          ),
                          enabled: enabled,
                          onSelected: (v) =>
                              onToggle('${module.key}.${action.key}', v),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final void Function(bool) onSelected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: enabled ? onSelected : null,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}
