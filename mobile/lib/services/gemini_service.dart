import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'local_db.dart';
import 'remote_config_service.dart';

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

/// تغيير سعر غرفة
class AiUpdateRoomPriceCommand extends AiCommand {
  final String roomNumber;
  final double newPrice;
  const AiUpdateRoomPriceCommand({
    required this.roomNumber,
    required this.newPrice,
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

  GenerativeModel? _model;
  bool _isInitialized = false;

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
      final available = allRooms.where((r) => r.status == 'available').length;
      final occupied = allRooms.where((r) => r.status == 'occupied').length;
      final maintenance = allRooms.where((r) => r.status == 'maintenance').length;
      final cleaning = allRooms.where((r) => r.status == 'cleaning').length;
      lines.add('إجمالي الغرف: ${allRooms.length}');
      lines.add('شاغرة: $available | محجوزة: $occupied | تنظيف: $cleaning | صيانة: $maintenance');

      // --- الحجوزات النشطة ---
      final activeBookings = await (db.select(db.bookings)
            ..where((b) => b.status.equals('checked_in'))
            ..orderBy([(b) => OrderingTerm.asc(b.roomNumber)]))
          .get();

      if (activeBookings.isNotEmpty) {
        lines.add('');
        lines.add('الحجوزات النشطة (${activeBookings.length}):');
        for (final b in activeBookings) {
          final paid = await (db.select(db.payments)
                ..where((p) => p.bookingLocalId.equals(b.id)))
              .get();
          final totalPaid = paid.fold<double>(0, (s, p) => s + p.amount);
          final nights = b.expectedNights;
          final room = allRooms.where((r) => r.roomNumber == b.roomNumber).firstOrNull;
          final pricePerNight = room?.price ?? 0;
          final due = pricePerNight * nights;
          final remaining = due - totalPaid;

          lines.add(
            '- غرفة ${b.roomNumber}: ${b.guestName} | ${b.guestPhone} | $nights ليلة | مدفوع: ${totalPaid.toStringAsFixed(0)} | متبقي: ${remaining.toStringAsFixed(0)}',
          );
        }
      }

      // --- الغرف الشاغرة مع أسعارها ---
      final availableRooms = allRooms.where((r) => r.status == 'available').toList();
      if (availableRooms.isNotEmpty) {
        lines.add('');
        lines.add('الغرف الشاغرة:');
        for (final r in availableRooms) {
          lines.add('- ${r.roomNumber}: ${r.type} - ${r.price.toStringAsFixed(0)} ريال');
        }
      }

      // --- الديون غير المسددة ---
      final debts = await (db.select(db.debts)
            ..where((d) => d.isSettled.equals(0))
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
            ..where((p) => p.paymentDate.equals(today)))
          .get();
      final todayExpenses = await (db.select(db.expenses)
            ..where((e) => e.date.equals(today)))
          .get();
      final totalIncome = todayPayments.fold<double>(0, (s, p) => s + p.amount);
      final totalExpenses = todayExpenses.fold<double>(0, (s, e) => s + e.amount);

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

  Future<GeminiResponse> chat(String userMessage) async {
    if (!isAvailable) {
      return GeminiResponse(
        text: 'المساعد الذكي غير متاح. يرجى إدخال مفتاح Gemini API من الإعدادات.',
        command: null,
        requiresConfirmation: false,
      );
    }

    try {
      // بناء السياق الحي من قاعدة البيانات
      final hotelContext = await _buildHotelContext();
      final systemPrompt = _buildSystemPrompt();

      // إنشاء محادثة جديدة مع السياق
      final chatHistory = <Content>[
        Content.text(systemPrompt),
        Content.text('بيانات الفندق الحالية:\n$hotelContext'),
      ];

      // إضافة المحادثة السابقة (آخر 10 رسائل)
      final recentHistory = _conversationHistory.length > 10
          ? _conversationHistory.sublist(_conversationHistory.length - 10)
          : _conversationHistory;
      chatHistory.addAll(recentHistory);

      final chat = _model!.startChat(history: chatHistory);

      final response = await chat.sendMessage(Content.text(userMessage));
      final responseText = response.text ?? '';

      // حفظ في سجل المحادثة
      _conversationHistory.add(Content.text('المستخدم: $userMessage'));
      _conversationHistory.add(Content.text(responseText));

      // تحليل الأمر من الرد
      final command = _parseCommand(responseText);
      final cleanText = _stripJsonFromResponse(responseText);

      return GeminiResponse(
        text: cleanText,
        command: command,
        requiresConfirmation: command != null &&
            command is! AiQueryCommand &&
            command is! AiNoActionCommand,
      );
    } catch (e) {
      debugPrint('❌ خطأ في Gemini: $e');
      return GeminiResponse(
        text: 'عذراً، حدث خطأ أثناء معالجة طلبك. يرجى المحاولة مرة أخرى.',
        command: null,
        requiresConfirmation: false,
      );
    }
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

        case AiUpdateRoomPriceCommand(:final roomNumber, :final newPrice):
          final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).get();
          if (rooms.isEmpty) {
            result = 'الغرفة $roomNumber غير موجودة';
            break;
          }
          final oldPrice = rooms.first.price;
          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).write(
            RoomsCompanion(
              price: Value(newPrice),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          result =
              'تم تغيير سعر الغرفة $roomNumber من ${oldPrice.toStringAsFixed(0)} إلى ${newPrice.toStringAsFixed(0)} ريال';

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

        case AiAddExpenseCommand(:final expenseType, :final desc, :final amount):
          final uuid = now.microsecondsSinceEpoch.toString();
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

        case AiAddPaymentCommand(:final roomNumber, :final amount, :final notes):
          final bookings = await (db.select(db.bookings)
            ..where((b) => b.roomNumber.equals(roomNumber))).get();
          final activeBooking =
              bookings.where((b) => b.status == 'checked_in').firstOrNull;
          if (activeBooking == null) {
            result = 'لا يوجد حجز نشط للغرفة $roomNumber';
            break;
          }

          final uuid = now.microsecondsSinceEpoch.toString();
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
          result = 'تم تسجيل دفعة ${amount.toStringAsFixed(0)} ريال للغرفة $roomNumber';

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
          result = 'تم إنهاء حجز الغرفة $roomNumber وتسجيل خروج الضيف ${activeBooking.guestName}';

        case AiSettleDebtCommand(
            :final debtId,
            :final guestName,
            :final amount
          ):
          // البحث عن الدين
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
                (targetDebt.totalAmount - newPaid).clamp(0.0, double.infinity),
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

        case AiAddBookingCommand(
            :final roomNumber,
            :final guestName,
            :final guestPhone,
            :final guestNationality,
            :final checkinDate,
            :final expectedNights,
            :final price,
          ):
          // التحقق من توفر الغرفة
          final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).get();
          if (rooms.isEmpty) {
            result = 'الغرفة $roomNumber غير موجودة';
            break;
          }
          if (rooms.first.status != 'available') {
            result = 'الغرفة $roomNumber غير متاحة حالياً. حالتها: ${rooms.first.status}';
            break;
          }

          final roomPrice = price ?? rooms.first.price;
          final uuid = now.microsecondsSinceEpoch.toString();

          // إنشاء الحجز
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

          // تحديث حالة الغرفة
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

        case AiUpdateBookingGuestCommand(
            :final roomNumber,
            :final guestName,
            :final guestPhone,
            :final extendNights,
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

          final changes = updates.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
          result = 'تم تحديث بيانات الغرفة $roomNumber: $changes';

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

صيغ JSON للأوامر المدعومة:

1. تغيير سعر غرفة:
{"action": "update_room_price", "room_number": "101", "new_price": 50000}

2. تغيير حالة غرفة:
{"action": "update_room_status", "room_number": "101", "new_status": "available"}

3. إضافة مصروف:
{"action": "add_expense", "expense_type": "صيانة", "description": "صيانة مكيف", "amount": 20000}

4. تسجيل دفعة:
{"action": "add_payment", "room_number": "101", "amount": 50000, "notes": "دفعة نقدية"}

5. إنهاء حجز (تسجيل خروج):
{"action": "checkout", "room_number": "101"}

6. تسوية دين:
{"action": "settle_debt", "guest_name": "أحمد", "amount": 30000}

7. إضافة حجز جديد:
{"action": "add_booking", "room_number": "101", "guest_name": "أحمد محمد", "guest_phone": "777123456", "guest_nationality": "يمني", "checkin_date": "2025-01-15", "expected_nights": 2}

8. تحديث بيانات ضيف:
{"action": "update_booking_guest", "room_number": "101", "guest_name": "الاسم الجديد", "extend_nights": 1}

حالات الغرف: available, occupied, cleaning, maintenance, reserved
أنواع المصروفات: صيانة, طعام, كهرباء, ماء, تنظيف, نقل, أخرى
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
            description:
                'تغيير سعر الغرفة ${json['room_number']} إلى ${json['new_price']}',
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
            guestNationality: json['guest_nationality'] as String? ?? 'يمني',
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
