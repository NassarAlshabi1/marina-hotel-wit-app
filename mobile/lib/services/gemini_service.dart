import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:uuid/uuid.dart';
import 'local_db.dart';
import 'remote_config_service.dart';
import 'price_adjustment_service.dart';
import 'booking_derived_fields_service.dart';

// ═══════════════════════════════════════════════════════════════
//  أوامر AI
// ═══════════════════════════════════════════════════════════════

sealed class AiCommand {
  final String description;
  const AiCommand({required this.description});
}

/// أمر استعلام فقط — لا يحتاج تأكيد
class AiQueryCommand extends AiCommand {
  const AiQueryCommand({required super.description});
}

/// تغيير سعر غرفة (مع إعادة حساب الحجوزات النشطة)
class AiUpdateRoomPriceCommand extends AiCommand {
  final String roomNumber;
  final double newPrice;
  final String? reason;
  const AiUpdateRoomPriceCommand({
    required this.roomNumber,
    required this.newPrice,
    this.reason,
    required super.description,
  });
}

/// تخفيض/زيادة سعر بنسبة لجميع غرف نوع معين
/// مثال: زيادة 10% على غرف doubles
/// مثال: تخفيض 5000 ريال من جميع الغرف
class AiBulkPriceAdjustCommand extends AiCommand {
  final String? roomType;
  final String mode; // 'percent_increase', 'percent_decrease', 'fixed_increase', 'fixed_decrease'
  final double value;
  final String? reason;
  const AiBulkPriceAdjustCommand({
    this.roomType,
    required this.mode,
    required this.value,
    this.reason,
    required super.description,
  });
}

/// تخفيض على حجز معين (خصم ليلي أو إجمالي)
class AiBookingDiscountCommand extends AiCommand {
  final String roomNumber;
  final double discountAmount;
  final String discountType; // 'per_night' أو 'total'
  final String? reason;
  const AiBookingDiscountCommand({
    required this.roomNumber,
    required this.discountAmount,
    required this.discountType,
    this.reason,
    required super.description,
  });
}

/// تغيير حالة غرفة
class AiUpdateRoomStatusCommand extends AiCommand {
  final String roomNumber;
  final String newStatus;
  const AiUpdateRoomStatusCommand({
    required this.roomNumber,
    required this.newStatus,
    required super.description,
  });
}

/// إضافة مصروف
class AiAddExpenseCommand extends AiCommand {
  final String expenseType;
  final String desc;
  final double amount;
  const AiAddExpenseCommand({
    required this.expenseType,
    required this.desc,
    required this.amount,
    required super.description,
  });
}

/// تسجيل دفعة لحجز
class AiAddPaymentCommand extends AiCommand {
  final String roomNumber;
  final double amount;
  final String? notes;
  const AiAddPaymentCommand({
    required this.roomNumber,
    required this.amount,
    this.notes,
    required super.description,
  });
}

/// إنهاء حجز (تسجيل خروج)
class AiCheckoutCommand extends AiCommand {
  final String roomNumber;
  const AiCheckoutCommand({
    required this.roomNumber,
    required super.description,
  });
}

/// تسوية دين
class AiSettleDebtCommand extends AiCommand {
  final int? debtId;
  final String guestName;
  final double amount;
  const AiSettleDebtCommand({
    this.debtId,
    required this.guestName,
    required this.amount,
    required super.description,
  });
}

/// إضافة حجز جديد
class AiAddBookingCommand extends AiCommand {
  final String roomNumber;
  final String guestName;
  final String guestPhone;
  final String guestNationality;
  final String checkinDate;
  final int expectedNights;
  final double? price;
  const AiAddBookingCommand({
    required this.roomNumber,
    required this.guestName,
    required this.guestPhone,
    required this.guestNationality,
    required this.checkinDate,
    required this.expectedNights,
    this.price,
    required super.description,
  });
}

/// تحديث بيانات ضيف
class AiUpdateBookingGuestCommand extends AiCommand {
  final String roomNumber;
  final String? guestName;
  final String? guestPhone;
  final int? extendNights;
  const AiUpdateBookingGuestCommand({
    required this.roomNumber,
    this.guestName,
    this.guestPhone,
    this.extendNights,
    required super.description,
  });
}

/// طلب تقرير (يُنفذ فوراً بدون تأكيد)
class AiReportCommand extends AiCommand {
  final String reportType; // daily, revenue, occupancy, debts, expenses, room_prices
  final String? dateFrom;
  final String? dateTo;
  const AiReportCommand({
    required this.reportType,
    this.dateFrom,
    this.dateTo,
    required super.description,
  });
}

/// لا يوجد إجراء مطلوب
class AiNoActionCommand extends AiCommand {
  const AiNoActionCommand({required super.description});
}

// ═══════════════════════════════════════════════════════════════
//  سجل تدقيق AI
// ═══════════════════════════════════════════════════════════════

class AiAuditLog {
  final String id;
  final String userMessage;
  final String aiResponse;
  final String? commandType;
  final String? commandDescription;
  final String executionResult;
  final DateTime timestamp;
  final bool wasConfirmed;

  const AiAuditLog({
    required this.id,
    required this.userMessage,
    required this.aiResponse,
    this.commandType,
    this.commandDescription,
    required this.executionResult,
    required this.timestamp,
    required this.wasConfirmed,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userMessage': userMessage,
        'aiResponse': aiResponse,
        'commandType': commandType,
        'commandDescription': commandDescription,
        'executionResult': executionResult,
        'timestamp': timestamp.toIso8601String(),
        'wasConfirmed': wasConfirmed,
      };
}

// ═══════════════════════════════════════════════════════════════
//  خدمة Gemini AI المحسّنة
// ═══════════════════════════════════════════════════════════════

class GeminiService {
  static final GeminiService _instance = GeminiService._();
  static GeminiService get instance => _instance;
  GeminiService._();

  static const _uuid = Uuid();
  static final _random = Random();
  GenerativeModel? _model;
  bool _isInitialized = false;

  /// مؤقت لمنع الإرسال السريع ( cooldown بين الطلبات )
  DateTime? _lastRequestTime;
  static const _minRequestInterval = Duration(seconds: 2);

  /// عدد المحاولات عند تجاوز الحد
  static const _maxRetries = 3;

  /// سجل التدقيق
  final List<AiAuditLog> _auditLog = [];
  List<AiAuditLog> get auditLog => List.unmodifiable(_auditLog);

  /// محادثة سابقة للمتابعة
  final List<Content> _conversationHistory = [];

  Future<void> initialize() async {
    if (_isInitialized) return;

    final apiKey = await RemoteConfigService.instance.geminiApiKey;
    if (apiKey.isEmpty) {
      debugPrint('⚠️ مفتاح Gemini API غير مضبوط');
      return;
    }

    _model = GenerativeModel(
      model: 'gemini-2.0-flash',
      apiKey: apiKey,
      systemInstruction: Content.system(_buildSystemPrompt()),
      generationConfig: GenerationConfig(
        temperature: 0.3,
        topP: 0.8,
        maxOutputTokens: 2048,
      ),
    );
    _isInitialized = true;
    debugPrint('✅ تم تهيئة Gemini AI');
  }

  void reset() {
    _model = null;
    _isInitialized = false;
    _conversationHistory.clear();
  }

  bool get isAvailable => _model != null && _isInitialized;

  /// مسح سجل المحادثة
  void clearHistory() {
    _conversationHistory.clear();
  }

  /// مسح سجل التدقيق
  void clearAuditLog() {
    _auditLog.clear();
  }

  // ───────────────────────────────────────────────────────────
  //  بناء سياق الفندق من قاعدة البيانات
  // ───────────────────────────────────────────────────────────

  Future<String> _buildHotelContext() async {
    final db = DatabaseManager.instance;
    final lines = <String>[];

    try {
      // --- إحصائيات سريعة ---
      final allRooms = await db.select(db.rooms).get();
      final available =
          allRooms.where((r) => r.status == 'available' && r.deletedAt == null).length;
      final occupied =
          allRooms.where((r) => r.status == 'occupied' && r.deletedAt == null).length;
      final maintenance =
          allRooms.where((r) => r.status == 'maintenance' && r.deletedAt == null).length;
      final cleaning =
          allRooms.where((r) => r.status == 'cleaning' && r.deletedAt == null).length;
      final total = allRooms.where((r) => r.deletedAt == null).length;
      lines.add('إجمالي الغرف: $total');
      lines.add(
          'شاغرة: $available | محجوزة: $occupied | تنظيف: $cleaning | صيانة: $maintenance');

      // --- الحجوزات النشطة ---
      final activeBookings = await (db.select(db.bookings)
            ..where((b) => b.status.equals('checked_in'))
            ..where((b) => b.deletedAt.isNull())
            ..orderBy([(b) => OrderingTerm.asc(b.roomNumber)]))
          .get();

      if (activeBookings.isNotEmpty) {
        lines.add('');
        lines.add('الحجوزات النشطة (${activeBookings.length}):');
        for (final b in activeBookings) {
          final paid = await (db.select(db.payments)
                ..where((p) => p.bookingLocalId.equals(b.id))
                ..where((p) => p.isVoided.equals(false)))
              .get();
          final totalPaid = paid.fold<double>(0, (s, p) => s + p.amount);
          final nights = b.expectedNights;
          final room =
              allRooms.where((r) => r.roomNumber == b.roomNumber).firstOrNull;
          final pricePerNight = room?.price ?? 0;
          final due = pricePerNight * nights;
          final remaining = due - totalPaid;

          lines.add(
            '- غرفة ${b.roomNumber}: ${b.guestName} | ${b.guestPhone} | $nights ليلة | مدفوع: ${totalPaid.toStringAsFixed(0)} | متبقي: ${remaining.toStringAsFixed(0)}',
          );
        }
      }

      // --- الغرف الشاغرة مع أسعارها ---
      final availableRooms = allRooms
          .where((r) => r.status == 'available' && r.deletedAt == null)
          .toList();
      if (availableRooms.isNotEmpty) {
        lines.add('');
        lines.add('الغرف الشاغرة:');
        for (final r in availableRooms) {
          lines.add(
              '- ${r.roomNumber}: ${r.type} - ${r.price.toStringAsFixed(0)} ريال');
        }
      }

      // --- الديون غير المسددة ---
      final debts = await (db.select(db.debts)
            ..where((d) => d.isSettled.equals(0))
            ..where((d) => d.deletedAt.isNull())
            ..orderBy([(d) => OrderingTerm.desc(d.dateRecorded)]))
          .get();
      if (debts.isNotEmpty) {
        lines.add('');
        lines.add('الديون غير المسددة (${debts.length}):');
        for (final d in debts.take(10)) {
          lines.add(
            '- ${d.guestName}: ${d.remainingAmount.toStringAsFixed(0)} ريال متبقي | سبب: ${d.debtReason}',
          );
        }
      }

      // --- إيرادات ومصروفات اليوم ---
      final today = DateTime.now().toIso8601String().split('T')[0];
      final todayPayments = await (db.select(db.payments)
            ..where((p) => p.paymentDate.equals(today))
            ..where((p) => p.isVoided.equals(false)))
          .get();
      final todayExpenses = await (db.select(db.expenses)
            ..where((e) => e.date.equals(today)))
          .get();
      final totalIncome = todayPayments.fold<double>(0, (s, p) => s + p.amount);
      final totalExpenses =
          todayExpenses.fold<double>(0, (s, e) => s + e.amount);

      lines.add('');
      lines.add('ملخص اليوم ($today):');
      lines.add('الإيرادات: ${totalIncome.toStringAsFixed(0)} ريال');
      lines.add('المصروفات: ${totalExpenses.toStringAsFixed(0)} ريال');
      lines.add('صافي: ${(totalIncome - totalExpenses).toStringAsFixed(0)} ريال');
    } catch (e) {
      debugPrint('⚠️ خطأ في بناء سياق الفندق: $e');
      lines.add('(تعذر تحميل بعض البيانات)');
    }

    return lines.join('\n');
  }

  // ───────────────────────────────────────────────────────────
  //  إرسال رسالة والحصول على رد + أمر
  // ───────────────────────────────────────────────────────────

  /// إرسال رسالة مع retry تلقائي عند تجاوز حد الطلبات
  Future<GeminiResponse> chat(String userMessage) async {
    if (!isAvailable) {
      return GeminiResponse(
        text: 'المساعد الذكي غير متاح. يرجى إدخال مفتاح Gemini API من الإعدادات.',
        command: null,
        requiresConfirmation: false,
      );
    }

    // ── Cooldown: منع الإرسال السريع ──
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _minRequestInterval) {
        final waitTime = _minRequestInterval - elapsed;
        debugPrint('⏳ انتظار ${waitTime.inSeconds + 1} ثانية قبل الطلب التالي...');
        await Future.delayed(waitTime);
      }
    }

    try {
      // بناء السياق الحي من قاعدة البيانات
      final hotelContext = await _buildHotelContext();

      // أخذ آخر 6 رسائل فقط (تقليل الـ tokens لتفادي تجاوز الحد)
      final recentHistory = _conversationHistory.length > 6
          ? _conversationHistory.sublist(_conversationHistory.length - 6)
          : List<Content>.from(_conversationHistory);

      // إنشاء جلسة محادثة مع التاريخ
      final chat = _model!.startChat(history: recentHistory);

      // إرسال رسالة المستخدم مع سياق الفندق الحي
      final fullMessage = 'بيانات الفندق الحالية:\n$hotelContext\n\n$userMessage';

      // ── إرسال مع Retry عند 429 ──
      final response = await _sendWithRetry(
        () => chat.sendMessage(Content.text(fullMessage)),
      );
      _lastRequestTime = DateTime.now();

      final responseText = response.text ?? '';

      // حفظ في سجل المحادثة بأدوار صحيحة
      _conversationHistory.add(Content.text(userMessage));
      _conversationHistory.add(Content.model([TextPart(responseText)]));

      // تحليل الأمر من الرد
      final command = _parseCommand(responseText);
      final cleanText = _stripJsonFromResponse(responseText);

      // التقارير تُنفذ فوراً بدون تأكيد
      if (command is AiReportCommand) {
        final reportResult = await executeCommand(command);
        return GeminiResponse(
          text: reportResult,
          command: null,
          requiresConfirmation: false,
        );
      }

      return GeminiResponse(
        text: cleanText,
        command: command,
        requiresConfirmation: command != null &&
            command is! AiQueryCommand &&
            command is! AiNoActionCommand,
      );
    } catch (e) {
      debugPrint('❌ خطأ في Gemini: $e');
      // مسح سجل المحادثة التالف عند خطأ الأدوار
      if (e.toString().contains('role') ||
          e.toString().contains('alternat')) {
        debugPrint('⚠️ مسح سجل المحادثة التالف');
        _conversationHistory.clear();
      }
      final errorMsg = e.toString();
      String friendlyMessage;
      if (errorMsg.contains('API key') || errorMsg.contains('401')) {
        friendlyMessage = 'مفتاح Gemini API غير صالح. يرجى إدخال مفتاح جديد من الإعدادات.';
      } else if (errorMsg.contains('429') ||
          errorMsg.contains('quota') ||
          errorMsg.contains('RESOURCE_EXHAUSTED')) {
        friendlyMessage = 'تم تجاوز حد الطلبات. انتظر 30 ثانية ثم حاول مجدداً.';
      } else if (errorMsg.contains('SAFETY')) {
        friendlyMessage = 'تم حظر الرد لأسباب أمنية. حاول صياغة السؤال بشكل مختلف.';
      } else {
        friendlyMessage = 'حدث خطأ أثناء معالجة طلبك. حاول مجدداً.';
      }
      return GeminiResponse(
        text: friendlyMessage,
        command: null,
        requiresConfirmation: false,
      );
    }
  }

  /// إعادة محاولة تلقائية مع exponential backoff عند تجاوز حد الطلبات
  Future<GenerateContentResponse> _sendWithRetry(
    Future<GenerateContentResponse> Function() sendFn,
  ) async {
    var delay = const Duration(seconds: 4);
    const maxDelay = Duration(seconds: 30);

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await sendFn();
      } catch (e) {
        final msg = e.toString();

        // إعادة محاولة فقط عند تجاوز حد الطلبات
        final isRateLimit = msg.contains('429') ||
            msg.contains('quota') ||
            msg.contains('RESOURCE_EXHAUSTED') ||
            msg.contains('rate');

        if (!isRateLimit || attempt >= _maxRetries) rethrow;

        // حساب jitter عشوائي لمنع thundering herd
        final jitterMs = (_random.nextDouble() * delay.inMilliseconds * 0.3).round();
        final actualDelay = Duration(milliseconds: delay.inMilliseconds + jitterMs);

        debugPrint('⚠️ تجاوز حد الطلبات — محاولة ${attempt + 1}/$_maxRetries، انتظار ${actualDelay.inSeconds} ثانية...');

        await Future.delayed(actualDelay);

        // مضاعفة التأخير للمحاولة التالية
        delay = Duration(
          milliseconds: (delay.inMilliseconds * 2).clamp(0, maxDelay.inMilliseconds),
        );
      }
    }
    throw StateError('Unreachable');
  }

  // ───────────────────────────────────────────────────────────
  //  تنفيذ الأمر على قاعدة البيانات + سجل التدقيق
  // ───────────────────────────────────────────────────────────

  Future<String> executeCommand(AiCommand command) async {
    final db = DatabaseManager.instance;
    final now = DateTime.now();

    try {
      String result;

      switch (command) {
        case AiQueryCommand():
          result = command.description;

        // ═══════════════════════════════════════════════════
        //  تغيير سعر غرفة — باستخدام PriceAdjustmentService
        //  (إعادة حساب حجوزات الغرفة النشطة تلقائياً)
        // ═══════════════════════════════════════════════════
        case AiUpdateRoomPriceCommand(
            :final roomNumber,
            :final newPrice,
            :final reason
          ):
          final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).get();
          if (rooms.isEmpty) {
            result = 'الغرفة $roomNumber غير موجودة';
            break;
          }
          final oldPrice = rooms.first.price;

          final priceResult = await PriceAdjustmentService(db)
              .applyRoomPriceChange(
            roomNumber: roomNumber,
            oldPrice: oldPrice,
            newPrice: newPrice,
            appliedBy: 'AI - Gemini',
            reason: reason,
          );

          if (!priceResult.success) {
            result = 'فشل تغيير السعر: ${priceResult.error}';
            break;
          }

          final details = <String>[];
          details.add(
              'سعر الغرفة $roomNumber: ${oldPrice.toStringAsFixed(0)} -> ${newPrice.toStringAsFixed(0)} ريال');
          if (priceResult.bookingsAffected > 0) {
            details.add('حجوزات متأثرة: ${priceResult.bookingsAffected}');
            details.add('ليالي مُعاد حسابها: ${priceResult.nightsUpdated}');
          }
          result = details.join(' | ');

        // ═══════════════════════════════════════════════════
        //  تخفيض/زيادة جماعية — لجميع الغرف أو نوع معين
        // ═══════════════════════════════════════════════════
        case AiBulkPriceAdjustCommand(
            :final roomType,
            :final mode,
            :final value,
            :final reason
          ):
          final allRooms = await db.select(db.rooms).get();
          var targetRooms = allRooms.where((r) => r.deletedAt == null).toList();
          if (roomType != null && roomType.isNotEmpty) {
            targetRooms =
                targetRooms.where((r) => r.type == roomType).toList();
          }
          if (targetRooms.isEmpty) {
            result = roomType != null
                ? 'لا توجد غرف من نوع "$roomType"'
                : 'لا توجد غرف';
            break;
          }

          int updated = 0;
          final details = <String>[];
          for (final room in targetRooms) {
            final oldPrice = room.price;
            double newPrice;
            switch (mode) {
              case 'percent_increase':
                newPrice = oldPrice * (1 + value / 100);
              case 'percent_decrease':
                newPrice = (oldPrice * (1 - value / 100))
                    .clamp(0.0, double.infinity);
              case 'fixed_increase':
                newPrice = oldPrice + value;
              case 'fixed_decrease':
                newPrice = (oldPrice - value).clamp(0.0, double.infinity);
              default:
                newPrice = oldPrice;
            }

            final priceResult = await PriceAdjustmentService(db)
                .applyRoomPriceChange(
              roomNumber: room.roomNumber,
              oldPrice: oldPrice,
              newPrice: newPrice,
              appliedBy: 'AI - Gemini',
              reason: reason ??
                  'تعديل جماعي: $mode ${value.toStringAsFixed(0)}',
            );
            if (priceResult.success) {
              updated++;
              details.add(
                  '${room.roomNumber}: ${oldPrice.toStringAsFixed(0)} -> ${newPrice.toStringAsFixed(0)}');
            }
          }

          final modeArabic = _modeToArabic(mode);
          result =
              'تم تعديل $updated غرفة ($modeArabic ${value.toStringAsFixed(0)})\n${details.take(5).join("\n")}${details.length > 5 ? "\n... و${details.length - 5} غرف أخرى" : ""}';

        // ═══════════════════════════════════════════════════
        //  تخفيض على حجز معين (خصم ليلي أو إجمالي)
        // ═══════════════════════════════════════════════════
        case AiBookingDiscountCommand(
            :final roomNumber,
            :final discountAmount,
            :final discountType,
          ):
          final bookings = await (db.select(db.bookings)
                ..where((b) => b.roomNumber.equals(roomNumber))
                ..where((b) => b.status.equals('checked_in'))
                ..where((b) => b.deletedAt.isNull()))
              .get();
          if (bookings.isEmpty) {
            result = 'لا يوجد حجز نشط للغرفة $roomNumber';
            break;
          }
          final booking = bookings.first;

          await (db.update(db.bookings)
            ..where((b) => b.id.equals(booking.id))).write(
            BookingsCompanion(
              discount: Value(discountAmount),
              discountType: Value(discountType),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );

          // إعادة حساب الليالي عبر BookingDerivedFieldsService
          try {
            await BookingDerivedFieldsService(db)
                .refreshForBookingId(booking.id, forceRebuild: true);
          } catch (e) {
            debugPrint('⚠️ خطأ في إعادة حساب الحجز: $e');
          }

          final typeLabel =
              discountType == 'per_night' ? 'لكل ليلة' : 'إجمالي';
          result =
              'تم تطبيق خصم ${discountAmount.toStringAsFixed(0)} ريال ($typeLabel) على حجز الغرفة $roomNumber - ${booking.guestName}';

        // ═══════════════════════════════════════════════════
        //  تغيير حالة غرفة
        // ═══════════════════════════════════════════════════
        case AiUpdateRoomStatusCommand(:final roomNumber, :final newStatus):
          final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).get();
          if (rooms.isEmpty) {
            result = 'الغرفة $roomNumber غير موجودة';
            break;
          }
          final oldStatus = rooms.first.status;
          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).write(
            RoomsCompanion(
              status: Value(newStatus),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          result =
              'تم تغيير حالة الغرفة $roomNumber من $oldStatus إلى $newStatus';

        // ═══════════════════════════════════════════════════
        //  إضافة مصروف
        // ═══════════════════════════════════════════════════
        case AiAddExpenseCommand(
            :final expenseType,
            :final desc,
            :final amount
          ):
          final uuid = _uuid.v4();
          await db.into(db.expenses).insert(
            ExpensesCompanion(
              expenseType: Value(expenseType),
              description: Value(desc),
              amount: Value(amount),
              date: Value(now.toIso8601String().split('T')[0]),
              localUuid: Value(uuid),
              createdAt: Value(now.millisecondsSinceEpoch),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              createdAtIso: Value(now.toIso8601String()),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          result = 'تم إضافة مصروف: $desc - ${amount.toStringAsFixed(0)} ريال';

        // ═══════════════════════════════════════════════════
        //  تسجيل دفعة
        // ═══════════════════════════════════════════════════
        case AiAddPaymentCommand(
            :final roomNumber,
            :final amount,
            :final notes
          ):
          final bookings = await (db.select(db.bookings)
            ..where((b) => b.roomNumber.equals(roomNumber))).get();
          final activeBooking =
              bookings.where((b) => b.status == 'checked_in').firstOrNull;
          if (activeBooking == null) {
            result = 'لا يوجد حجز نشط للغرفة $roomNumber';
            break;
          }

          final uuid = _uuid.v4();
          await db.into(db.payments).insert(
            PaymentsCompanion(
              bookingLocalId: Value(activeBooking.id),
              roomNumber: Value(roomNumber),
              amount: Value(amount),
              paymentDate: Value(now.toIso8601String().split('T')[0]),
              paymentMethod: Value('cash'),
              revenueType: Value('room_rent'),
              notes: Value(notes),
              localUuid: Value(uuid),
              createdAt: Value(now.millisecondsSinceEpoch),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              createdAtIso: Value(now.toIso8601String()),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          result =
              'تم تسجيل دفعة ${amount.toStringAsFixed(0)} ريال للغرفة $roomNumber';

        // ═══════════════════════════════════════════════════
        //  إنهاء حجز (تسجيل خروج)
        // ═══════════════════════════════════════════════════
        case AiCheckoutCommand(:final roomNumber):
          final bookings = await (db.select(db.bookings)
            ..where((b) => b.roomNumber.equals(roomNumber))).get();
          final activeBooking =
              bookings.where((b) => b.status == 'checked_in').firstOrNull;
          if (activeBooking == null) {
            result = 'لا يوجد حجز نشط للغرفة $roomNumber';
            break;
          }

          final today = now.toIso8601String().split('T')[0];

          await (db.update(db.bookings)
            ..where((b) => b.id.equals(activeBooking.id))).write(
            BookingsCompanion(
              status: Value('checked_out'),
              actualCheckout: Value(today),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );

          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).write(
            RoomsCompanion(
              status: Value('available'),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          result =
              'تم إنهاء حجز الغرفة $roomNumber وتسجيل خروج الضيف ${activeBooking.guestName}';

        // ═══════════════════════════════════════════════════
        //  تسوية دين
        // ═══════════════════════════════════════════════════
        case AiSettleDebtCommand(
            :final debtId,
            :final guestName,
            :final amount
          ):
          Debt? targetDebt;
          if (debtId != null) {
            targetDebt = await (db.select(db.debts)
              ..where((d) => d.id.equals(debtId))).getSingleOrNull();
          } else {
            final debts = await (db.select(db.debts)
                  ..where((d) =>
                      d.isSettled.equals(0) & d.guestName.contains(guestName)))
                .get();
            targetDebt = debts.firstOrNull;
          }

          if (targetDebt == null) {
            result = 'لم يتم العثور على دين مسجل للضيف $guestName';
            break;
          }

          final newPaid = targetDebt.paidAmount + amount;
          final isFullySettled = newPaid >= targetDebt.totalAmount;

          await (db.update(db.debts)
            ..where((d) => d.id.equals(targetDebt!.id))).write(
            DebtsCompanion(
              paidAmount: Value(newPaid),
              remainingAmount: Value(
                (targetDebt.totalAmount - newPaid)
                    .clamp(0.0, double.infinity),
              ),
              isSettled: Value(isFullySettled ? 1 : 0),
              paymentDate: Value(now.toIso8601String().split('T')[0]),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          result = isFullySettled
              ? 'تم تسوية دين $guestName بالكامل (${targetDebt.totalAmount.toStringAsFixed(0)} ريال)'
              : 'تم تسجيل دفعة ${amount.toStringAsFixed(0)} ريال من دين $guestName. المتبقي: ${(targetDebt.totalAmount - newPaid).toStringAsFixed(0)} ريال';

        // ═══════════════════════════════════════════════════
        //  إضافة حجز جديد
        // ═══════════════════════════════════════════════════
        case AiAddBookingCommand(
            :final roomNumber,
            :final guestName,
            :final guestPhone,
            :final guestNationality,
            :final checkinDate,
            :final expectedNights,
            :final price
          ):
          final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).get();
          if (rooms.isEmpty) {
            result = 'الغرفة $roomNumber غير موجودة';
            break;
          }
          if (rooms.first.status != 'available') {
            result =
                'الغرفة $roomNumber غير متاحة حالياً. حالتها: ${rooms.first.status}';
            break;
          }

          final roomPrice = price ?? rooms.first.price;
          final uuid = _uuid.v4();

          await db.into(db.bookings).insert(
            BookingsCompanion(
              roomNumber: Value(roomNumber),
              guestName: Value(guestName),
              guestPhone: Value(guestPhone),
              guestNationality: Value(guestNationality),
              checkinDate: Value(checkinDate),
              status: Value('checked_in'),
              expectedNights: Value(expectedNights),
              calculatedNights: Value(expectedNights),
              discount: Value(0),
              localUuid: Value(uuid),
              createdAt: Value(now.millisecondsSinceEpoch),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              createdAtIso: Value(now.toIso8601String()),
              updatedAtIso: Value(now.toIso8601String()),
              hotelDayCheckin: Value(checkinDate),
            ),
          );

          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).write(
            RoomsCompanion(
              status: Value('occupied'),
              price: Value(roomPrice),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );

          result =
              'تم حجز الغرفة $roomNumber للضيف $guestName لمدة $expectedNights ليلة (${roomPrice.toStringAsFixed(0)} ريال/ليلة)';

        // ═══════════════════════════════════════════════════
        //  تحديث بيانات ضيف
        // ═══════════════════════════════════════════════════
        case AiUpdateBookingGuestCommand(
            :final roomNumber,
            :final guestName,
            :final guestPhone,
            :final extendNights
          ):
          final bookings = await (db.select(db.bookings)
            ..where((b) => b.roomNumber.equals(roomNumber))).get();
          final activeBooking =
              bookings.where((b) => b.status == 'checked_in').firstOrNull;
          if (activeBooking == null) {
            result = 'لا يوجد حجز نشط للغرفة $roomNumber';
            break;
          }

          final updates = <String, dynamic>{};

          if (guestName != null && guestName.isNotEmpty) {
            updates['اسم الضيف'] = guestName;
          }
          if (guestPhone != null && guestPhone.isNotEmpty) {
            updates['رقم الهاتف'] = guestPhone;
          }
          if (extendNights != null && extendNights > 0) {
            updates['عدد الليالي'] =
                '${activeBooking.expectedNights} -> ${activeBooking.expectedNights + extendNights}';
          }

          if (updates.isEmpty) {
            result = 'لم يتم تحديد أي تغيير';
            break;
          }

          await (db.update(db.bookings)
            ..where((b) => b.id.equals(activeBooking.id))).write(
            BookingsCompanion(
              guestName: guestName != null && guestName.isNotEmpty
                  ? Value(guestName)
                  : const Value.absent(),
              guestPhone: guestPhone != null && guestPhone.isNotEmpty
                  ? Value(guestPhone)
                  : const Value.absent(),
              expectedNights: extendNights != null
                  ? Value(activeBooking.expectedNights + extendNights)
                  : const Value.absent(),
              calculatedNights: extendNights != null
                  ? Value(activeBooking.calculatedNights + extendNights)
                  : const Value.absent(),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );

          final changes =
              updates.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
          result = 'تم تحديث بيانات الغرفة $roomNumber: $changes';

        // ═══════════════════════════════════════════════════
        //  التقارير
        // ═══════════════════════════════════════════════════
        case AiReportCommand(:final reportType):
          result = await _generateReport(
              db, reportType, command.dateFrom, command.dateTo);

        case AiNoActionCommand():
          result = command.description;
      }

      return '✅ $result';
    } catch (e) {
      debugPrint('❌ خطأ في تنفيذ الأمر: $e');
      return '❌ فشل تنفيذ الأمر: $e';
    }
  }

  /// تسجيل في سجل التدقيق
  void logToAudit({
    required String userMessage,
    required String aiResponse,
    AiCommand? command,
    required String executionResult,
    required bool wasConfirmed,
  }) {
    final auditNow = DateTime.now();
    _auditLog.add(AiAuditLog(
      id: auditNow.millisecondsSinceEpoch.toString(),
      userMessage: userMessage,
      aiResponse: aiResponse,
      commandType: command?.runtimeType.toString(),
      commandDescription: command?.description,
      executionResult: executionResult,
      timestamp: auditNow,
      wasConfirmed: wasConfirmed,
    ));
  }

  // ───────────────────────────────────────────────────────────
  //  System Prompt
  // ───────────────────────────────────────────────────────────

  String _buildSystemPrompt() {
    return '''أنت مساعد ذكي لنظام إدارة فندق Marina. تتحدث باللغة العربية فقط.

مهمتك: فهم طلبات المستخدم باللغة العربية الطبيعية والرد بمعلومات مفيدة أو تنفيذ أوامر على النظام.

قواعد مهمة:
- كن مختصراً ومفيداً — لا تزد على 3 أسطر إلا عند الحاجة
- استخدم البيانات الحالية المقدمة لك للإجابة بدقة
- إذا طلب المستخدم تعديل بيانات، أجب بالشرح المختصر ثم أضف JSON للأمر في نهاية رسالتك
- لا تنفذ أوامر خطيرة (تعديل/حذف) بدون تأكيد المستخدم
- الصيغة: ردك المكتوب أولاً، ثم JSON للأمر في سطر منفصل
- لا تضع JSON بين ``` فقط أرسله مباشرة
- أوامر التقارير تُنفذ فوراً بدون تأكيد

صيغ JSON للأوامر المدعومة:

1. تغيير سعر غرفة (مع إعادة حساب الحجوزات النشطة تلقائياً):
{"action": "update_room_price", "room_number": "101", "new_price": 50000, "reason": "زيادة بسبب الموسم"}

2. تخفيض/زيادة جماعية لجميع الغرف أو نوع معين:
{"action": "bulk_price_adjust", "room_type": "double", "mode": "percent_increase", "value": 10, "reason": "زيادة موسمية"}
- mode: percent_increase, percent_decrease, fixed_increase, fixed_decrease
- room_type اختياري (إذا لم يُحدد يُطبق على جميع الغرف)
- أمثلة: "زِد جميع الأسعار 10%" | "خفّض غرف doubles 5000 ريال" | "زِد سعر الغرف 20%"

3. تخفيض على حجز معين (خصم ليلي أو إجمالي):
{"action": "booking_discount", "room_number": "101", "discount_amount": 5000, "discount_type": "per_night", "reason": "خصم خاص"}
- discount_type: per_night (لكل ليلة) أو total (إجمالي)
- أمثلة: "خفّض 5000 لكل ليلة للغرفة 101" | "خصم 10000 إجمالي على حجز الغرفة 202"

4. تغيير حالة غرفة:
{"action": "update_room_status", "room_number": "101", "new_status": "available"}

5. إضافة مصروف:
{"action": "add_expense", "expense_type": "صيانة", "description": "صيانة مكيف", "amount": 20000}

6. تسجيل دفعة:
{"action": "add_payment", "room_number": "101", "amount": 50000, "notes": "دفعة نقدية"}

7. إنهاء حجز (تسجيل خروج):
{"action": "checkout", "room_number": "101"}

8. تسوية دين:
{"action": "settle_debt", "guest_name": "أحمد", "amount": 30000}

9. إضافة حجز جديد:
{"action": "add_booking", "room_number": "101", "guest_name": "أحمد محمد", "guest_phone": "777123456", "guest_nationality": "يمني", "checkin_date": "2025-01-15", "expected_nights": 2}

10. تحديث بيانات ضيف:
{"action": "update_booking_guest", "room_number": "101", "guest_name": "الاسم الجديد", "extend_nights": 1}

11. طلب تقرير (يُنفذ فوراً بدون تأكيد):
{"action": "report", "report_type": "daily"}
- report_type: daily (يومي), revenue (إيرادات), occupancy (إشغال), debts (ديون), expenses (مصروفات), room_prices (أسعار الغرف)
- أمثلة: "أعطني تقرير اليوم" | "كم الإيرادات هذا الشهر" | "كم نسبة الإشغال" | "تقرير الديون"

حالات الغرف: available, occupied, cleaning, maintenance, reserved
أنواع المصروفات: صيانة, طعام, كهرباء, ماء, تنظيف, نقل, أخرى
أنواع الغرف: single, double, triple, suite, family
المبالغ بالريال اليمني
الأرقام بدون فواصل (50000 وليس 50,000)
تاريخ اليوم الحالي: ${DateTime.now().toIso8601String().split('T')[0]}''';
  }

  // ───────────────────────────────────────────────────────────
  //  تحليل JSON من رد Gemini
  // ───────────────────────────────────────────────────────────

  AiCommand? _parseCommand(String text) {
    try {
      // البحث عن JSON في النص — يدعم JSON متعدد الأسطر
      final jsonPattern = RegExp(r'\{[^{}]*\}', dotAll: true);
      final match = jsonPattern.firstMatch(text);
      if (match == null) return null;

      final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final action = json['action'] as String?;

      switch (action) {
        case 'update_room_price':
          return AiUpdateRoomPriceCommand(
            roomNumber: json['room_number'] as String? ?? '',
            newPrice: (json['new_price'] as num).toDouble(),
            reason: json['reason'] as String?,
            description:
                'تغيير سعر الغرفة ${json['room_number']} إلى ${json['new_price']} (مع إعادة حساب الحجوزات)',
          );

        case 'bulk_price_adjust':
          return AiBulkPriceAdjustCommand(
            roomType: json['room_type'] as String?,
            mode: json['mode'] as String? ?? 'percent_increase',
            value: (json['value'] as num).toDouble(),
            reason: json['reason'] as String?,
            description:
                'تعديل جماعي: ${json['mode']} ${json['value']}${json['room_type'] != null ? ' على غرف ${json['room_type']}' : ''}',
          );

        case 'booking_discount':
          return AiBookingDiscountCommand(
            roomNumber: json['room_number'] as String? ?? '',
            discountAmount: (json['discount_amount'] as num).toDouble(),
            discountType: json['discount_type'] as String? ?? 'per_night',
            reason: json['reason'] as String?,
            description:
                'خصم ${(json['discount_amount'] as num).toDouble().toStringAsFixed(0)} (${json['discount_type']}) على الغرفة ${json['room_number']}',
          );

        case 'update_room_status':
          return AiUpdateRoomStatusCommand(
            roomNumber: json['room_number'] as String? ?? '',
            newStatus: json['new_status'] as String? ?? '',
            description:
                'تغيير حالة الغرفة ${json['room_number']} إلى ${json['new_status']}',
          );

        case 'add_expense':
          return AiAddExpenseCommand(
            expenseType: json['expense_type'] as String? ?? 'أخرى',
            desc: json['description'] as String? ?? '',
            amount: (json['amount'] as num).toDouble(),
            description:
                'إضافة مصروف: ${json['description']} - ${json['amount']}',
          );

        case 'add_payment':
          return AiAddPaymentCommand(
            roomNumber: json['room_number'] as String? ?? '',
            amount: (json['amount'] as num).toDouble(),
            notes: json['notes'] as String?,
            description:
                'تسجيل دفعة ${json['amount']} للغرفة ${json['room_number']}',
          );

        case 'checkout':
          return AiCheckoutCommand(
            roomNumber: json['room_number'] as String? ?? '',
            description: 'إنهاء حجز الغرفة ${json['room_number']}',
          );

        case 'settle_debt':
          return AiSettleDebtCommand(
            debtId: json['debt_id'] as int?,
            guestName: json['guest_name'] as String? ?? '',
            amount: (json['amount'] as num).toDouble(),
            description:
                'تسوية دين ${json['guest_name']}: ${json['amount']} ريال',
          );

        case 'add_booking':
          return AiAddBookingCommand(
            roomNumber: json['room_number'] as String? ?? '',
            guestName: json['guest_name'] as String? ?? '',
            guestPhone: json['guest_phone'] as String? ?? '',
            guestNationality:
                json['guest_nationality'] as String? ?? 'يمني',
            checkinDate: json['checkin_date'] as String? ??
                DateTime.now().toIso8601String().split('T')[0],
            expectedNights: json['expected_nights'] as int? ?? 1,
            price: json['price'] != null
                ? (json['price'] as num).toDouble()
                : null,
            description:
                'حجز غرفة ${json['room_number']} للضيف ${json['guest_name']}',
          );

        case 'update_booking_guest':
          return AiUpdateBookingGuestCommand(
            roomNumber: json['room_number'] as String? ?? '',
            guestName: json['guest_name'] as String?,
            guestPhone: json['guest_phone'] as String?,
            extendNights: json['extend_nights'] as int?,
            description:
                'تحديث بيانات الغرفة ${json['room_number']}',
          );

        case 'report':
          return AiReportCommand(
            reportType: json['report_type'] as String? ?? 'daily',
            dateFrom: json['date_from'] as String?,
            dateTo: json['date_to'] as String?,
            description: 'تقرير ${json['report_type']}',
          );

        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  String _stripJsonFromResponse(String text) {
    return text
        .replaceAll(RegExp(r'\{[^{}]*\}', dotAll: true), '')
        .replaceAll(RegExp(r'```json?\n?'), '')
        .replaceAll(RegExp(r'```'), '')
        .trim();
  }

  // ───────────────────────────────────────────────────────────
  //  توليد التقارير من قاعدة البيانات
  // ───────────────────────────────────────────────────────────

  Future<String> _generateReport(
    AppDatabase db,
    String reportType,
    String? dateFrom,
    String? dateTo,
  ) async {
    try {
      switch (reportType) {
        case 'daily':
          return await _generateDailyReport(db);
        case 'revenue':
          return await _generateRevenueReport(db, dateFrom, dateTo);
        case 'occupancy':
          return await _generateOccupancyReport(db);
        case 'debts':
          return await _generateDebtsReport(db);
        case 'expenses':
          return await _generateExpensesReport(db, dateFrom, dateTo);
        case 'room_prices':
          return await _generateRoomPricesReport(db);
        default:
          return 'نوع التقرير غير معروف: $reportType';
      }
    } catch (e) {
      debugPrint('خطأ في توليد التقرير: $e');
      return 'فشل توليد التقرير: $e';
    }
  }

  Future<String> _generateDailyReport(AppDatabase db) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final lines = <String>['📊 تقرير يومي - $today', ''];

    // الإيرادات
    final todayPayments = await (db.select(db.payments)
          ..where((p) => p.paymentDate.equals(today))
          ..where((p) => p.isVoided.equals(false)))
        .get();
    final totalIncome = todayPayments.fold<double>(0, (s, p) => s + p.amount);

    // المصروفات
    final todayExpenses = await (db.select(db.expenses)
          ..where((e) => e.date.equals(today)))
        .get();
    final totalExpenses =
        todayExpenses.fold<double>(0, (s, e) => s + e.amount);

    // الغرف
    final allRooms = await db.select(db.rooms).get();
    final available =
        allRooms.where((r) => r.status == 'available' && r.deletedAt == null).length;
    final occupied =
        allRooms.where((r) => r.status == 'occupied' && r.deletedAt == null).length;
    final total = allRooms.where((r) => r.deletedAt == null).length;
    final occRate =
        total > 0 ? (occupied * 100 / total).toStringAsFixed(1) : '0';

    lines.add(
        '💰 الإيرادات: ${totalIncome.toStringAsFixed(0)} ريال (${todayPayments.length} دفعة)');
    lines.add(
        '📉 المصروفات: ${totalExpenses.toStringAsFixed(0)} ريال (${todayExpenses.length} مصروف)');
    lines.add(
        '📊 صافي الربح: ${(totalIncome - totalExpenses).toStringAsFixed(0)} ريال');
    lines.add('');
    lines.add(
        '🏠 إجمالي الغرف: $total | شاغرة: $available | مشغولة: $occupied');
    lines.add('📈 نسبة الإشغال: $occRate%');

    // حجوزات جديدة اليوم
    final todayBookings = await (db.select(db.bookings)
          ..where((b) => b.checkinDate.equals(today))
          ..where((b) => b.deletedAt.isNull()))
        .get();
    lines.add('📋 حجوزات جديدة اليوم: ${todayBookings.length}');

    // خروج اليوم
    final todayCheckouts = await (db.select(db.bookings)
          ..where((b) => b.actualCheckout.equals(today))
          ..where((b) => b.deletedAt.isNull()))
        .get();
    lines.add('🚪 تسجيلات خروج اليوم: ${todayCheckouts.length}');

    return lines.join('\n');
  }

  Future<String> _generateRevenueReport(
      AppDatabase db, String? from, String? to) async {
    final now = DateTime.now();
    final dateFrom =
        from ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final dateTo = to ?? now.toIso8601String().split('T')[0];

    final lines =
        <String>['💰 تقرير الإيرادات: $dateFrom إلى $dateTo', ''];

    final payments = await (db.select(db.payments)
          ..where((p) => p.paymentDate.isBiggerOrEqualValue(dateFrom))
          ..where((p) => p.paymentDate.isSmallerOrEqualValue(dateTo))
          ..where((p) => p.isVoided.equals(false)))
        .get();

    final totalIncome =
        payments.fold<double>(0, (s, p) => s + p.amount);

    // تجميع حسب طريقة الدفع
    final byMethod = <String, double>{};
    for (final p in payments) {
      byMethod[p.paymentMethod] =
          (byMethod[p.paymentMethod] ?? 0) + p.amount;
    }

    // تجميع حسب النوع
    final byType = <String, double>{};
    for (final p in payments) {
      byType[p.revenueType] = (byType[p.revenueType] ?? 0) + p.amount;
    }

    lines.add(
        'إجمالي الإيرادات: ${totalIncome.toStringAsFixed(0)} ريال (${payments.length} دفعة)');
    lines.add('');
    lines.add('حسب طريقة الدفع:');
    for (final entry in byMethod.entries) {
      lines.add('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
    }
    lines.add('');
    lines.add('حسب النوع:');
    for (final entry in byType.entries) {
      lines.add('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
    }

    return lines.join('\n');
  }

  Future<String> _generateOccupancyReport(AppDatabase db) async {
    final lines = <String>['📈 تقرير نسبة الإشغال', ''];

    final allRooms = await db.select(db.rooms).get();
    final activeRooms = allRooms.where((r) => r.deletedAt == null).toList();
    final total = activeRooms.length;

    if (total == 0) return 'لا توجد غرف مسجلة';

    final occupied =
        activeRooms.where((r) => r.status == 'occupied').length;
    final available =
        activeRooms.where((r) => r.status == 'available').length;
    final cleaning =
        activeRooms.where((r) => r.status == 'cleaning').length;
    final maintenance =
        activeRooms.where((r) => r.status == 'maintenance').length;
    final occRate = (occupied * 100 / total).toStringAsFixed(1);

    lines.add('إجمالي الغرف: $total');
    lines.add(
        'مشغولة: $occupied (${(occupied * 100 / total).toStringAsFixed(1)}%)');
    lines.add(
        'شاغرة: $available (${(available * 100 / total).toStringAsFixed(1)}%)');
    lines.add(
        'تنظيف: $cleaning (${(cleaning * 100 / total).toStringAsFixed(1)}%)');
    lines.add(
        'صيانة: $maintenance (${(maintenance * 100 / total).toStringAsFixed(1)}%)');
    lines.add('');
    lines.add('نسبة الإشغال: $occRate%');

    // تجميع حسب نوع الغرفة
    final byType = <String, int>{};
    final occupiedByType = <String, int>{};
    for (final r in activeRooms) {
      byType[r.type] = (byType[r.type] ?? 0) + 1;
      if (r.status == 'occupied') {
        occupiedByType[r.type] = (occupiedByType[r.type] ?? 0) + 1;
      }
    }
    lines.add('');
    lines.add('حسب نوع الغرفة:');
    for (final entry in byType.entries) {
      final occ = occupiedByType[entry.key] ?? 0;
      final rate = (occ * 100 / entry.value).toStringAsFixed(0);
      lines.add('  ${entry.key}: $occ/${entry.value} ($rate%)');
    }

    return lines.join('\n');
  }

  Future<String> _generateDebtsReport(AppDatabase db) async {
    final lines = <String>['📋 تقرير الديون غير المسددة', ''];

    final debts = await (db.select(db.debts)
          ..where((d) => d.isSettled.equals(0))
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([(d) => OrderingTerm.desc(d.remainingAmount)]))
        .get();

    if (debts.isEmpty) {
      lines.add('لا توجد ديون غير مسددة.');
      return lines.join('\n');
    }

    final totalDebt =
        debts.fold<double>(0, (s, d) => s + d.remainingAmount);
    final totalPaid =
        debts.fold<double>(0, (s, d) => s + d.paidAmount);

    lines.add('عدد الديون: ${debts.length}');
    lines.add(
        'إجمالي المبالغ المتبقية: ${totalDebt.toStringAsFixed(0)} ريال');
    lines.add(
        'إجمالي المدفوع: ${totalPaid.toStringAsFixed(0)} ريال');
    lines.add('');
    lines.add('تفاصيل (الأعلى أولاً):');
    for (final d in debts.take(15)) {
      lines.add(
        '  ${d.guestName}: ${d.remainingAmount.toStringAsFixed(0)} ريال متبقي | من أصل ${d.totalAmount.toStringAsFixed(0)} | ${d.debtReason}',
      );
    }
    if (debts.length > 15) {
      lines.add('  ... و${debts.length - 15} ديون أخرى');
    }

    return lines.join('\n');
  }

  Future<String> _generateExpensesReport(
      AppDatabase db, String? from, String? to) async {
    final now = DateTime.now();
    final dateFrom =
        from ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final dateTo = to ?? now.toIso8601String().split('T')[0];

    final lines =
        <String>['📉 تقرير المصروفات: $dateFrom إلى $dateTo', ''];

    final expenses = await (db.select(db.expenses)
          ..where((e) => e.date.isBiggerOrEqualValue(dateFrom))
          ..where((e) => e.date.isSmallerOrEqualValue(dateTo)))
        .get();

    if (expenses.isEmpty) {
      lines.add('لا توجد مصروفات في الفترة المحددة.');
      return lines.join('\n');
    }

    final totalExpenses =
        expenses.fold<double>(0, (s, e) => s + e.amount);

    // تجميع حسب النوع
    final byType = <String, double>{};
    for (final e in expenses) {
      byType[e.expenseType] = (byType[e.expenseType] ?? 0) + e.amount;
    }

    lines.add(
        'إجمالي المصروفات: ${totalExpenses.toStringAsFixed(0)} ريال (${expenses.length} مصروف)');
    lines.add('');
    lines.add('حسب النوع:');
    final sorted = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      final pct = (entry.value * 100 / totalExpenses).toStringAsFixed(1);
      lines.add('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال ($pct%)');
    }

    return lines.join('\n');
  }

  Future<String> _generateRoomPricesReport(AppDatabase db) async {
    final lines = <String>['🏨 تقرير أسعار الغرف', ''];

    final allRooms = await db.select(db.rooms).get();
    final activeRooms = allRooms.where((r) => r.deletedAt == null).toList();

    if (activeRooms.isEmpty) {
      lines.add('لا توجد غرف مسجلة.');
      return lines.join('\n');
    }

    // تجميع حسب النوع
    final byType = <String, List<Room>>{};
    for (final r in activeRooms) {
      byType.putIfAbsent(r.type, () => []).add(r);
    }

    double minPrice = double.infinity;
    double maxPrice = 0;
    double totalPrice = 0;

    for (final r in activeRooms) {
      if (r.price < minPrice) minPrice = r.price;
      if (r.price > maxPrice) maxPrice = r.price;
      totalPrice += r.price;
    }
    final avgPrice =
        activeRooms.isNotEmpty ? totalPrice / activeRooms.length : 0;

    lines.add('إجمالي الغرف: ${activeRooms.length}');
    lines.add('أقل سعر: ${minPrice.toStringAsFixed(0)} ريال');
    lines.add('أعلى سعر: ${maxPrice.toStringAsFixed(0)} ريال');
    lines.add('متوسط السعر: ${avgPrice.toStringAsFixed(0)} ريال');
    lines.add('');

    for (final entry in byType.entries) {
      final rooms = entry.value;
      final typeTotal = rooms.fold<double>(0, (s, r) => s + r.price);
      final typeAvg = rooms.isNotEmpty ? typeTotal / rooms.length : 0;
      lines.add(
          '${entry.key} (${rooms.length} غرف — متوسط ${typeAvg.toStringAsFixed(0)}):');
      for (final r
          in rooms..sort((a, b) => a.roomNumber.compareTo(b.roomNumber))) {
        final statusEmoji = r.status == 'available'
            ? '✅'
            : (r.status == 'occupied' ? '🔴' : '⚪');
        lines.add(
            '  $statusEmoji ${r.roomNumber}: ${r.price.toStringAsFixed(0)} ريال (${r.status})');
      }
      lines.add('');
    }

    return lines.join('\n');
  }

  String _modeToArabic(String mode) {
    switch (mode) {
      case 'percent_increase':
        return 'زيادة بنسبة';
      case 'percent_decrease':
        return 'تخفيض بنسبة';
      case 'fixed_increase':
        return 'زيادة قدرها';
      case 'fixed_decrease':
        return 'تخفيض قدره';
      default:
        return mode;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  نماذج البيانات
// ═══════════════════════════════════════════════════════════════

class GeminiResponse {
  final String text;
  final AiCommand? command;
  final bool requiresConfirmation;

  const GeminiResponse({
    required this.text,
    this.command,
    this.requiresConfirmation = false,
  });
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final AiCommand? pendingCommand;
  final DateTime timestamp;
  final bool isExecuted;
  final String? executionResult;

  ChatMessage({
    required this.id,
    required this.text,
    this.isUser = false,
    this.pendingCommand,
    DateTime? timestamp,
    this.isExecuted = false,
    this.executionResult,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    AiCommand? pendingCommand,
    bool? isExecuted,
    String? executionResult,
  }) {
    return ChatMessage(
      id: id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      pendingCommand: pendingCommand ?? this.pendingCommand,
      timestamp: timestamp,
      isExecuted: isExecuted ?? this.isExecuted,
      executionResult: executionResult ?? this.executionResult,
    );
  }
}
