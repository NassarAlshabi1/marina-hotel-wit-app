import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.subtitle, this.message, this.icon});
  final String title;
  final String? subtitle;
  final String? message;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.inbox, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Colors.grey)),
          if (message != null) Text(message!, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
