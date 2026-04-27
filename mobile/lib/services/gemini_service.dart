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

class AiQueryCommand extends AiCommand {
  const AiQueryCommand({required super.description});
}

class AiUpdateRoomPriceCommand extends AiCommand {
  final String roomNumber;
  final double newPrice;
  const AiUpdateRoomPriceCommand({
    required this.roomNumber,
    required this.newPrice,
    required super.description,
  });
}

class AiUpdateRoomStatusCommand extends AiCommand {
  final String roomNumber;
  final String newStatus;
  const AiUpdateRoomStatusCommand({
    required this.roomNumber,
    required this.newStatus,
    required super.description,
  });
}

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

class AiCheckoutCommand extends AiCommand {
  final String roomNumber;
  const AiCheckoutCommand({
    required this.roomNumber,
    required super.description,
  });
}

class AiNoActionCommand extends AiCommand {
  const AiNoActionCommand({required super.description});
}

// ═══════════════════════════════════════════════════════════════
//  خدمة Gemini AI
// ═══════════════════════════════════════════════════════════════

class GeminiService {
  static final GeminiService _instance = GeminiService._();
  static GeminiService get instance => _instance;
  GeminiService._();

  GenerativeModel? _model;
  bool _isInitialized = false;

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
        maxOutputTokens: 1024,
      ),
    );
    _isInitialized = true;
    debugPrint('✅ تم تهيئة Gemini AI');
  }

  void reset() {
    _model = null;
    _isInitialized = false;
  }

  bool get isAvailable => _model != null && _isInitialized;

  /// إرسال رسالة والحصول على رد + أمر
  Future<GeminiResponse> chat(String userMessage, {String? context}) async {
    if (!isAvailable) {
      return GeminiResponse(
        text: '⚠️ المساعد الذكي غير متاح. يرجى إدخال مفتاح Gemini API من الإعدادات.',
        command: null,
        requiresConfirmation: false,
      );
    }

    try {
      final systemPrompt = _buildSystemPrompt();

      final chat = _model!.startChat(
        history: [
          Content.text(systemPrompt),
        ],
      );

      final prompt = context != null
          ? '$context\n\nالمستخدم: $userMessage'
          : userMessage;

      final response = await chat.sendMessage(Content.text(prompt));
      final responseText = response.text ?? '';

      final command = _parseCommand(responseText);
      final cleanText = _stripJsonFromResponse(responseText);

      return GeminiResponse(
        text: cleanText,
        command: command,
        requiresConfirmation:
            command != null && command is! AiQueryCommand && command is! AiNoActionCommand,
      );
    } catch (e) {
      debugPrint('❌ خطأ في Gemini: $e');
      return GeminiResponse(
        text: 'عذراً، حدث خطأ أثناء معالجة طلبك: $e',
        command: null,
        requiresConfirmation: false,
      );
    }
  }

  /// تنفيذ الأمر على قاعدة البيانات
  Future<String> executeCommand(AiCommand command) async {
    final db = DatabaseManager.instance;
    final now = DateTime.now();

    try {
      switch (command) {
        case AiQueryCommand():
          return command.description;

        case AiUpdateRoomPriceCommand(:final roomNumber, :final newPrice):
          final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))
          ).get();
          if (rooms.isEmpty) return '❌ الغرفة $roomNumber غير موجودة';

          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))
          ).write(
            RoomsCompanion(
              price: Value(newPrice),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          return '✅ تم تغيير سعر الغرفة $roomNumber إلى $newPrice';

        case AiUpdateRoomStatusCommand(:final roomNumber, :final newStatus):
          final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))
          ).get();
          if (rooms.isEmpty) return '❌ الغرفة $roomNumber غير موجودة';

          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))
          ).write(
            RoomsCompanion(
              status: Value(newStatus),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          return '✅ تم تغيير حالة الغرفة $roomNumber إلى $newStatus';

        case AiAddExpenseCommand(:final expenseType, :final desc, :final amount):
          final uuid = now.microsecondsSinceEpoch.toString();
          await db.into(db.expenses).insert(
            ExpensesCompanion(
              expenseType: expenseType,
              description: desc,
              amount: amount,
              date: now.toIso8601String().split('T')[0],
              localUuid: Value(uuid),
              createdAt: Value(now.millisecondsSinceEpoch),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              createdAtIso: Value(now.toIso8601String()),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          return '✅ تم إضافة مصروف: $desc - $amount';

        case AiAddPaymentCommand(:final roomNumber, :final amount, :final notes):
          final bookings = await (db.select(db.bookings)
            ..where(
              (b) => b.roomNumber.equals(roomNumber),
            )
          ).get();
          final activeBooking = bookings.where((b) => b.status == 'checked_in').firstOrNull;
          if (activeBooking == null) {
            return '❌ لا يوجد حجز نشط للغرفة $roomNumber';
          }

          final uuid = now.microsecondsSinceEpoch.toString();
          await db.into(db.payments).insert(
            PaymentsCompanion(
              bookingLocalId: Value(activeBooking.id),
              roomNumber: Value(roomNumber),
              amount: amount,
              paymentDate: now.toIso8601String().split('T')[0],
              paymentMethod: 'cash',
              revenueType: 'room_rent',
              notes: Value(notes),
              localUuid: Value(uuid),
              createdAt: Value(now.millisecondsSinceEpoch),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              createdAtIso: Value(now.toIso8601String()),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          return '✅ تم تسجيل دفعة $amount للغرفة $roomNumber';

        case AiCheckoutCommand(:final roomNumber):
          final bookings = await (db.select(db.bookings)
            ..where((b) => b.roomNumber.equals(roomNumber))
          ).get();
          final activeBooking = bookings.where((b) => b.status == 'checked_in').firstOrNull;
          if (activeBooking == null) {
            return '❌ لا يوجد حجز نشط للغرفة $roomNumber';
          }

          final today = now.toIso8601String().split('T')[0];

          await (db.update(db.bookings)
            ..where((b) => b.id.equals(activeBooking.id))
          ).write(
            BookingsCompanion(
              status: Value('checked_out'),
              actualCheckout: Value(today),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );

          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))
          ).write(
            RoomsCompanion(
              status: Value('available'),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          return '✅ تم إنهاء حجز الغرفة $roomNumber';

        case AiNoActionCommand():
          return command.description;
      }
    } catch (e) {
      debugPrint('❌ خطأ في تنفيذ الأمر: $e');
      return '❌ فشل تنفيذ الأمر: $e';
    }
  }

  String _buildSystemPrompt() {
    return '''أنت مساعد ذكي لنظام إدارة فندق Marina. تتحدث باللغة العربية فقط.

قواعد مهمة:
- كن مختصراً ومفيداً
- إذا طلب المستخدم تعديل بيانات، أجب بالشرح ثم أضف JSON للأمر في نهاية رسالتك
- لا تنفذ أوامر خطيرة أبداً بدون تأكيد المستخدم
- الصيغة: ردك المكتوب أولاً، ثم JSON للأمر في سطر منفصل

صيغة JSON للأوامر:

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

حالات الغرف الممكنة: available, occupied, cleaning, maintenance, reserved
طرق الدفع: cash, transfer, card''';
  }

  AiCommand? _parseCommand(String text) {
    try {
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
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  String _stripJsonFromResponse(String text) {
    return text.replaceAll(RegExp(r'\{[^{}]*\}', dotAll: true), '').trim();
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

  const ChatMessage({
    required this.id,
    required this.text,
    this.isUser = false,
    this.pendingCommand,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? text,
    bool? isUser,
    AiCommand? pendingCommand,
  }) {
    return ChatMessage(
      id: id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      pendingCommand: pendingCommand ?? this.pendingCommand,
      timestamp: timestamp,
    );
  }
}
