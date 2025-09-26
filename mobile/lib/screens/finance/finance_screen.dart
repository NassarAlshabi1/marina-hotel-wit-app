import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../payments/payments_main_screen.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AppScaffold(
      title: 'المالية',
      body: PaymentsMainScreen(),
    );
  }
}
