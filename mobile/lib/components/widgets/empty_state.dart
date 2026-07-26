import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({      required this.title,
      super.key,
      this.subtitle,
      this.message,
      this.icon,
  });
  final String title;
  final String? subtitle;
  final String? message;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.inbox, size: 48, color: muted),
          const SizedBox(height: 8),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null)
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
          if (message != null)
            Text(
              message!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
