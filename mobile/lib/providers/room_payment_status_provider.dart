import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../services/remote_config_service.dart';
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
    // ملاحظة: تم إلغاء اللون البني (overdueRoomColor) والاعتماد على الوميض في الواجهة
    return Colors.red.shade600; // اللون الأحمر للمحجوز والمتأخر في السداد
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

    // بناء خريطة O(1) بدل التكرار O(R×B)
    final bookingByRoom = <String, Booking>{};
    for (final b in bookings) {
      if (StatusUtils.isActiveBooking(b.status)) {
        bookingByRoom[b.roomNumber] = b;
      }
    }

    final result = rooms.map((room) {
      bool isPaymentOverdue = false;

      if (StatusUtils.isRoomOccupied(room.status)) {
        final activeBooking = bookingByRoom[room.roomNumber];

        if (activeBooking != null) {
          final hasRemainingBalance = activeBooking.remainingBalanceCached > 0.1;

          if (hasRemainingBalance) {
            final hour = currentTime.hour;
            // تأخر السداد يبدأ من الساعة 11 مساءً إلى 5 صباحاً
            if (hour >= 23 || hour < 5) {
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

  final roomsSub = roomsStream.listen((rooms) {
    lastRooms = rooms;
    computeAndEmit();
  });

  final bookingsSub = bookingsStream.listen((bookings) {
    lastBookings = bookings;
    computeAndEmit();
  });

  // تحديث الوقت كل دقيقة لإعادة حساب حالة التأخر (23:00-06:00)
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    lastTime = DateTime.now();
    computeAndEmit();
  });

  ref.onDispose(() {
    roomsSub.cancel();
    bookingsSub.cancel();
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});
