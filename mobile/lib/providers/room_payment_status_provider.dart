import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_db.dart';
import '../utils/status_utils.dart';
import 'repository_providers.dart';

/// نموذج بيانات يجمع بين الغرفة وحالة تأخر السداد
class RoomWithPaymentStatus {

  RoomWithPaymentStatus({
    required this.room,
    required this.isPaymentOverdue,
    this.activeBooking,
  });
  final Room room;
  final bool isPaymentOverdue;

  /// ✅ الحجز النشط المرتبط بالغرفة (إن وجد)
  /// يُستخدم لتحديد حالة الإشغال بدلاً من الاعتماد على room.status المخزن
  /// الذي قد يكون قديماً/غير محدث بعد المزامنة
  final Booking? activeBooking;

  /// ✅ هل توجد غرفة بحجز نشط فعلي؟
  bool get hasActiveBooking => activeBooking != null;

  Color get roomColor {
    // صيانة - الأولوية القصوى
    if (room.status == 'صيانة' || room.status == 'maintenance') {
      return Colors.orange.shade600;
    }

    // ✅ نعتمد على وجود حجز نشط فعلي بدلاً من room.status المخزن
    // هذا يضمن أن الغرفة تظهر باللون الصحيح حتى لو كان room.status
    // قديماً أو غير محدث بعد المزامنة مع Appwrite
    if (hasActiveBooking) {
      // غرفة محجوزة بنشاط - أحمر
      return Colors.red.shade600;
    }

    // لا يوجد حجز نشط - خضراء (شاغرة)
    return Colors.green.shade600;
  }

  /// ✅ الحالة المعروضة للغرفة - مشتقة من الحجز النشط
  /// بدلاً من room.status المخزن الذي قد يكون قديماً
  String get displayStatus {
    if (room.status == 'صيانة' || room.status == 'maintenance') {
      return 'صيانة';
    }
    if (hasActiveBooking) {
      return 'محجوزة';
    }
    return 'شاغرة';
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
    if (lastRooms == null || lastBookings == null) {
      return;
    }

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

      // ✅ استخدام bookingByRoom لتحديد وجود حجز نشط فعلي
      // بدلاً من الاعتماد على room.status الذي قد يكون قديماً
      final activeBooking = bookingByRoom[room.roomNumber];

      if (activeBooking != null) {
        final hasRemainingBalance =
            activeBooking.remainingBalanceCached.round() > 0;

        if (hasRemainingBalance) {
          final hour = currentTime.hour;
          // تأخر السداد يبدأ من الساعة 11 مساءً إلى 5 صباحاً
          if (hour >= 23 || hour < 5) {
            isPaymentOverdue = true;
          }
        }
      }

      return RoomWithPaymentStatus(
        room: room,
        isPaymentOverdue: isPaymentOverdue,
        activeBooking: activeBooking,
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
