import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';

class PaymentsListScreen extends ConsumerWidget {
  const PaymentsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(paymentsRepoProvider);
    return AppScaffold(
      title: 'المدفوعات',
      body: StreamBuilder(
        stream: repo.paymentsByBooking(-1),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final p = list[i];
              return ListTile(
                title: Text('${p.amount.toStringAsFixed(2)} • ${p.paymentMethod}'),
                subtitle: Text('${p.paymentDate} • ${p.revenueType}'),
                trailing: p.roomNumber != null ? Chip(label: Text(p.roomNumber!)) : null,
              );
            },
          );
        },
      ),
    );
  }
}
