import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import 'booking_edit.dart';

class BookingsListScreen extends ConsumerWidget {
  const BookingsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(coreProviders.dbProvider);
    return AppScaffold(
      title: 'الحجوزات',
      actions: [
        IconButton(
          onPressed: () => ref.read(coreProviders.syncProvider).runSync(),
          icon: const Icon(Icons.sync),
        ),
        IconButton(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingEditScreen()));
          },
          icon: const Icon(Icons.add),
        )
      ],
      body: StreamBuilder(
        stream: db.select(db.bookings).watch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final list = snapshot.data!;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (c, i) {
              final b = list[i];
              return ListTile(
                title: Text('${b.guestName} • ${b.roomNumber}'),
                subtitle: Text('من ${b.checkinDate} إلى ${b.checkoutDate ?? '-'} • ${b.status}'),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingEditScreen(existing: b)));
                },
              );
            },
          );
        },
      ),
    );
  }
}
