import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart' as coreProviders;

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(coreProviders.dbProvider);
    return AppScaffold(
      title: 'الصندوق',
      actions: [IconButton(onPressed: () => ref.read(coreProviders.syncProvider).runSync(), icon: const Icon(Icons.sync))],
      body: StreamBuilder(
        stream: db.select(db.cashTransactions).watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final t = list[i];
              return ListTile(
                title: Text('${t.transactionType} • ${t.amount.toStringAsFixed(2)}'),
                subtitle: Text('${t.transactionTime} • ${t.referenceType}#${t.referenceId}'),
              );
            },
          );
        },
      ),
    );
  }
}
