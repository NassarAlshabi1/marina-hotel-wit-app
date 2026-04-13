import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../utils/status_utils.dart';
import 'repository_providers.dart';

/// نموذج بيانات يجمع بين الغرفة وحالة تأخر السداد
class RoomWithPaymentStatus {
  final Room room;
  final bool isPaymentOverdue;

  RoomWithPaymentStatus({
    required this.room,
    required this.isPaymentOverdue,
  });

  Color get roomColor {
    if (StatusUtils.isRoomAvailable(room.status)) {
      return Colors.green;
    }
    
    // إذا كانت الغرفة محجوزة، نتحقق من حالة تأخر السداد
    if (isPaymentOverdue) {
      return const Color(0xFFA1887F); // اللون البني المطلوب
    }
    
    return Colors.red;
  }
}

/// بروفايدر لمراقبة الوقت الحالي (يحدث كل دقيقة)
final currentTimeProvider = StreamProvider<DateTime>((ref) {
  return Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now())
      .startWith(DateTime.now());
});

extension StreamStartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}

/// بروفايدر يدمج الغرف مع حالة تأخر السداد بناءً على الوقت وحالة الحجز
final roomsWithPaymentStatusProvider = StreamProvider.autoDispose<List<RoomWithPaymentStatus>>((ref) {
  final roomsStream = ref.watch(roomsListProvider.stream);
  final bookingsStream = ref.watch(bookingsListProvider.stream);
  final currentTime = ref.watch(currentTimeProvider).value ?? DateTime.now();

  return roomsStream.combineLatest(bookingsStream, (rooms, bookings) {
    return rooms.map((room) {
      bool isPaymentOverdue = false;

      // إذا كانت الغرفة محجوزة، نبحث عن الحجز النشط لها
      if (!StatusUtils.isRoomAvailable(room.status)) {
        final activeBooking = bookings.firstWhere(
          (b) => b.roomNumber == room.roomNumber && StatusUtils.isActiveBooking(b.status),
          orElse: () => null as dynamic,
        );

        if (activeBooking != null) {
          // التحقق من حالة السداد (إذا كان هناك رصيد متبقي)
          final hasRemainingBalance = activeBooking.remainingBalanceCached > 0;
          
          if (hasRemainingBalance) {
            final hour = currentTime.hour;
            
            // المنطق المطلوب:
            // من الساعة 23:00 مساءً حتى الساعة 06:00 صباحاً يتحول للون البني إذا لم يسدد
            if (hour >= 23 || hour < 6) {
              isPaymentOverdue = true;
            }
          }
        }
      }

      return RoomWithPaymentStatus(
        room: room,
        isPaymentOverdue: isPaymentOverdue,
      );
    }).toList();
  });
});

extension StreamCombine<T> on Stream<T> {
  Stream<R> combineLatest<S, R>(Stream<S> other, R Function(T, S) combiner) async* {
    T? lastT;
    S? lastS;
    bool tHasValue = false;
    bool sHasValue = false;

    final stream1 = map((event) {
      lastT = event;
      tHasValue = true;
      return true;
    });
    final stream2 = other.map((event) {
      lastS = event;
      sHasValue = true;
      return true;
    });

    await for (final _ in StreamGroup.merge([stream1, stream2])) {
      if (tHasValue && sHasValue) {
        yield combiner(lastT as T, lastS as S);
      }
    }
  }
}

/// كلاس مساعد لدمج الستريمات (بسيط)
class StreamGroup {
  static Stream<T> merge<T>(Iterable<Stream<T>> streams) async* {
    final List<StreamIterator<T>> iterators = streams.map((s) => StreamIterator(s)).toList();
    try {
      while (true) {
        final List<Future<bool>> nextFutures = iterators.map((i) => i.moveNext()).toList();
        final bool anyNext = (await Future.wait(nextFutures)).any((b) => b);
        if (!anyNext) break;
        for (final i in iterators) {
          yield i.current;
        }
      }
    } finally {
      for (final i in iterators) {
        await i.cancel();
      }
    }
  }
}
