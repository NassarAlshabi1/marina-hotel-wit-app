import 'package:flutter/material.dart';
import '../constants/ui_constants.dart';

/// Info Row Widget - عرض معلومة بصيغة (Label: Value)
class InfoRow extends StatelessWidget {
  const InfoRow({      required this.label,
      required this.value,
      super.key,
      this.icon,
      this.iconColor,
      this.labelStyle,
      this.valueStyle,
      this.isExpandable = false,
  });
  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final bool isExpandable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UIConstants.spacingSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: UIConstants.iconSizeSM, color: iconColor ?? Colors.grey.shade600),
            const SizedBox(width: UIConstants.spacingSM),
          ],
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle ?? TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                const SizedBox(width: UIConstants.spacingSM),
                if (isExpandable)
                  Expanded(
                    child: Text(
                      value,
                      style: valueStyle ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.end,
                    ),
                  )
                else
                  Text(
                    value,
                    style: valueStyle ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.end,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat Card Widget - عرض إحصائية برقم وأيقونة
class StatCard extends StatelessWidget {
  const StatCard({      required this.title,
      required this.value,
      required this.icon,
      required this.color,
      super.key,
      this.onTap,
      this.subtitle,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UIConstants.radiusLG)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
        child: Padding(
          padding: const EdgeInsets.all(UIConstants.spacingMD),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(UIConstants.spacingSM),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(UIConstants.radiusMD),
                    ),
                    child: Icon(icon, color: color, size: UIConstants.iconSizeMD),
                  ),
                ],
              ),
              const SizedBox(height: UIConstants.spacingSM),
              Text(
                value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: UIConstants.spacingXS),
                Text(subtitle!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Status Badge Widget - عرض حالة بلون وأيقونة
class StatusBadge extends StatelessWidget {
  const StatusBadge({      required this.status,
      super.key,
      this.color,
      this.icon,
      this.showIcon = true,
      this.fontSize,
  });
  final String status;
  final Color? color;
  final IconData? icon;
  final bool showIcon;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final badgeColor = color ?? UIConstants.getColorForStatus(status);
    final badgeIcon = icon ?? UIConstants.getIconForStatus(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: UIConstants.spacingSM, vertical: UIConstants.spacingXS),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(UIConstants.radiusSM),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[Icon(badgeIcon, size: 12, color: badgeColor), const SizedBox(width: 4)],
          Text(
            status,
            style: TextStyle(fontSize: fontSize ?? 11, fontWeight: FontWeight.w600, color: badgeColor),
          ),
        ],
      ),
    );
  }
}

/// Section Header Widget - عنوان قسم
class SectionHeader extends StatelessWidget {
  const SectionHeader({      required this.title,
      super.key,
      this.icon,
      this.action,
      this.color,
  });
  final String title;
  final IconData? icon;
  final Widget? action;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: UIConstants.spacingLG, bottom: UIConstants.spacingMD),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: UIConstants.iconSizeMD, color: color ?? Theme.of(context).primaryColor),
            const SizedBox(width: UIConstants.spacingSM),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color ?? Theme.of(context).primaryColor,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Empty State Widget - عرض حالة فارغة
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({      required this.message,
      super.key,
      this.icon = Icons.inbox_outlined,
      this.actionLabel,
      this.onAction,
  });
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: UIConstants.iconSizeXL * 2, color: Colors.grey.shade300),
            const SizedBox(height: UIConstants.spacingLG),
            Text(
              message,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: UIConstants.spacingLG),
              ElevatedButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading State Widget - عرض حالة تحميل
class LoadingStateWidget extends StatelessWidget {
  const LoadingStateWidget({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: UIConstants.spacingMD),
            Text(message!, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          ],
        ],
      ),
    );
  }
}

/// Error State Widget - عرض حالة خطأ
class ErrorStateWidget extends StatelessWidget {
  const ErrorStateWidget({      required this.message,
      super.key,
      this.onRetry,
  });
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: UIConstants.iconSizeXL * 2, color: Colors.red.shade300),
            const SizedBox(height: UIConstants.spacingLG),
            Text(
              message,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: UIConstants.spacingLG),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Info Badge Widget - badge للأرقام والإشعارات
class InfoBadge extends StatelessWidget {
  const InfoBadge({      required this.text,
      super.key,
      this.backgroundColor,
      this.textColor,
  });
  final String text;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor ?? Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor ?? Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }
}
