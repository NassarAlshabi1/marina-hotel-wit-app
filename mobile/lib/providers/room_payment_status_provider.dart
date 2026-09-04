import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_db.dart';
import '../utils/status_utils.dart';
import 'repository_providers.dart';

/// ✅ مقارنة قائمتين من RoomWithPaymentStatus لمنع إعادة الإرسال غير الضرورية
/// هذا يمنع وميض الشاشة (flickering) عند عدم تغيير البيانات فعلياً
bool _listsEqual(List<RoomWithPaymentStatus> a, List<RoomWithPaymentStatus> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final ra = a[i];
    final rb = b[i];
    if (ra.room.localUuid != rb.room.localUuid) return false;
    if (ra.isPaymentOverdue != rb.isPaymentOverdue) return false;
    if (ra.isLatePayment != rb.isLatePayment) {
      return false;
    }
    if (ra.activeBooking?.localUuid != rb.activeBooking?.localUuid) {
      return false;
    }
    if (ra.room.status != rb.room.status) return false;
  }
  return true;
}

/// نموذج بيانات يجمع بين الغرفة وحالة تأخر السداد
class RoomWithPaymentStatus {
  RoomWithPaymentStatus({
    required this.room,
    required this.isPaymentOverdue,
    this.activeBooking,
    this.isLatePayment = false,
  });
  final Room room;
  final bool isPaymentOverdue;

  /// ✅ مرحلة تحذير مبكرة (22:00-23:59): الغرفة محجوزة + رصيد متبقي +
  /// الوقت بين 22:00 و 23:59 مساءً. في هذه المرحلة يتحول جزء من الزر
  /// إلى اللون البرتقالي للتنبيه.
  final bool isLatePayment;

  /// ✅ الحجز النشط المرتبط بالغرفة (إن وجد)
  /// يُستخدم لتحديد حالة الإشغال بدلاً من الاعتماد على room.status المخزن
  /// الذي قد يكون قديماً/غير محدث بعد المزامنة
  final Booking? activeBooking;

  /// ✅ هل توجد غرفة بحجز نشط فعلي؟
  bool get hasActiveBooking => activeBooking != null;

  /// ✅ هل تحتاج الغرفة لإظهار المؤشر البرتقالي الجزئي؟
  /// يصبح true عند 22:00+ مع وجود رصيد متبقي (مرحلة التحذير المبكر).
  bool get hasLatePaymentIndicator => isLatePayment || isPaymentOverdue;

  Color get roomColor {
    // صيانة - الأولوية القصوى
    if (StatusUtils.isUnderMaintenance(room.status)) {
      return Colors.orange.shade600;
    }

    // ✅ نعتمد على وجود حجز نشط فعلي بدلاً من room.status المخزن
    // هذا يضمن أن الغرفة تظهر باللون الصحيح حتى لو كان room.status
    // قديماً أو غير محدث بعد المزامنة مع Appwrite
    // ✅ نعتمد على وجود حجز نشط فعلي بدلاً من room.status المخزن
    // هذا يضمن أن الغرفة تظهر باللون الأخضر فور تسجيل المغادرة (حتى لو لم تتزامن الحالة بعد)
    if (hasActiveBooking) {
      // غرفة محجوزة بنشاط - أحمر
      return Colors.red.shade600;
    }

    // لا يوجد حجز نشط أو تم تسجيل المغادرة - خضراء (شاغرة)
    return Colors.green.shade600;
  }

  /// ✅ الحالة المعروضة للغرفة - مشتقة من الحجز النشط
  /// بدلاً من room.status المخزن الذي قد يكون قديماً
  String get displayStatus {
    if (StatusUtils.isUnderMaintenance(room.status)) {
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

      // ✅ تخزين آخر نتيجة مُرسلة لمنع إعادة الإرسال عند عدم التغيير
      List<RoomWithPaymentStatus>? lastEmitted;

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
          bool isLatePayment = false;

          // ✅ استخدام bookingByRoom لتحديد وجود حجز نشط فعلي
          // بدلاً من الاعتماد على room.status الذي قد يكون قديماً
          final activeBooking = bookingByRoom[room.roomNumber];

          if (activeBooking != null) {
            final hasRemainingBalance =
                activeBooking.remainingBalanceCached.round() > 0;

            if (hasRemainingBalance) {
              final hour = currentTime.hour;
              // ✅ مرحلة التحذير المبكر: من 22:00 (10 مساءً) إلى 23:59
              // في هذه المرحلة يظهر مؤشر برتقالي جزئي على الزر للتنبيه
              // أن السداد سيتأخر قريباً.
              if (hour >= 22 && hour < 23) {
                isLatePayment = true;
              }
              // ✅ مرحلة التأخر الفعلي: من 23:00 (11 مساءً) إلى 05:00 (5 صباحاً)
              // في هذه المرحلة يكون الزر بأكمله ينبض باللون البرتقالي/الأحمر.
              if (hour >= 23 || hour < 5) {
                isPaymentOverdue = true;
              }
            }
          }

          return RoomWithPaymentStatus(
            room: room,
            isPaymentOverdue: isPaymentOverdue,
            isLatePayment: isLatePayment,
            activeBooking: activeBooking,
          );
        }).toList();

        // ✅ إصلاح الوميض: لا نُرسل بيانات جديدة إذا كانت مطابقة للسابقة
        // هذا يمنع إعادة بناء الـ Widgets وإعادة تشغيل الرسوم المتحركة بدون سبب
        if (lastEmitted != null && _listsEqual(lastEmitted!, result)) {
          return; // لا تغيير فعلي — لا حاجة للإرسال
        }
        lastEmitted = result;

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

      // تحديث الوقت كل دقيقة لإعادة حساب حالة التأخر
      // ✅ نُعيد الحساب فقط خلال نافذتي التحذير (22:00-23:00) والتأخر (23:00-05:00)
      // خارج النافذتين نحدّث الوقت فقط بدون إعادة حساب مكلفة
      // تنبيه: تغييرات البيانات (غرف/حجوزات) تُعيد الحساب دائماً بغض النظر عن الوقت
      final timer = Timer.periodic(const Duration(minutes: 1), (_) {
        lastTime = DateTime.now();
        final hour = lastTime.hour;
        if (hour >= 22 || hour < 5) {
          computeAndEmit();
        }
      });

      ref.onDispose(() {
        roomsSub.cancel();
        bookingsSub.cancel();
        timer.cancel();
        controller.close();
      });

      return controller.stream;
    });
// ══════════════════════════════════════════════════════════════════════════
//  ✅ P0: Riverpod .select() — مشتقات فائقة السرعة للهواتف الضعيفة
//
//  هذه البروفايدرات تستخدم .select() لمراقبة قيمة مُشتقّة فقط.
//  الميزة: لو تغيرت غرفة واحدة، الـ Dashboard الذي يشاهد العدد لا يعيد بناء نفسه.
// ══════════════════════════════════════════════════════════════════════════

/// عدد الغرف المشغولة — يُحدّث فقط عندما يتغير العدد (وليس عند تغيير حالات فردية)
final occupiedRoomsCountProvider = Provider<int>((ref) {
  return ref.watch(
    roomsWithPaymentStatusProvider.select(
      (rooms) =>
          rooms.valueOrNull?.where((r) => r.hasActiveBooking).length ?? 0,
    ),
  );
});

/// عدد الغرف المتاحة — يُحدّث فقط عندما يتغير العدد
final availableRoomsCountProvider = Provider<int>((ref) {
  return ref.watch(
    roomsWithPaymentStatusProvider.select(
      (rooms) =>
          rooms.valueOrNull
              ?.where(
                (r) =>
                    !r.hasActiveBooking &&
                    !StatusUtils.isUnderMaintenance(r.room.status),
              )
              .length ??
          0,
    ),
  );
});

/// عدد الغرف المتأخرة السداد — يُحدّث فقط عندما يتغير العدد
final overdueRoomsCountProvider = Provider<int>((ref) {
  return ref.watch(
    roomsWithPaymentStatusProvider.select(
      (rooms) =>
          rooms.valueOrNull?.where((r) => r.isPaymentOverdue).length ?? 0,
    ),
  );
});

/// ✅ عدد الغرف في مرحلة التحذير المبكر (22:00-23:00 + رصيد متبقي)
/// في هذه المرحلة يظهر مؤشر برتقالي جزئي على الزر للتنبيه.
final latePaymentRoomsCountProvider = Provider<int>((ref) {
  return ref.watch(
    roomsWithPaymentStatusProvider.select(
      (rooms) => rooms.valueOrNull?.where((r) => r.isLatePayment).length ?? 0,
    ),
  );
});

/// عدد الغرف تحت الصيانة — يُحدّث فقط عندما يتغير العدد
/// ✅ استخدام StatusUtils.isUnderMaintenance (DRY) — كان قبل ذلك يفحص
/// 'صيانة' فقط بدون 'maintenance'، فكانت الغرف الإنجليزية لا تُحسب!
final maintenanceRoomsCountProvider = Provider<int>((ref) {
  return ref.watch(
    roomsWithPaymentStatusProvider.select(
      (rooms) =>
          rooms.valueOrNull
              ?.where((r) => StatusUtils.isUnderMaintenance(r.room.status))
              .length ??
          0,
    ),
  );
});
