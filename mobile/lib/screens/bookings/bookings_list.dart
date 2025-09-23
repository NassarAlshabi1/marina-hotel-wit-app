import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import 'booking_edit.dart';

class BookingsListScreen extends ConsumerWidget {
  const BookingsListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingsListProvider);
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
      body: bookings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('خطأ: $e')),
        data: (list) {
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
