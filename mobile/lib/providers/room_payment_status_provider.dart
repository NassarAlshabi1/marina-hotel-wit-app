import 'package:flutter/material.dart';
import 'dart:async';
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
      return Colors.green.shade600;
    }

    if (room.status == 'صيانة') {
      return Colors.orange.shade600;
    }

    // إذا كانت الغرفة محجوزة، نتحقق من حالة تأخر السداد
    if (isPaymentOverdue) {
      return const Color(0xFF795548); // اللون البني (Brown)
    }

    return Colors.red.shade600; // اللون الأحمر الافتراضي للمحجوز
  }
}

/// بروفايدر يدمج الغرف مع حالة تأخر السداد — يتحدث تلقائياً مع تغييرات DB
final roomsWithPaymentStatusProvider =
    StreamProvider.autoDispose<List<RoomWithPaymentStatus>>((ref) {
  // استخدام الـ repositories مباشرة للحصول على Streams حقيقية
  final roomsStream = ref.watch(roomsRepoProvider).watchAll();
  final bookingsStream = ref.watch(bookingsRepoProvider).watch();

  // دمج الستريمان — أي تغيير في غرف، حجوزات، أو الوقت يُعيد حساب الحالات
  final controller = StreamController<List<RoomWithPaymentStatus>>();

  // التتبع الأخير لكل ستيرام لتجنب التكرار
  List<Room>? lastRooms;
  List<Booking>? lastBookings;
  DateTime lastTime = DateTime.now();

  void computeAndEmit() {
    if (lastRooms == null || lastBookings == null) return;

    final currentTime = lastTime;
    final rooms = lastRooms!;
    final bookings = lastBookings!;

    final result = rooms.map((room) {
      bool isPaymentOverdue = false;

      if (StatusUtils.isRoomOccupied(room.status)) {
        final activeBooking = bookings
            .where(
              (b) =>
                  b.roomNumber == room.roomNumber &&
                  StatusUtils.isActiveBooking(b.status),
            )
            .toList();

        if (activeBooking.isNotEmpty) {
          final booking = activeBooking.first;
          final hasRemainingBalance = booking.remainingBalanceCached > 0.1;

          if (hasRemainingBalance) {
            final hour = currentTime.hour;
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

    if (!controller.isClosed) {
      controller.add(result);
    }
  }

  roomsStream.listen((rooms) {
    lastRooms = rooms;
    computeAndEmit();
  });

  bookingsStream.listen((bookings) {
    lastBookings = bookings;
    computeAndEmit();
  });

  // تحديث الوقت كل دقيقة لإعادة حساب حالة التأخر (23:00-06:00)
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    lastTime = DateTime.now();
    computeAndEmit();
  });

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});
