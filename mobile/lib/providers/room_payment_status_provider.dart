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

/// بروفايدر لمراقبة الوقت الحالي (يحدث كل دقيقة)
final currentTimeProvider = StreamProvider<DateTime>((ref) {
  return Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now())
      .asyncMap((_) async => DateTime.now());
});

/// بروفايدر يدمج الغرف مع حالة تأخر السداد بناءً على الوقت وحالة الحجز
final roomsWithPaymentStatusProvider = StreamProvider.autoDispose<List<RoomWithPaymentStatus>>((ref) {
  final roomsAsync = ref.watch(roomsListProvider);
  final bookingsAsync = ref.watch(bookingsListProvider);
  final currentTime = ref.watch(currentTimeProvider).value ?? DateTime.now();

  // ننتظر حتى تتوفر البيانات من كلا الستريمين
  if (roomsAsync.value == null || bookingsAsync.value == null) {
    return const Stream.empty();
  }

  final rooms = roomsAsync.value!;
  final bookings = bookingsAsync.value!;

  final result = rooms.map((room) {
    bool isPaymentOverdue = false;

    // إذا كانت الغرفة محجوزة، نبحث عن الحجز النشط لها
    if (StatusUtils.isRoomOccupied(room.status)) {
      // البحث عن الحجز النشط للغرفة (الحالة 'محجوزة')
      final activeBooking = bookings.where((b) => 
        b.roomNumber == room.roomNumber && 
        StatusUtils.isActiveBooking(b.status)
      ).toList();

      if (activeBooking.isNotEmpty) {
        final booking = activeBooking.first;
        // التحقق من وجود مبلغ متبقي (لم يسدد بالكامل)
        final hasRemainingBalance = booking.remainingBalanceCached > 0.1;
        
        if (hasRemainingBalance) {
          final hour = currentTime.hour;
          
          // المنطق المطلوب:
          // يتحول للون البني في حال تأخر النزيل عن السداد إلى الساعة 23 مساءً
          // ويستمر بني حتى يقوم بالسداد أو يتجاوز الوقت الساعة 6 صباحاً (حيث يعود للأحمر)
          // ملاحظة: "يتجاوز الوقت الساعة 6 صباحاً يرجع إلى الأحمر" تعني أن الفترة البنية هي [23:00 - 06:00]
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

  return Stream.value(result);
});
