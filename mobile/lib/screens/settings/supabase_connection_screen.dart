import 'package:flutter/material.dart';

import '../../components/app_scaffold.dart';

class SupabaseConnectionScreen extends StatelessWidget {
  const SupabaseConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      title: 'تكامل Supabase',
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'تم إزالة تكامل Supabase من التطبيق. تعتمد جميع الوظائف الآن على المزامنة المحلية وDitto Cloud فقط.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
