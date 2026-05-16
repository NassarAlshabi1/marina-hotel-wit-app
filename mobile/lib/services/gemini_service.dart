import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' hide Column;
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../utils/status_utils.dart';
import 'booking_derived_fields_service.dart';
import 'local_db.dart';
import 'price_adjustment_service.dart';

// ═══════════════════════════════════════════════════════════════
//  أوامر AI
// ═══════════════════════════════════════════════════════════════

sealed class AiCommand {
  const AiCommand({required this.description});
  final String description;
}

/// أمر استعلام فقط — لا يحتاج تأكيد
class AiQueryCommand extends AiCommand {
  const AiQueryCommand({required super.description});
}

/// تغيير سعر غرفة (مع إعادة حساب الحجوزات النشطة)
class AiUpdateRoomPriceCommand extends AiCommand {
  const AiUpdateRoomPriceCommand({
    required this.roomNumber,
    required this.newPrice,
    this.reason,
    required super.description,
  });
  final String roomNumber;
  final double newPrice;
  final String? reason;
}

/// تخفيض/زيادة سعر بنسبة لجميع غرف نوع معين
/// مثال: زيادة 10% على غرف doubles
/// مثال: تخفيض 5000 ريال من جميع الغرف
class AiBulkPriceAdjustCommand extends AiCommand {
  const AiBulkPriceAdjustCommand({
    this.roomType,
    required this.mode,
    required this.value,
    this.reason,
    required super.description,
  });
  final String? roomType;
  final String mode; // 'percent_increase', 'percent_decrease', 'fixed_increase', 'fixed_decrease'
  final double value;
  final String? reason;
}

/// تخفيض على حجز معين (خصم ليلي أو إجمالي)
class AiBookingDiscountCommand extends AiCommand {
  const AiBookingDiscountCommand({
    required this.roomNumber,
    required this.discountAmount,
    required this.discountType,
    this.reason,
    required super.description,
  });
  final String roomNumber;
  final double discountAmount;
  final String discountType; // 'per_night' أو 'total'
  final String? reason;
}

/// تغيير حالة غرفة
class AiUpdateRoomStatusCommand extends AiCommand {
  const AiUpdateRoomStatusCommand({
    required this.roomNumber,
    required this.newStatus,
    required super.description,
  });
  final String roomNumber;
  final String newStatus;
}

/// إضافة مصروف
class AiAddExpenseCommand extends AiCommand {
  const AiAddExpenseCommand({
    required this.expenseType,
    required this.desc,
    required this.amount,
    required super.description,
  });
  final String expenseType;
  final String desc;
  final double amount;
}

/// تسجيل دفعة لحجز
class AiAddPaymentCommand extends AiCommand {
  const AiAddPaymentCommand({
    required this.roomNumber,
    required this.amount,
    this.notes,
    required super.description,
  });
  final String roomNumber;
  final double amount;
  final String? notes;
}

/// إنهاء حجز (تسجيل خروج)
class AiCheckoutCommand extends AiCommand {
  const AiCheckoutCommand({
    required this.roomNumber,
    required super.description,
  });
  final String roomNumber;
}

/// إصلاح دفعات غرفة — إعادة حساب الليالي والمستحقات والمدفوعات المخزّنة
class AiFixPaymentsCommand extends AiCommand {
  const AiFixPaymentsCommand({
    required this.roomNumber,
    required super.description,
  });
  final String roomNumber;
}

/// تسوية دين
class AiSettleDebtCommand extends AiCommand {
  const AiSettleDebtCommand({
    this.debtId,
    required this.guestName,
    required this.amount,
    required super.description,
  });
  final int? debtId;
  final String guestName;
  final double amount;
}

/// إضافة حجز جديد
class AiAddBookingCommand extends AiCommand {
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
  final String roomNumber;
  final String guestName;
  final String guestPhone;
  final String guestNationality;
  final String checkinDate;
  final int expectedNights;
  final double? price;
}

/// تحديث بيانات ضيف
class AiUpdateBookingGuestCommand extends AiCommand {
  const AiUpdateBookingGuestCommand({
    required this.roomNumber,
    this.guestName,
    this.guestPhone,
    this.extendNights,
    required super.description,
  });
  final String roomNumber;
  final String? guestName;
  final String? guestPhone;
  final int? extendNights;
}

/// طلب تقرير (يُنفذ فوراً بدون تأكيد)
class AiReportCommand extends AiCommand {
  const AiReportCommand({
    required this.reportType,
    this.dateFrom,
    this.dateTo,
    required super.description,
  });
  final String reportType; // daily, revenue, occupancy, debts, expenses, room_prices
  final String? dateFrom;
  final String? dateTo;
}

/// لا يوجد إجراء مطلوب
class AiNoActionCommand extends AiCommand {
  const AiNoActionCommand({required super.description});
}

// ═══════════════════════════════════════════════════════════════
//  سجل تدقيق AI
// ═══════════════════════════════════════════════════════════════

class AiAuditLog {

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
  final String id;
  final String userMessage;
  final String aiResponse;
  final String? commandType;
  final String? commandDescription;
  final String executionResult;
  final DateTime timestamp;
  final bool wasConfirmed;

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
  GeminiService._();
  static final GeminiService _instance = GeminiService._();
  static GeminiService get instance => _instance;

  static const _uuid = Uuid();
  static final _random = Random();
  GenerativeModel? _model;
  ChatSession? _chat;
  bool _isInitialized = false;

  /// مؤقت لمنع الإرسال السريع ( cooldown بين الطلبات )
  DateTime? _lastRequestTime;
  static const _minRequestInterval = Duration(seconds: 2);

  /// عدد المحاولات عند تجاوز الحد
  static const _maxRetries = 3;

  /// سجل التدقيق
  final List<AiAuditLog> _auditLog = [];
  List<AiAuditLog> get auditLog => List.unmodifiable(_auditLog);

  /// آخر خطأ في التهيئة (لعرضه في الواجهة)
  String? _initError;
  String? get initError => _initError;

  /// آخر خطأ في الإرسال
  String? _lastError;
  String? get lastError => _lastError;

  /// تهيئة Gemini AI عبر Firebase AI Logic (بدون مفتاح API في الكود)
  /// يستخدم ChatSession لإدارة المحادثة تلقائياً — حسب نمط Firebase AI Logic الرسمي
  /// [forceRetry] = true لإجبار إعادة التهيئة حتى لو نجحت سابقاً
  Future<void> initialize({bool forceRetry = false}) async {
    if (_isInitialized && !forceRetry) {
      return;
    }

    // إعادة تعيين الحالة عند إعادة المحاولة
    if (forceRetry) {
      _model = null;
      _chat = null;
      _isInitialized = false;
      _initError = null;
    }

    try {
      _initError = null;
      // FirebaseAI.googleAI() يستخدم مفتاح API المُدار من Firebase Console
      // لا حاجة لتخزين مفتاح API في الكود أو Remote Config
      final ai = FirebaseAI.googleAI();
      _model = ai.generativeModel(
        model: 'gemini-2.5-flash', // تم التحديث إلى Gemini 2.5 Flash
        systemInstruction: Content.system(_buildSystemPrompt()),
        generationConfig: GenerationConfig(
          temperature: 0.2, // تقليل الـ temperature لزيادة الدقة في الأوامر
          topP: 0.9,
          maxOutputTokens: 4096, // زيادة الحد الأقصى للتوكنز للتقارير الطويلة
        ),
      );
      // إنشاء جلسة محادثة — startChat يدير سجل المحادثة تلقائياً
      _chat = _model!.startChat();
      _isInitialized = true;
      _lastError = null;
      debugPrint('✅ تم تهيئة Gemini AI عبر Firebase AI Logic (ChatSession)');
    } catch (e) {
      debugPrint('⚠️ فشل تهيئة Gemini AI: $e');
      debugPrint('ℹ️ تأكد من تفعيل AI Logic في Firebase Console');
      _initError = _describeInitError(e);
      _lastError = _initError;
    }
  }

  /// وصف خطأ التهيئة بلغة واضحة
  String _describeInitError(Object e) {
    final msg = e.toString();
    if (msg.contains('[core/no-app') || msg.contains('No Firebase')) {
      return 'Firebase غير مهيأ — تأكد من استدعاء Firebase.initializeApp() في main()';
    } else if (msg.contains('API_KEY') || msg.contains('api.key')) {
      return 'مفتاح API غير صالح — تحقق من Firebase Console > Project Settings';
    } else if (msg.contains('not enabled') || msg.contains('NOT_FOUND')) {
      return 'Firebase AI غير مفعّل — فعّله من Firebase Console > AI Logic';
    } else if (msg.contains('location') || msg.contains('region')) {
      return 'الخدمة غير متاحة في منطقتك — تأكد أن Firebase AI مفعّل';
    } else if (msg.contains('network') || msg.contains('socket') || msg.contains('connection')) {
      return 'خطأ في الاتصال بالشبكة — تأكد من الإنترنت';
    }
    return 'فشل التهيئة: $e';
  }

  void reset() {
    _model = null;
    _chat = null;
    _isInitialized = false;
  }

  bool get isAvailable => _model != null && _chat != null && _isInitialized;

  /// مسح سجل المحادثة — إنشاء جلسة جديدة
  void clearHistory() {
    if (_model != null && _isInitialized) {
      _chat = _model!.startChat();
    }
  }

  /// مسح سجل التدقيق
  void clearAuditLog() {
    _auditLog.clear();
  }

  // ───────────────────────────────────────────────────────────
  //  بناء سياق الفندق من قاعدة البيانات
  //  محسّن: استعلام واحد موحد بدل N+1 + cache لمدة 30 ثانية
  // ───────────────────────────────────────────────────────────

  /// ذاكرة مؤقتة للسياق — تُحدّث كل 30 ثانية فقط
  String? _cachedContext;
  DateTime? _contextBuiltAt;
  static const _contextCacheDuration = Duration(seconds: 30);

  /// بناء سياق الفندق — عام ليُستخدم من خدمات أخرى
  Future<String> buildHotelContext() => _buildHotelContextImpl();

  Future<String> _buildHotelContext() => _buildHotelContextImpl();

  Future<String> _buildHotelContextImpl() async {
    // إعادة استخدام السياق المخزّن مؤقتاً
    if (_cachedContext != null && _contextBuiltAt != null) {
      final elapsed = DateTime.now().difference(_contextBuiltAt!);
      if (elapsed < _contextCacheDuration) {
        return _cachedContext!;
      }
    }

    final db = DatabaseManager.instance;
    final s = StringBuffer();
    final now = DateTime.now();
    final today = now.toIso8601String().split('T')[0];

    try {
      s.writeln('═══ سياق الفندق (موسع) ═══');
      s.writeln('تاريخ/وقت البناء: ${now.toIso8601String()}');
      s.writeln('ملاحظة: البيانات أدناه حية من قاعدة البيانات، وقد تحتوي قوائم طويلة حسب حجم الفندق.');
      s.writeln();

      // ═══════════════════════════════════════════════════════════
      //  1. بيانات الغرف الشاملة
      // ═══════════════════════════════════════════════════════════
      final allRooms = await (db.select(db.rooms)
            ..where((r) => r.deletedAt.isNull()))
          .get();
      final roomMap = {for (final r in allRooms) r.roomNumber: r};

      final available = allRooms.where((r) => r.status == 'available').length;
      final occupied = allRooms.where((r) => r.status == 'occupied').length;
      final maintenance = allRooms.where((r) => r.status == 'maintenance').length;
      final cleaning = allRooms.where((r) => r.status == 'cleaning').length;
      final total = allRooms.length;

      // توزيع أنواع الغرف مع متوسط الأسعار
      final typeStats = <String, List<double>>{};
      for (final r in allRooms) {
        typeStats.putIfAbsent(r.type, () => []).add(r.price);
      }

      s.writeln('═══ بيانات الغرف ($total غرفة) ═══');
      s.writeln('الحالات: شاغرة $available | محجوزة $occupied | تنظيف $cleaning | صيانة $maintenance');
      s.writeln('أنواع الغرف:');
      for (final entry in typeStats.entries) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        final min = entry.value.reduce((a, b) => a < b ? a : b);
        final max = entry.value.reduce((a, b) => a > b ? a : b);
        s.writeln('  ${entry.key}: ${entry.value.length} غرفة | متوسط ${avg.toStringAsFixed(0)} | أقل ${min.toStringAsFixed(0)} | أعلى ${max.toStringAsFixed(0)} ريال');
      }

      if (allRooms.isNotEmpty) {
        final typeStatusStats = <String, Map<String, int>>{};
        for (final r in allRooms) {
          final row = typeStatusStats.putIfAbsent(r.type, () => <String, int>{
                'available': 0,
                'occupied': 0,
                'maintenance': 0,
                'cleaning': 0,
                'other': 0,
              });
          final status = r.status;
          if (row.containsKey(status)) {
            row[status] = (row[status] ?? 0) + 1;
          } else {
            row['other'] = (row['other'] ?? 0) + 1;
          }
        }

        s.writeln();
        s.writeln('تفصيل الإشغال حسب النوع:');
        for (final entry in typeStatusStats.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
          final m = entry.value;
          final t = m.values.fold<int>(0, (s, v) => s + v);
          final occ = m['occupied'] ?? 0;
          final occRate = t > 0 ? (occ / t * 100) : 0.0;
          s.writeln(
              '  ${entry.key}: إجمالي $t | إشغال $occ (${occRate.toStringAsFixed(0)}%) | شاغر ${m['available'] ?? 0} | تنظيف ${m['cleaning'] ?? 0} | صيانة ${m['maintenance'] ?? 0}');
        }

        final prices = allRooms.map((r) => r.price).toList()..sort();
        double percentile(double p) {
          if (prices.isEmpty) return 0;
          final idx = p * (prices.length - 1);
          final lo = idx.floor();
          final hi = idx.ceil();
          if (lo == hi) return prices[lo];
          final frac = idx - lo;
          return prices[lo] + (prices[hi] - prices[lo]) * frac;
        }

        final minPrice = prices.first;
        final maxPrice = prices.last;
        final p10 = percentile(0.10);
        final p25 = percentile(0.25);
        final p50 = percentile(0.50);
        final p75 = percentile(0.75);
        final p90 = percentile(0.90);
        s.writeln();
        s.writeln(
            'إحصائيات الأسعار (لكل الغرف): أقل ${minPrice.toStringAsFixed(0)} | 10% ${p10.toStringAsFixed(0)} | 25% ${p25.toStringAsFixed(0)} | متوسط/وسيط ${p50.toStringAsFixed(0)} | 75% ${p75.toStringAsFixed(0)} | 90% ${p90.toStringAsFixed(0)} | أعلى ${maxPrice.toStringAsFixed(0)} ريال');
      }

      // الغرف الشاغرة مرتبة بالسعر
      final availableRooms = allRooms.where((r) => r.status == 'available').toList()
        ..sort((a, b) => a.price.compareTo(b.price));
      if (availableRooms.isNotEmpty) {
        s.writeln();
        final limit = availableRooms.length < 120 ? availableRooms.length : 120;
        s.writeln('الغرف الشاغرة (${availableRooms.length}) — عرض أول $limit:');
        for (final r in availableRooms.take(limit)) {
          s.writeln('  ${r.roomNumber}: ${r.type} | ${r.price.toStringAsFixed(0)} ريال');
        }
        if (availableRooms.length > limit) {
          s.writeln('  ... (${availableRooms.length - limit} غرفة أخرى)');
        }
      }

      final maintenanceRooms =
          allRooms.where((r) => r.status == 'maintenance').toList()
            ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
      if (maintenanceRooms.isNotEmpty) {
        final limit = maintenanceRooms.length < 80 ? maintenanceRooms.length : 80;
        s.writeln();
        s.writeln('غرف تحت الصيانة (${maintenanceRooms.length}) — عرض أول $limit:');
        for (final r in maintenanceRooms.take(limit)) {
          s.writeln('  ${r.roomNumber}: ${r.type} | ${r.price.toStringAsFixed(0)} ريال');
        }
        if (maintenanceRooms.length > limit) {
          s.writeln('  ... (${maintenanceRooms.length - limit} غرفة أخرى)');
        }
      }

      final cleaningRooms =
          allRooms.where((r) => r.status == 'cleaning').toList()
            ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
      if (cleaningRooms.isNotEmpty) {
        final limit = cleaningRooms.length < 80 ? cleaningRooms.length : 80;
        s.writeln();
        s.writeln('غرف بحاجة تنظيف (${cleaningRooms.length}) — عرض أول $limit:');
        for (final r in cleaningRooms.take(limit)) {
          s.writeln('  ${r.roomNumber}: ${r.type} | ${r.price.toStringAsFixed(0)} ريال');
        }
        if (cleaningRooms.length > limit) {
          s.writeln('  ... (${cleaningRooms.length - limit} غرفة أخرى)');
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  2. الحجوزات النشطة — بيانات شاملة ومُفصّلة
      // ═══════════════════════════════════════════════════════════
      final activeBookings = await (db.select(db.bookings)
            ..where((b) => b.status.equals('checked_in'))
            ..where((b) => b.deletedAt.isNull())
            ..orderBy([(b) => OrderingTerm.asc(b.roomNumber)]))
          .get();

      if (activeBookings.isNotEmpty) {
        s.writeln();
        s.writeln('═══ الحجوزات النشطة (${activeBookings.length}) ═══');
        final limit = activeBookings.length < 200 ? activeBookings.length : 200;
        for (final b in activeBookings.take(limit)) {
          final totalPaid = b.totalPaidCached;
          final totalDue = b.totalDueCached;
          final remaining = b.remainingBalanceCached;
          final nights = b.calculatedNights;
          final checkin = b.checkinDate.split('T').first;
          final checkout = b.checkoutDate?.split('T').first ?? 'غير محدد';
          final discount = b.discount;
          final hasDiscount = discount > 0;
          final room = roomMap[b.roomNumber];
          final roomType = room?.type ?? '';
          final roomPrice = room?.price ?? 0;
          final nationality = b.guestNationality;
          final isFullyPaid = b.isFullyPaid;
          final isOverdue = b.isOverdue;
          final stayDays = checkin != 'غير محدد'
              ? now.difference(DateTime.parse(checkin)).inDays
              : 0;

          s.writeln('  [${b.roomNumber}] ${b.guestName} | $nationality | ${b.guestPhone}');
          s.writeln('    النوع: $roomType | السعر: ${roomPrice.toStringAsFixed(0)} ريال/ليلة');
          s.writeln('    دخول: $checkin | مغادرة: $checkout | $nights ليلة | أقام $stayDays يوم');
          s.writeln('    مدفوع: ${totalPaid.toStringAsFixed(0)} | مستحق: ${totalDue.toStringAsFixed(0)} | متبقي: ${remaining.toStringAsFixed(0)} ${isFullyPaid ? "(مكتمل)" : "(غير مكتمل)"}${isOverdue ? " ⚠️ متأخر" : ""}');
          if (hasDiscount) {
            final discountLabel = b.discountType == 'per_night' ? 'ل كل ليلة' : 'إجمالي';
            s.writeln('    خصم: ${discount.toStringAsFixed(0)} ريال ($discountLabel)');
          }
        }
        if (activeBookings.length > limit) {
          s.writeln('... (تم عرض أول $limit من ${activeBookings.length})');
        }

        // إحصائيات الضيوف الحاليين
        final nationalities = <String, int>{};
        for (final b in activeBookings) {
          nationalities[b.guestNationality] = (nationalities[b.guestNationality] ?? 0) + 1;
        }
        s.writeln();
        s.writeln('توزيع الجنسيات: ${nationalities.entries.map((e) => "${e.key}(${e.value})").join(", ")}');

        // إحصائيات الدفع
        final fullyPaid = activeBookings.where((b) => b.isFullyPaid).length;
        final partialPaid = activeBookings.where((b) => b.totalPaidCached > 0 && !b.isFullyPaid).length;
        final notPaid = activeBookings.where((b) => b.totalPaidCached == 0).length;
        final overdueCount = activeBookings.where((b) => b.isOverdue).length;
        s.writeln('حالة الدفع: مكتمل $fullyPaid | جزئي $partialPaid | لم يدفع $notPaid | متأخر $overdueCount');

        final overdueBookings = activeBookings
            .where((b) => b.isOverdue)
            .toList()
          ..sort((a, b) => b.remainingBalanceCached.compareTo(a.remainingBalanceCached));
        if (overdueBookings.isNotEmpty) {
          final overdueLimit =
              overdueBookings.length < 50 ? overdueBookings.length : 50;
          s.writeln();
          s.writeln('الحجوزات المتأخرة في الدفع (${overdueBookings.length}) — عرض أول $overdueLimit:');
          for (final b in overdueBookings.take(overdueLimit)) {
            s.writeln(
                '  [${b.roomNumber}] ${b.guestName} | متبقي ${b.remainingBalanceCached.toStringAsFixed(0)} ريال | دخول ${b.checkinDate.split('T').first}');
          }
        }

        final remainingBookings = activeBookings
            .where((b) => b.remainingBalanceCached > 0.5)
            .toList()
          ..sort((a, b) => b.remainingBalanceCached.compareTo(a.remainingBalanceCached));
        if (remainingBookings.isNotEmpty) {
          final remLimit =
              remainingBookings.length < 50 ? remainingBookings.length : 50;
          s.writeln();
          s.writeln('أكبر المتبقيات على الحجوزات (${remainingBookings.length}) — عرض أول $remLimit:');
          for (final b in remainingBookings.take(remLimit)) {
            s.writeln(
                '  [${b.roomNumber}] ${b.guestName} | متبقي ${b.remainingBalanceCached.toStringAsFixed(0)} ريال | مستحق ${b.totalDueCached.toStringAsFixed(0)} | مدفوع ${b.totalPaidCached.toStringAsFixed(0)}');
          }
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  3. تنبيهات المغادرة — ضيوف يجب مغادرتهم اليوم أو غداً
      // ═══════════════════════════════════════════════════════════
      final tomorrow = now.add(const Duration(days: 1)).toIso8601String().split('T')[0];
      final checkoutToday = activeBookings.where((b) => b.checkoutDate?.split('T').first == today).toList();
      final checkoutTomorrow = activeBookings.where((b) => b.checkoutDate?.split('T').first == tomorrow).toList();

      if (checkoutToday.isNotEmpty || checkoutTomorrow.isNotEmpty) {
        s.writeln();
        s.writeln('═══ تنبيهات المغادرة ═══');
        if (checkoutToday.isNotEmpty) {
          s.writeln('مغادرة اليوم (${checkoutToday.length}):');
          for (final b in checkoutToday) {
            final rem = b.remainingBalanceCached;
            s.writeln('  [${b.roomNumber}] ${b.guestName} | متبقي: ${rem.toStringAsFixed(0)} ريال ${rem > 0 ? "⚠️" : "✓"}');
          }
        }
        if (checkoutTomorrow.isNotEmpty) {
          s.writeln('مغادرة غداً (${checkoutTomorrow.length}):');
          for (final b in checkoutTomorrow) {
            final rem = b.remainingBalanceCached;
            s.writeln('  [${b.roomNumber}] ${b.guestName} | متبقي: ${rem.toStringAsFixed(0)} ريال ${rem > 0 ? "⚠️" : "✓"}');
          }
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  4. الديون غير المسددة — مع تفاصيل الرهن
      // ═══════════════════════════════════════════════════════════
      final debts = await (db.select(db.debts)
            ..where((d) => d.isSettled.equals(0))
            ..where((d) => d.deletedAt.isNull())
            ..orderBy([(d) => OrderingTerm.desc(d.dateRecorded)]))
          .get();
      if (debts.isNotEmpty) {
        final totalDebt = debts.fold<double>(0, (s, d) => s + d.remainingAmount);
        s.writeln();
        s.writeln('═══ الديون غير المسددة (${debts.length}) | إجمالي: ${totalDebt.toStringAsFixed(0)} ريال ═══');
        for (final d in debts.take(50)) {
          final pledgeInfo = d.pledge != null && d.pledge!.isNotEmpty ? ' | رهن: ${d.pledge}' : '';
          s.writeln('  ${d.guestName}: متبقي ${d.remainingAmount.toStringAsFixed(0)} من ${d.totalAmount.toStringAsFixed(0)} ريال | سبب: ${d.debtReason}$pledgeInfo');
        }

        final topDebts = [...debts]
          ..sort((a, b) => b.remainingAmount.compareTo(a.remainingAmount));
        s.writeln();
        s.writeln('أكبر الديون (أول 10):');
        for (final d in topDebts.take(10)) {
          final pledgeInfo = d.pledge != null && d.pledge!.isNotEmpty ? ' | رهن: ${d.pledge}' : '';
          s.writeln('  ${d.guestName}: ${d.remainingAmount.toStringAsFixed(0)} ريال | سبب: ${d.debtReason}$pledgeInfo');
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  5. الإيرادات والمصروفات اليوم — مع تفصيل حسب النوع
      // ═══════════════════════════════════════════════════════════
      final todayPayments = await (db.select(db.payments)
            ..where((p) => p.paymentDate.like('$today%'))
            ..where((p) => p.deletedAt.isNull())
            ..where((p) => p.isVoided.equals(false)))
          .get();
      final todayExpenses = await (db.select(db.expenses)
            ..where((e) => e.date.like('$today%'))
            ..where((e) => e.deletedAt.isNull()))
          .get();

      final totalIncome = todayPayments.fold<double>(0, (s, p) => s + p.amount);
      final totalExpenses = todayExpenses.fold<double>(0, (s, e) => s + e.amount);

      s.writeln();
      s.writeln('═══ ملخص اليوم ($today) ═══');
      s.writeln('الإيرادات: ${totalIncome.toStringAsFixed(0)} ريال (${todayPayments.length} عملية)');
      s.writeln('المصروفات: ${totalExpenses.toStringAsFixed(0)} ريال (${todayExpenses.length} عملية)');
      s.writeln('صافي اليوم: ${(totalIncome - totalExpenses).toStringAsFixed(0)} ريال');

      // تفصيل المدفوعات حسب نوع الإيراد
      final revenueByType = <String, double>{};
      for (final p in todayPayments) {
        final type = p.revenueType;
        revenueByType[type] = (revenueByType[type] ?? 0) + p.amount;
      }
      if (revenueByType.isNotEmpty) {
        s.writeln('توزيع الإيرادات:');
        for (final entry in revenueByType.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
          s.writeln('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
        }
      }

      // تفصيل المدفوعات حسب طريقة الدفع
      final paymentsByMethod = <String, double>{};
      for (final p in todayPayments) {
        final method = p.paymentMethod;
        paymentsByMethod[method] = (paymentsByMethod[method] ?? 0) + p.amount;
      }
      if (paymentsByMethod.isNotEmpty) {
        s.writeln('طرق الدفع:');
        for (final entry in paymentsByMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
          s.writeln('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
        }
      }

      // تفصيل المصروفات حسب الفئة
      final expensesByType = <String, double>{};
      for (final e in todayExpenses) {
        final type = e.expenseType;
        expensesByType[type] = (expensesByType[type] ?? 0) + e.amount;
      }
      if (expensesByType.isNotEmpty) {
        s.writeln('توزيع المصروفات:');
        for (final entry in expensesByType.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
          s.writeln('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
        }
      }

      if (todayPayments.isNotEmpty) {
        final sorted = [...todayPayments]..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
        s.writeln();
        final limit = sorted.length < 60 ? sorted.length : 60;
        s.writeln('تفاصيل المدفوعات اليوم (آخر $limit من ${sorted.length}):');
        for (final p in sorted.take(limit)) {
          final room = p.roomNumber ?? '-';
          final note = (p.notes != null && p.notes!.trim().isNotEmpty) ? ' | ملاحظة: ${p.notes}' : '';
          s.writeln('  $room | ${p.amount.toStringAsFixed(0)} ريال | ${p.paymentMethod} | ${p.revenueType} | ${p.paymentDate}$note');
        }
      }

      if (todayExpenses.isNotEmpty) {
        final sorted = [...todayExpenses]..sort((a, b) => b.date.compareTo(a.date));
        s.writeln();
        final limit = sorted.length < 60 ? sorted.length : 60;
        s.writeln('تفاصيل المصروفات اليوم (آخر $limit من ${sorted.length}):');
        for (final e in sorted.take(limit)) {
          final desc = (e.description != null && e.description!.trim().isNotEmpty) ? ' | ${e.description}' : '';
          s.writeln('  ${e.expenseType}: ${e.amount.toStringAsFixed(0)} ريال | ${e.date}$desc');
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  6. المؤشرات المالية الأساسية
      // ═══════════════════════════════════════════════════════════
      final occupancyRate = total > 0 ? (occupied / total * 100) : 0.0;
      final totalRemaining = activeBookings.fold<double>(
        0, (s, b) => s + (b.remainingBalanceCached > 0 ? b.remainingBalanceCached : 0),
      );
      final avgPayment = todayPayments.isNotEmpty ? totalIncome / todayPayments.length : 0.0;
      final totalDueAll = activeBookings.fold<double>(0, (s, b) => s + b.totalDueCached);
      final totalPaidAll = activeBookings.fold<double>(0, (s, b) => s + b.totalPaidCached);
      final collectionRate = totalDueAll > 0 ? (totalPaidAll / totalDueAll * 100) : 0.0;

      s.writeln();
      s.writeln('═══ المؤشرات المالية ═══');
      s.writeln('نسبة الإشغال: ${occupancyRate.toStringAsFixed(0)}%');
      s.writeln('إجمالي المتبقي المستحق: ${totalRemaining.toStringAsFixed(0)} ريال');
      s.writeln('إجمالي المستحقات: ${totalDueAll.toStringAsFixed(0)} ريال');
      s.writeln('إجمالي المحصّل: ${totalPaidAll.toStringAsFixed(0)} ريال');
      s.writeln('نسبة التحصيل: ${collectionRate.toStringAsFixed(0)}%');
      s.writeln('متوسط قيمة العملية اليوم: ${avgPayment.toStringAsFixed(0)} ريال');

      // ═══════════════════════════════════════════════════════════
      //  7. الإيرادات التاريخية — آخر 7 أيام (اتجاه الإيرادات)
      // ═══════════════════════════════════════════════════════════
      s.writeln();
      s.writeln('═══ اتجاه الإيرادات (آخر 14 يوم) ═══');
      for (var i = 13; i >= 0; i--) {
        final pastDate = now.subtract(Duration(days: i)).toIso8601String().split('T')[0];
        final dayPayments = await (db.select(db.payments)
              ..where((p) => p.paymentDate.like('$pastDate%'))
              ..where((p) => p.deletedAt.isNull())
              ..where((p) => p.isVoided.equals(false)))
            .get();
        final dayExpenses = await (db.select(db.expenses)
              ..where((e) => e.date.like('$pastDate%'))
              ..where((e) => e.deletedAt.isNull()))
            .get();
        final dayIncome = dayPayments.fold<double>(0, (s, p) => s + p.amount);
        final dayExpense = dayExpenses.fold<double>(0, (s, e) => s + e.amount);
        final dayNet = dayIncome - dayExpense;
        final isToday = i == 0;
        final marker = isToday ? ' ◄' : '';
        s.writeln('  $pastDate: إيرادات ${dayIncome.toStringAsFixed(0)} | مصروفات ${dayExpense.toStringAsFixed(0)} | صافي ${dayNet.toStringAsFixed(0)}$marker');
      }

      // ═══════════════════════════════════════════════════════════
      //  8. دفتر اليوم الفندقي — آخر 5 أيام
      // ═══════════════════════════════════════════════════════════
      final ledgerEntries = await (db.select(db.hotelDayLedger)
            ..orderBy([(l) => OrderingTerm.desc(l.hotelDayKey)]))
          .get();
      if (ledgerEntries.isNotEmpty) {
        s.writeln();
        final limit = ledgerEntries.length < 10 ? ledgerEntries.length : 10;
        s.writeln('═══ دفتر اليوم الفندقي (آخر $limit) ═══');
        for (final l in ledgerEntries.take(limit)) {
          s.writeln('  ${l.hotelDayKey}: دخل ${l.totalIncome.toStringAsFixed(0)} | مصروفات ${l.totalExpenses.toStringAsFixed(0)} | إشغال ${l.occupancyRate.toStringAsFixed(0)}% | حجوزات ${l.bookingsProcessed} | مدفوعات ${l.paymentsProcessed}');
        }

        final last30Limit = ledgerEntries.length < 30 ? ledgerEntries.length : 30;
        final last30 = ledgerEntries.take(last30Limit).toList();
        final totalIncome30 = last30.fold<double>(0, (s, e) => s + e.totalIncome);
        final totalExp30 = last30.fold<double>(0, (s, e) => s + e.totalExpenses);
        final avgIncome30 = last30.isNotEmpty ? totalIncome30 / last30.length : 0.0;
        final avgExp30 = last30.isNotEmpty ? totalExp30 / last30.length : 0.0;
        final avgOcc30 = last30.isNotEmpty
            ? last30.fold<double>(0, (s, e) => s + e.occupancyRate) / last30.length
            : 0.0;
        final bestIncomeDay = [...last30]
          ..sort((a, b) => b.totalIncome.compareTo(a.totalIncome));
        final worstIncomeDay = [...last30]
          ..sort((a, b) => a.totalIncome.compareTo(b.totalIncome));
        s.writeln();
        s.writeln('ملخص دفتر اليوم (آخر $last30Limit يوم):');
        s.writeln('  إجمالي دخل: ${totalIncome30.toStringAsFixed(0)} | إجمالي مصروفات: ${totalExp30.toStringAsFixed(0)} | صافي: ${(totalIncome30 - totalExp30).toStringAsFixed(0)} ريال');
        s.writeln('  متوسط يومي: دخل ${avgIncome30.toStringAsFixed(0)} | مصروفات ${avgExp30.toStringAsFixed(0)} | إشغال ${avgOcc30.toStringAsFixed(0)}%');
        if (bestIncomeDay.isNotEmpty) {
          final d = bestIncomeDay.first;
          s.writeln('  أعلى دخل: ${d.hotelDayKey} = ${d.totalIncome.toStringAsFixed(0)} ريال');
        }
        if (worstIncomeDay.isNotEmpty) {
          final d = worstIncomeDay.first;
          s.writeln('  أقل دخل: ${d.hotelDayKey} = ${d.totalIncome.toStringAsFixed(0)} ريال');
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  9. ملاحظات الوردية النشطة
      // ═══════════════════════════════════════════════════════════
      final activeNotes = await (db.select(db.shiftNotes)
            ..where((n) => n.isRead.equals(0)))
          .get();
      if (activeNotes.isNotEmpty) {
        s.writeln();
        s.writeln('═══ ملاحظات وردية غير مقروءة (${activeNotes.length}) ═══');
        for (final n in activeNotes.take(10)) {
          final priorityLabel = n.priority == 'high' ? '🔴' : n.priority == 'medium' ? '🟡' : '🟢';
          s.writeln('  $priorityLabel [${n.shiftType}] ${n.title}: ${n.content}');
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  10. تعديلات الأسعار الأخيرة
      // ═══════════════════════════════════════════════════════════
      final recentAdjustments = await (db.select(db.priceAdjustments)
            ..where((a) => a.isReversed.equals(false))
            ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
          .get();
      if (recentAdjustments.isNotEmpty) {
        s.writeln();
        final limit = recentAdjustments.length < 30 ? recentAdjustments.length : 30;
        s.writeln('═══ تعديلات أسعار حديثة (آخر $limit) ═══');
        for (final a in recentAdjustments.take(limit)) {
          s.writeln('  ${a.targetType} | ${a.adjustmentType}: ${a.previousValue} -> ${a.newValue} | بواسطة: ${a.appliedBy} | ${a.reason ?? "بدون سبب"}');
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  11. المتوسطات والإحصائيات العامة
      // ═══════════════════════════════════════════════════════════
      if (activeBookings.isNotEmpty) {
        final avgNights = activeBookings.fold<int>(0, (s, b) => s + b.calculatedNights) / activeBookings.length;
        final avgDue = activeBookings.fold<double>(0, (s, b) => s + b.totalDueCached) / activeBookings.length;
        s.writeln();
        s.writeln('═══ إحصائيات عامة ═══');
        s.writeln('متوسط مدة الإقامة: ${avgNights.toStringAsFixed(1)} ليلة');
        s.writeln('متوسط الفاتورة: ${avgDue.toStringAsFixed(0)} ريال');
        s.writeln('إجمالي الحجوزات النشطة: ${activeBookings.length}');
      }

      // ═══════════════════════════════════════════════════════════
      //  12. التحقق من صحة الحسابات — 4 فحوصات شاملة
      // ═══════════════════════════════════════════════════════════
      s.writeln();
      s.writeln('═══ التحقق من صحة الحسابات ═══');

      // --- فحص 1: هل المتبقي = التكلفة - المدفوع ---
      final balanceErrors = <String>[];
      for (final b in activeBookings) {
        final due = b.totalDueCached;
        final paid = b.totalPaidCached;
        final remaining = b.remainingBalanceCached;
        final expectedRemaining = due - paid;
        final diff = (remaining - expectedRemaining).abs();
        if (diff > 0.5) {
          // فرق أكبر من 0.5 ريال يُعتبر خطأ
          balanceErrors.add(
            '[${b.roomNumber}] ${b.guestName}: المتبقي المسجل ${remaining.toStringAsFixed(0)} ≠ المتوقع ${expectedRemaining.toStringAsFixed(0)} (تكلفة ${due.toStringAsFixed(0)} - مدفوع ${paid.toStringAsFixed(0)}) | فرق ${diff.toStringAsFixed(0)} ريال',
          );
        }
      }
      if (balanceErrors.isEmpty) {
        s.writeln('✓ فحص توازن الحسابات: جميع الحسابات صحيحة — المتبقي = التكلفة - المدفوع');
      } else {
        s.writeln('✗ فحص توازن الحسابات: ${balanceErrors.length} خطأ في توازن الحسابات:');
        for (final err in balanceErrors) {
          s.writeln('  ✗ $err');
        }
      }

      // --- فحص 2: هل يوجد رصيد سالب (مدفوع أكبر من التكلفة) ---
      final negativeBalance = activeBookings.where((b) => b.remainingBalanceCached < -0.5).toList();
      if (negativeBalance.isEmpty) {
        s.writeln('✓ فحص الرصيد السالب: لا يوجد أرصدة سالبة');
      } else {
        s.writeln('✗ فحص الرصيد السالب: ${negativeBalance.length} حجز برصيد سالب (المدفوع exceeds التكلفة):');
        for (final b in negativeBalance) {
          s.writeln('  ✗ [${b.roomNumber}] ${b.guestName}: متبقي ${b.remainingBalanceCached.toStringAsFixed(0)} ريال (مدفوع ${b.totalPaidCached.toStringAsFixed(0)} exceeds مستحق ${b.totalDueCached.toStringAsFixed(0)})');
        }
      }

      // --- فحص 3: هل يوجد دفعات أكبر من إجمالي التكلفة ---
      final overpayments = activeBookings.where((b) => b.totalPaidCached > b.totalDueCached + 0.5).toList();
      if (overpayments.isEmpty) {
        s.writeln('✓ فحص الدفعات الزائدة: لا توجد دفعات تتجاوز التكلفة');
      } else {
        s.writeln('✗ فحص الدفعات الزائدة: ${overpayments.length} حجز بدفعات تتجاوز التكلفة:');
        for (final b in overpayments) {
          final overpay = b.totalPaidCached - b.totalDueCached;
          s.writeln('  ✗ [${b.roomNumber}] ${b.guestName}: مدفوع ${b.totalPaidCached.toStringAsFixed(0)} > مستحق ${b.totalDueCached.toStringAsFixed(0)} | زيادة ${overpay.toStringAsFixed(0)} ريال');
        }
      }

      // --- فحص 4: هل توجد غرفة محجوزة بدون أي دفعة ---
      final noPayments = activeBookings.where((b) => b.totalPaidCached < 0.5).toList();
      if (noPayments.isEmpty) {
        s.writeln('✓ فحص الغرف بدون دفعات: جميع الغرف المحجوزة لديها دفعات مسجلة');
      } else {
        s.writeln('✗ فحص الغرف بدون دفعات: ${noPayments.length} غرفة محجوزة بدون أي دفعة:');
        for (final b in noPayments) {
          final stayDays = b.checkinDate.isNotEmpty
              ? now.difference(DateTime.parse(b.checkinDate)).inDays
              : 0;
          s.writeln('  ✗ [${b.roomNumber}] ${b.guestName}: مستحق ${b.totalDueCached.toStringAsFixed(0)} ريال | مدفوع 0 | أقام $stayDays يوم ${stayDays >= 3 ? "⚠️ فترة طويلة بدون دفع!" : ""}');
        }
      }

      // --- ملخص التحقق ---
      final totalIssues = balanceErrors.length + negativeBalance.length + overpayments.length + noPayments.length;
      s.writeln();
      if (totalIssues == 0) {
        s.writeln('✓ ملخص التحقق: جميع الحسابات صحيحة — لا توجد مشاكل');
      } else {
        s.writeln('✗ ملخص التحقق: $totalIssues مشكلة تحتاج مراجعة');
        s.writeln('  - أخطاء التوازن: ${balanceErrors.length}');
        s.writeln('  - أرصدة سالبة: ${negativeBalance.length}');
        s.writeln('  - دفعات زائدة: ${overpayments.length}');
        s.writeln('  - غرف بدون دفعات: ${noPayments.length}');
      }

      // ═══════════════════════════════════════════════════════════
      //  13. مفهوم اليوم الفندقي — كيفية الاحتساب
      // ═══════════════════════════════════════════════════════════
      s.writeln();
      s.writeln('═══ اليوم الفندقي (Hotel Day) ═══');
      s.writeln('قاعدة الحسم: الساعة 14:00 (ظهراً)');
      s.writeln('اليوم الفندقي يمتد من 14:00 حتى 14:00 من اليوم التالي');
      s.writeln('التاريخ/الوقت الحالي: ${now.toIso8601String()}');
      final currentHotelDay = today; // مبسّط — التطبيق يحسب بال HotelTimeEngine
      s.writeln('اليوم الفندقي الحالي: $currentHotelDay');

      // الغرف التي يتغير يومها الفندقي قريباً (تنبيه)
      final timeToNext = DateTime(now.year, now.month, now.day, 14);
      final actualNext = now.isAfter(timeToNext)
          ? timeToNext.add(const Duration(days: 1))
          : timeToNext;
      final remaining = actualNext.difference(now);
      s.writeln('الوقت المتبقي لبداية يوم فندقي جديد: ${remaining.inHours} ساعة و${remaining.inMinutes % 60} دقيقة');

      // توزيع الحجوزات على أيام فندقية
      final hotelDayMap = <String, int>{};
      for (final b in activeBookings) {
        final hd = b.hotelDayCheckin;
        if (hd != null && hd.isNotEmpty) {
          hotelDayMap[hd] = (hotelDayMap[hd] ?? 0) + 1;
        }
      }
      if (hotelDayMap.isNotEmpty) {
        s.writeln();
        s.writeln('توزيع الحجوزات حسب يوم الدخول الفندقي:');
        for (final entry in hotelDayMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
          s.writeln('  $entry.key: ${entry.value} حجز');
        }
      }

      // ═══════════════════════════════════════════════════════════
      //  14. الموظفين والرواتب
      // ═══════════════════════════════════════════════════════════
      final employees = await (db.select(db.employees)
            ..where((e) => e.deletedAt.isNull()))
          .get();

      if (employees.isNotEmpty) {
        s.writeln();
        s.writeln('═══ الموظفين والرواتب (${employees.length}) ═══');

        final activeEmp =
            employees.where((e) => StatusUtils.isEmployeeActive(e.status)).length;
        final inactiveEmp = employees.length - activeEmp;
        s.writeln('نشط: $activeEmp | غير نشط: $inactiveEmp');

        // رواتب الموظفين النشطين
        for (final emp
            in employees.where((e) => StatusUtils.isEmployeeActive(e.status))) {
          s.writeln('  [${emp.id}] ${emp.name} | ${emp.position} | الراتب: ${emp.basicSalary.toStringAsFixed(0)} ريال | ${emp.phone}');
        }

        // دورات الرواتب النشطة
        final salaryCycles = await (db.select(db.salaryCycles)
              ..where((c) => c.status.equals('draft')))
            .get();
        if (salaryCycles.isNotEmpty) {
          s.writeln();
          s.writeln('دورات رواتب غير مكتملة (${salaryCycles.length}):');
          for (final c in salaryCycles) {
            final emp = employees.where((e) => e.id == c.employeeId).firstOrNull;
            final empName = emp?.name ?? 'موظف محذوف';
            s.writeln('  $empName | الدورة: ${c.cycleKey} | مستحق: ${c.expectedAmount} | مدفوع: ${c.actualPaid} | متبقي: ${c.remainingAmount}');
          }
        }

        // المسحوبات الأخيرة
        final recentWithdrawals = await (db.select(db.salaryWithdrawals)
              ..where((w) => w.deletedAt.isNull())
              ..orderBy([(w) => OrderingTerm.desc(w.id)]))
            .get();
        if (recentWithdrawals.isNotEmpty) {
          s.writeln();
          s.writeln('آخر المسحوبات (${recentWithdrawals.length.clamp(0, 5)}):');
          for (final w in recentWithdrawals.take(5)) {
            final emp = employees.where((e) => e.id == w.employeeId).firstOrNull;
            final empName = emp?.name ?? 'موظف محذوف';
            s.writeln('  $empName | ${w.amount.toStringAsFixed(0)} ريال | ${w.withdrawalType ?? "عادي"} | ${w.reason ?? ""} | ${w.withdrawDate}');
          }
        }

        // إجمالي الرواتب المستحقة
        final totalSalaries =
            employees.where((e) => StatusUtils.isEmployeeActive(e.status)).fold<double>(
                  0,
                  (s, e) => s + e.basicSalary,
                );
        s.writeln();
        s.writeln('إجمالي الرواتب الشهرية: ${totalSalaries.toStringAsFixed(0)} ريال');
      }

      // ═══════════════════════════════════════════════════════════
      //  15. التسويات المالية والاستحقاقات
      // ═══════════════════════════════════════════════════════════
      s.writeln();
      s.writeln('═══ التسويات المالية والاستحقاقات ═══');

      // حركات الصندوق اليوم
      final todayCashTransactions = await (db.select(db.cashTransactions)
            ..where((t) => t.transactionTime.like('$today%')))
          .get();
      final cashIn = todayCashTransactions.where((t) => t.transactionType == 'income')
          .fold<double>(0, (s, t) => s + t.amount);
      final cashOut = todayCashTransactions.where((t) => t.transactionType == 'expense')
          .fold<double>(0, (s, t) => s + t.amount);
      s.writeln('حركة الصندوق اليوم: دخول ${cashIn.toStringAsFixed(0)} | خروج ${cashOut.toStringAsFixed(0)} | صافي ${(cashIn - cashOut).toStringAsFixed(0)} ريال');
      if (todayCashTransactions.isNotEmpty) {
        final sorted = [...todayCashTransactions]..sort((a, b) => b.transactionTime.compareTo(a.transactionTime));
        final limit = sorted.length < 60 ? sorted.length : 60;
        s.writeln('تفاصيل حركة الصندوق اليوم (آخر $limit من ${sorted.length}):');
        for (final t in sorted.take(limit)) {
          final desc = (t.description != null && t.description!.trim().isNotEmpty) ? ' | ${t.description}' : '';
          s.writeln('  ${t.transactionType}: ${t.amount.toStringAsFixed(0)} ريال | ${t.transactionTime}$desc');
        }
      }

      // المدفوعات المعلقة (غير مُطابقة)
      final pendingPayments = todayPayments.where((p) => p.isPendingBalance == true).toList();
      if (pendingPayments.isNotEmpty) {
        s.writeln('مدفوعات معلقة (غير مُطابقة): ${pendingPayments.length}');
        for (final p in pendingPayments) {
          s.writeln('  ${p.roomNumber ?? "?"} | ${p.amount.toStringAsFixed(0)} ريال | ${p.paymentMethod} | ${p.notes ?? ""}');
        }
      } else {
        s.writeln('مدفوعات معلقة: لا توجد');
      }

      // المدفوعات الملغاة اليوم
      final voidedPayments = await (db.select(db.paymentVoids)
            ..where((v) => v.voidedAtIso.like('$today%')))
          .get();
      if (voidedPayments.isNotEmpty) {
        s.writeln('مدفوعات ملغاة اليوم: ${voidedPayments.length}');
        for (final v in voidedPayments) {
          s.writeln('  حجز ${v.bookingUuid} | ${v.voidedAmount} ريال | سبب: ${v.voidReason}');
        }
      }

      // أرصدة الديون حسب الجنسية
      if (debts.isNotEmpty) {
        final debtByReason = <String, double>{};
        for (final d in debts) {
          final reason = d.debtReason.isNotEmpty ? d.debtReason : 'أخرى';
          debtByReason[reason] = (debtByReason[reason] ?? 0) + d.remainingAmount;
        }
        s.writeln();
        s.writeln('توزيع الديون حسب السبب:');
        for (final entry in debtByReason.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
          s.writeln('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
        }
      }

      // استحقاقات الحجوزات (المتبقي المحصّل vs غير المحصّل)
      final collectedRemaining = activeBookings
          .where((b) => b.totalPaidCached > 0 && b.remainingBalanceCached < 0.5)
          .length;
      final uncollectedRemaining = activeBookings
          .where((b) => b.remainingBalanceCached >= 0.5)
          .length;
      s.writeln();
      s.writeln('استحقاقات الحجوزات: مكتملة $collectedRemaining | غير مكتملة $uncollectedRemaining');

      // ═══════════════════════════════════════════════════════════
      //  16. ترحيل البيانات (Data Rollover & Sync)
      // ═══════════════════════════════════════════════════════════
      s.writeln();
      s.writeln('═══ ترحيل البيانات والمزامنة ═══');

      // حالة دفتر اليوم الفندقي
      final todayLedger = await (db.select(db.hotelDayLedger)
            ..where((l) => l.hotelDayKey.equals(today)))
          .getSingleOrNull();
      if (todayLedger != null) {
        s.writeln('دفتر اليوم ($today):');
        s.writeln('  الحالة: ${todayLedger.status} | الدخل: ${todayLedger.totalIncome.toStringAsFixed(0)} | المصروفات: ${todayLedger.totalExpenses.toStringAsFixed(0)}');
        s.writeln('  الأرصدة المعلقة: ${todayLedger.pendingBalances.toStringAsFixed(0)} | الإشغال: ${todayLedger.occupancyRate.toStringAsFixed(0)}%');
        s.writeln('  حجوزات: ${todayLedger.bookingsProcessed} | مدفوعات: ${todayLedger.paymentsProcessed} | ديون: ${todayLedger.debtsProcessed} | مصروفات: ${todayLedger.expensesProcessed}');
      } else {
        s.writeln('دفتر اليوم ($today): لم يُرحّل بعد — يحتاج ترحيل');
      }

      // آخر عمليات AutoFix
      final recentAutoFix = await (db.select(db.autoFixRuns)
            ..orderBy([(a) => OrderingTerm.desc(a.startedAtEpoch)]))
          .get();
      if (recentAutoFix.isNotEmpty) {
        s.writeln();
        s.writeln('آخر عمليات الإصلاح التلقائي:');
        for (final run in recentAutoFix.take(3)) {
          final statusLabel = run.status == 'completed' ? '✓' : run.status == 'running' ? '⟳' : '✗';
          s.writeln('  $statusLabel ${run.source}: ${run.status} | ${run.startedAtIso}');
        }
      }

      // حالة المزامنة
      final pendingOutbox = await (db.select(db.outbox)
            ..where((o) => o.processingStatus.equals('pending')))
          .get();
      final failedOutbox = await (db.select(db.outbox)
            ..where((o) => o.processingStatus.equals('failed')))
          .get();
      s.writeln();
      s.writeln('حالة ترحيل البيانات للسيرفر:');
      s.writeln('  بانتظار الرفع: ${pendingOutbox.length}');
      s.writeln('  فشل الرفع: ${failedOutbox.length}');
      if (pendingOutbox.isNotEmpty) {
        final sorted = [...pendingOutbox]..sort((a, b) => b.clientTs.compareTo(a.clientTs));
        final limit = sorted.length < 50 ? sorted.length : 50;
        s.writeln('تفاصيل عناصر بانتظار الرفع (آخر $limit من ${sorted.length}):');
        for (final o in sorted.take(limit)) {
          final err = (o.lastError != null && o.lastError!.trim().isNotEmpty) ? ' | آخر خطأ: ${o.lastError}' : '';
          s.writeln('  ${o.entity}/${o.op} | uuid: ${o.localUuid} | محاولات: ${o.attempts} | مصدر: ${o.source} | الحالة: ${o.processingStatus}$err');
        }
      }
      if (failedOutbox.isNotEmpty) {
        final sorted = [...failedOutbox]..sort((a, b) => b.clientTs.compareTo(a.clientTs));
        final limit = sorted.length < 50 ? sorted.length : 50;
        s.writeln('تفاصيل عناصر فشل الرفع (آخر $limit من ${sorted.length}):');
        for (final o in sorted.take(limit)) {
          final err = (o.lastError != null && o.lastError!.trim().isNotEmpty) ? ' | آخر خطأ: ${o.lastError}' : '';
          s.writeln('  ${o.entity}/${o.op} | uuid: ${o.localUuid} | محاولات: ${o.attempts} | مصدر: ${o.source} | الحالة: ${o.processingStatus}$err');
        }
      }

      final syncStateRow = await (db.select(db.syncState)
            ..where((s) => s.id.equals(1)))
          .getSingleOrNull();
      if (syncStateRow != null) {
        s.writeln();
        s.writeln('حالة المزامنة المحلية (SyncState):');
        s.writeln('  آخر Pull: ${syncStateRow.lastPullTs} | آخر Push: ${syncStateRow.lastPushTs} | آخر ServerTs: ${syncStateRow.lastServerTs} | هل يجري مزامنة: ${syncStateRow.isSyncing}');
      }

      final syncQueuePending = await (db.select(db.syncQueue)
            ..where((q) => q.status.equals('pending')))
          .get();
      if (syncQueuePending.isNotEmpty) {
        s.writeln();
        s.writeln('طابور المزامنة (pending): ${syncQueuePending.length}');
        final limit = syncQueuePending.length < 50 ? syncQueuePending.length : 50;
        for (final q in syncQueuePending.take(limit)) {
          s.writeln('  ${q.targetTable}/${q.operation} | uuid: ${q.uuid} | ${q.createdAt} | جهاز: ${q.deviceId}');
        }
      }

      final recentSyncLogs = await (db.select(db.syncLog)
            ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
          .get();
      if (recentSyncLogs.isNotEmpty) {
        s.writeln();
        final limit = recentSyncLogs.length < 20 ? recentSyncLogs.length : 20;
        s.writeln('سجل المزامنة (آخر $limit):');
        for (final l in recentSyncLogs.take(limit)) {
          s.writeln('  ${l.direction} | جهاز: ${l.deviceId} | حالة: ${l.status} | ${l.createdAt} -> ${l.completedAt ?? "-"} | checksum: ${l.checksumMatched}');
        }
      }

      final recentConflicts = await (db.select(db.syncConflicts)
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
          .get();
      if (recentConflicts.isNotEmpty) {
        s.writeln();
        final limit = recentConflicts.length < 20 ? recentConflicts.length : 20;
        s.writeln('تعارضات المزامنة (آخر $limit):');
        for (final c in recentConflicts.take(limit)) {
          s.writeln('  ${c.targetTable} | uuid: ${c.uuid} | حل: ${c.resolution} | ${c.createdAt}');
        }
      }

      final restoreFixes = await (db.select(db.restoreFixLog)
            ..orderBy([(r) => OrderingTerm.desc(r.executedAt)]))
          .get();
      if (restoreFixes.isNotEmpty) {
        s.writeln();
        final limit = restoreFixes.length < 20 ? restoreFixes.length : 20;
        s.writeln('سجل إصلاحات الاستعادة (آخر $limit):');
        for (final r in restoreFixes.take(limit)) {
          s.writeln('  ${r.fixType} | ${r.targetTable}#${r.targetRecordId} | ${r.fieldName}: ${r.oldValue ?? "-"} -> ${r.newValue ?? "-"} | سبب: ${r.reason}');
        }
      }

      // BookingNights — ليالي مرحّلة
      final recentNights = await (db.select(db.bookingNights)
            ..orderBy([(n) => OrderingTerm.desc(n.hotelDayKey)]))
          .get();
      if (recentNights.isNotEmpty) {
        s.writeln();
        final limit = recentNights.length < 20 ? recentNights.length : 20;
        s.writeln('آخر الليالي المُرحّلة (أول $limit):');
        for (final n in recentNights.take(limit)) {
          s.writeln('  ${n.hotelDayKey}: غرفة محجوزة | سعر ${n.finalRate.toStringAsFixed(0)} ريال');
        }
      }

    } catch (e) {
      debugPrint('⚠️ خطأ في بناء سياق الفندق: $e');
      s.writeln('(تعذر تحميل بعض البيانات: $e)');
    }

    // تخزين السياق في الذاكرة المؤقتة
    _cachedContext = s.toString();
    _contextBuiltAt = DateTime.now();

    return _cachedContext!;
  }

  // ───────────────────────────────────────────────────────────
  //  إرسال رسالة والحصول على رد + أمر
  // ───────────────────────────────────────────────────────────

  /// إرسال رسالة مع retry تلقائي عند تجاوز حد الطلبات
  /// يستخدم ChatSession.sendMessage — النمط الرسمي من Firebase AI Logic
  /// ChatSession يدير سجل المحادثة تلقائياً (لا حاجة لإدارة يدوية)
  Future<GeminiResponse> chat(String userMessage) async {
    if (!isAvailable) {
      return const GeminiResponse(
        text: 'المساعد الذكي غير متاح. تأكد من تفعيل AI Logic في Firebase Console.',
      );
    }

    // ── Cooldown: منع الإرسال السريع ──
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _minRequestInterval) {
        final waitTime = _minRequestInterval - elapsed;
        debugPrint('⏳ انتظار ${waitTime.inSeconds + 1} ثانية قبل الطلب التالي...');
        await Future<void>.delayed(waitTime);
      }
    }

    try {
      // بناء السياق الحي من قاعدة البيانات
      final hotelContext = await _buildHotelContext();

      // دمج سياق الفندق مع رسالة المستخدم
      // ملاحظة: Gemini 2.5 Flash يتعامل بشكل أفضل مع السياق المنظم
      final fullMessage = 'سياق الفندق الحالي:\n$hotelContext\n\nطلب المستخدم: $userMessage';

      // ── إرسال عبر ChatSession — يدير التاريخ تلقائياً ──
      // تم تحسين _sendWithRetry للتعامل مع Gemini 2.5 Flash
      final response = await _sendWithRetry(
        () {
          _chat ??= _model!.startChat();
          return _chat!.sendMessage(Content.text(fullMessage));
        },
      );
      _lastRequestTime = DateTime.now();

      // ⚠️ response.text يرمي FirebaseAIException عند الحظر (لا يُرجع null!)
      String responseText;
      try {
        responseText = response.text ?? '';
      } on FirebaseAIException catch (e) {
        debugPrint('⚠️ response.text رمى استثناء: $e');
        // إذا كان الرد محظور بسبب السلامة — أعد المحاولة بدون سياق الفندق
        if (e.message.contains('SAFETY') ||
            e.message.contains('blocked')) {
          debugPrint('⚠️ الرد محظور — إعادة المحاولة برسالة المستخدم فقط');
          try {
            final retryResponse = await _sendWithRetry(
              () => _chat!.sendMessage(Content.text(userMessage)),
            );
            responseText = retryResponse.text ?? '';
          } catch (retryE) {
            responseText = _friendlyErrorMessage(retryE);
          }
        } else {
          responseText = _friendlyErrorMessage(e);
        }
      }
      _lastError = null;

      // تحليل الأمر من الرد
      final command = _parseCommand(responseText);
      final cleanText = _stripJsonFromResponse(responseText);

      // التقارير وإصلاح الدفعات تُنفذ فوراً بدون تأكيد
      if (command is AiReportCommand || command is AiFixPaymentsCommand) {
        final reportResult = await executeCommand(command!);
        return GeminiResponse(
          text: reportResult,
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
      _lastError = e.toString();
      // إعادة تعيين الجلسة عند خطأ في الأدوار
      final msg = e.toString();
      if (msg.contains('role') || msg.contains('alternat')) {
        debugPrint('⚠️ إعادة تعيين الجلسة بسبب خطأ في الأدوار');
        _chat = _model!.startChat();
      }
      return GeminiResponse(
        text: _friendlyErrorMessage(e),
      );
    }
  }

  /// تحديد رسالة الخطأ المناسبة حسب نوع الاستثناء
  String _friendlyErrorMessage(Object e) {
    final msg = e.toString();
    // فحص نوع الاستثناء + نص الرسالة للتعامل مع جميع الإصدارات
    if (e is QuotaExceeded ||
        msg.contains('QUOTA') ||
        msg.contains('RESOURCE_EXHAUSTED') ||
        msg.contains('429') ||
        msg.contains('rate limit')) {
      return 'تم تجاوز حد الطلبات. انتظر 30 ثانية ثم حاول مجدداً.';
    } else if (e is InvalidApiKey || msg.contains('API_KEY') || msg.contains('api key')) {
      return 'مفتاح Gemini API غير صالح. تأكد من تفعيل AI Logic في Firebase Console.';
    } else if (e is ServiceApiNotEnabled || msg.contains('not enabled') || msg.contains('NOT_FOUND')) {
      return 'خدمة AI Logic غير مفعلة في Firebase Console. راجع الإعدادات.';
    } else if (e is UnsupportedUserLocation || msg.contains('location') || msg.contains('region')) {
      return 'خدمة Gemini غير متاحة في منطقتك حالياً.';
    } else if (e is FirebaseAIException) {
      final firebaseMsg = e.message;
      // e.message قد يكون null — فحص أمان
      if (firebaseMsg.contains('SAFETY') || firebaseMsg.contains('blocked')) {
        return 'تم حظر الرد لأسباب أمنية. حاول صياغة السؤال بشكل مختلف.';
      } else if (firebaseMsg.contains('role') || firebaseMsg.contains('alternat')) {
        return 'حدث خطأ في سجل المحادثة. تم مسح السجل — حاول مجدداً.';
      } else if (firebaseMsg.contains('No content') || firebaseMsg.contains('empty')) {
        return 'لم يتم توليد رد. حاول إعادة صياغة السؤال.';
      }
          return 'خطأ من خدمة AI: $firebaseMsg';
    }
    return 'حدث خطأ أثناء معالجة طلبك: $e';
  }

  /// إعادة محاولة تلقائية مع exponential backoff عند تجاوز حد الطلبات
  /// يعمل مع أي نوع استثناء (QuotaExceeded, ServerException, أو عام)
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
        // فحص إذا كان الخطأ قابلاً لإعادة المحاولة
        final isRetryable = e is QuotaExceeded ||
            e is ServerException ||
            msg.contains('QUOTA') ||
            msg.contains('RESOURCE_EXHAUSTED') ||
            msg.contains('429') ||
            msg.contains('500') ||
            msg.contains('503');

        if (!isRetryable || attempt >= _maxRetries) {
          rethrow;
        }

        // حساب jitter عشوائي لمنع thundering herd
        final jitterMs = (_random.nextDouble() * delay.inMilliseconds * 0.3).round();
        final actualDelay = Duration(milliseconds: delay.inMilliseconds + jitterMs);

        debugPrint('⚠️ خطأ مؤقت — محاولة ${attempt + 1}/$_maxRetries، انتظار ${actualDelay.inSeconds} ثانية...');

        await Future<void>.delayed(actualDelay);

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
              'سعر الغرفة $roomNumber: ${oldPrice.toStringAsFixed(0)} -> ${newPrice.toStringAsFixed(0)} ريال',);
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
                    .clamp(0.0, double.infinity).toDouble();
              case 'fixed_increase':
                newPrice = oldPrice + value;
              case 'fixed_decrease':
                newPrice = (oldPrice - value).clamp(0.0, double.infinity).toDouble();
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
                  '${room.roomNumber}: ${oldPrice.toStringAsFixed(0)} -> ${newPrice.toStringAsFixed(0)}',);
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
              paymentMethod: const Value('cash'),
              revenueType: const Value('room_rent'),
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
              status: const Value('checked_out'),
              actualCheckout: Value(today),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );

          await (db.update(db.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))).write(
            RoomsCompanion(
              status: const Value('available'),
              updatedAt: Value(now.millisecondsSinceEpoch),
              lastModified: Value(now.millisecondsSinceEpoch),
              updatedAtIso: Value(now.toIso8601String()),
            ),
          );
          result =
              'تم إنهاء حجز الغرفة $roomNumber وتسجيل خروج الضيف ${activeBooking.guestName}';

        // ═══════════════════════════════════════════════════
        //  إصلاح دفعات غرفة — إعادة حساب كاملة
        // ═══════════════════════════════════════════════════
        case AiFixPaymentsCommand(:final roomNumber):
          final bookings = await (db.select(db.bookings)
            ..where((b) => b.roomNumber.equals(roomNumber))).get();
          final activeBooking =
              bookings.where((b) => b.status == 'checked_in').firstOrNull;
          if (activeBooking == null) {
            result = 'لا يوجد حجز نشط للغرفة $roomNumber';
            break;
          }

          // حفظ القيم قبل الإصلاح
          final oldPaid = activeBooking.totalPaidCached;
          final oldDue = activeBooking.totalDueCached;
          final oldRemaining = activeBooking.remainingBalanceCached;
          final oldNights = activeBooking.calculatedNights;

          // إعادة حساب كاملة عبر BookingDerivedFieldsService
          try {
            await BookingDerivedFieldsService(db)
                .refreshForBookingId(activeBooking.id, forceRebuild: true);
          } catch (e) {
            debugPrint('⚠️ خطأ في إعادة حساب الحجز: $e');
            result = 'فشل إعادة حساب الحجز $roomNumber: $e';
            break;
          }

          // قراءة القيم الجديدة بعد الإصلاح
          final refreshed = await (db.select(db.bookings)
            ..where((b) => b.id.equals(activeBooking.id)))
              .getSingleOrNull();

          if (refreshed == null) {
            result = 'فشل قراءة الحجد بعد الإصلاح';
            break;
          }

          final newPaid = refreshed.totalPaidCached;
          final newDue = refreshed.totalDueCached;
          final newRemaining = refreshed.remainingBalanceCached;
          final newNights = refreshed.calculatedNights;

          final changes = <String>[];
          if (oldNights != newNights) {
            changes.add('الليالي: $oldNights -> $newNights');
          }
          if ((oldDue - newDue).abs() > 0.5) {
            changes.add('المستحق: ${oldDue.toStringAsFixed(0)} -> ${newDue.toStringAsFixed(0)}');
          }
          if ((oldPaid - newPaid).abs() > 0.5) {
            changes.add('المدفوع: ${oldPaid.toStringAsFixed(0)} -> ${newPaid.toStringAsFixed(0)}');
          }
          if ((oldRemaining - newRemaining).abs() > 0.5) {
            changes.add('المتبقي: ${oldRemaining.toStringAsFixed(0)} -> ${newRemaining.toStringAsFixed(0)}');
          }

          if (changes.isEmpty) {
            result = 'تم فحص الغرفة $roomNumber — الحسابات صحيحة لا تحتاج إصلاح';
          } else {
            result = 'تم إصلاح حسابات الغرفة $roomNumber (${refreshed.guestName}):\n${changes.join('\n')}';
          }

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
                      d.isSettled.equals(0) & d.guestName.contains(guestName),))
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
              status: const Value('checked_in'),
              expectedNights: Value(expectedNights),
              calculatedNights: Value(expectedNights),
              discount: const Value(0),
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
              status: const Value('occupied'),
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
              db, reportType, command.dateFrom, command.dateTo,);

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
    ),);
  }

  // ───────────────────────────────────────────────────────────
  //  System Prompt
  // ───────────────────────────────────────────────────────────

  /// بناء System Prompt — عام ليُستخدم من خدمات أخرى
  String buildSystemPrompt() => _systemPromptImpl();

  String _buildSystemPrompt() => _systemPromptImpl();

  String _systemPromptImpl() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    return '''
أنت "ماريانا" — مساعد ذكي متقدم لنظام إدارة فندق Marina Hotel. أنت مستشار فندقي محترف يتحدث باللغة العربية فقط.

═══ هويتك ومهمتك ═══
أنت مساعد فندقي ذكي يعمل كمستشار مالي وإداري للفندق. تفهم بيانات الفندق في الوقت الفعلي وتقدم:
- إجابات دقيقة على الأسئلة بناءً على البيانات الحية
- تحليلات مالية وإحصائية ذكية
- نصائح لتحسين الإيرادات وإدارة الغرف
- تنبيهات تلقائية للمشاكل والفرص
- تنفيذ الأوامر على النظام عند طلب المستخدم

═══ قواعد الاستجابة ═══
- كن مختصراً ومفيداً — أجب بتركيز عالٍ دون إطالة
- استخدم البيانات الحالية المقدمة لك في كل طلب — لا تتخيل أرقاماً
- عند تقديم نصائح، استخدم الأرقام الفعلية من البيانات
- عند ذكر أرقام أو قوائم، اذكر اسم القسم الذي استندت عليه (مثال: "ملخص اليوم" أو "الحجوزات النشطة")
- اعرض النتائج بأسلوب مهني: ملخص تنفيذي (3–6 نقاط) ثم تفاصيل مرتبطة مباشرة بسؤال المستخدم ثم توصيات عملية قابلة للتنفيذ
- إذا طلب المستخدم تعديل بيانات، أجب بالشرح المختصر ثم أضف JSON للأمر في نهاية رسالتك
- لا تنفذ أوامر خطيرة (تعديل/حذف) بدون تأكيد المستخدم
- أوامر التقارير تُنفذ فوراً بدون تأكيد
- لا تضع JSON بين ``` فقط أرسله مباشرة في سطر منفصل
- المبالغ بالريال اليمني — الأرقام بدون فواصل (50000 وليس 50,000)

═══ قدراتك التحليلية ═══
بناءً على البيانات المقدمة لك، يمكنك:
1. تحليل الأداء المالي: مقارنة الإيرادات اليومية، حساب متوسط الإيرادات، تحليل الصافي
2. تحليل الإشغال: تحديد أنماط الإشغال، اقتراح أسعار ديناميكية
3. إدارة الديون: تحديد الديون الخطرة، اقتراح أولويات التحصيل
4. تحليل الضيوف: أنماط الجنسيات، متوسط مدة الإقامة، قيمة كل ضيف
5. التنبؤات: تنبيه لمغادرة الضيوف، تنبيه للغرف المتأخرة، توقعات الإيرادات
6. تحسين الإيرادات: اقتراح تعديل الأسعار بناءً على الطلب والإشغال
7. إدارة المخاطر: تنبيه للحوادث المالية، اكتشاف الأنماط غير الطبيعية
8. التحقق من الحسابات: مراجعة تلقائية لصحة الحسابات — تكتشف:
   - عدم توازن الحسابات (المتبقي ≠ التكلفة - المدفوع)
   - الأرصدة السالبة (المدفوع أكبر من المستحق)
   - الدفعات الزائدة عن التكلفة
   - الغرف المحجوزة بدون أي دفعة (مع تنبيه حسب مدة الإقامة)

═══ تنسيق البيانات ═══
يتم تزويدك ببيانات حية من الفندق تتضمن:
- بيانات الغرف: الأنواع والأسعار والحالات وتوزيع الأسعار
- الحجوزات النشطة: تفاصيل كاملة لكل ضيف مع الجنسية والمدفوعات
- الديون: إجمالي وتفاصيل كل دين مع معلومات الرهن
- الإيرادات والمصروفات: تفصيل حسب النوع وطريقة الدفع
- المؤشرات المالية: نسبة الإشغال، نسبة التحصيل، المتوسطات
- اتجاه الإيرادات: آخر 14 يوم لمقارنة الأداء
- دفتر اليوم الفندقي: ملخص يومي شامل
- ملاحظات الوردية: تنبيهات وملاحظات من الموظفين
- تعديلات الأسعار: سجل التغييرات الأخيرة
- التحقق من صحة الحسابات: 4 فحوصات تلقائية
- اليوم الفندقي: قاعدة 14:00 وتوزيع الحجوزات حسب الأيام
- الموظفين والرواتب: بيانات الموظفين ودورات الرواتب والمسحوبات
- التسويات المالية: حركات الصندوق والمدفوعات المعلقة والملغاة
- ترحيل البيانات: دفتر اليوم وAutoFix والمزامنة مع السيرفر وسجلات المزامنة والتعارضات

═══ صيغ JSON للأوامر المدعومة ═══

1. تغيير سعر غرفة (مع إعادة حساب الحجوزات النشطة تلقائياً):
{"action": "update_room_price", "room_number": "101", "new_price": 50000, "reason": "زيادة بسبب الموسم"}

2. تخفيض/زيادة جماعية لجميع الغرف أو نوع معين:
{"action": "bulk_price_adjust", "room_type": "double", "mode": "percent_increase", "value": 10, "reason": "زيادة موسمية"}
- mode: percent_increase, percent_decrease, fixed_increase, fixed_decrease
- room_type اختياري (إذا لم يُحدد يُطبق على جميع الغرف)

3. تخفيض على حجز معين (خصم ليلي أو إجمالي):
{"action": "booking_discount", "room_number": "101", "discount_amount": 5000, "discount_type": "per_night", "reason": "خصم خاص"}
- discount_type: per_night (لكل ليلة) أو total (إجمالي)

4. تغيير حالة غرفة:
{"action": "update_room_status", "room_number": "101", "new_status": "available"}

5. إضافة مصروف:
{"action": "add_expense", "expense_type": "صيانة", "description": "صيانة مكيف", "amount": 20000}

6. تسجيل دفعة:
{"action": "add_payment", "room_number": "101", "amount": 50000, "notes": "دفعة نقدية"}

7. إنهاء حجز (تسجيل خروج):
{"action": "checkout", "room_number": "101"}

8. إصلاح دفعات غرفة (إعادة حساب كاملة — لا يحتاج تأكيد):
{"action": "fix_payments", "room_number": "101"}
- يعيد حساب: الليالي، المستحقات، المدفوعات المخزّنة، المتبقي
- يُنفذ فوراً بدون تأكيد لأنه عملية مراجعة وليست تغييراً
- مثال: "أصلح دفعات غرفة 101" | "راجع حسابات 202" | "فحص دفعات الغرفة 303"

9. تسوية دين:
{"action": "settle_debt", "guest_name": "أحمد", "amount": 30000}

10. إضافة حجز جديد:
{"action": "add_booking", "room_number": "101", "guest_name": "أحمد محمد", "guest_phone": "777123456", "guest_nationality": "يمني", "checkin_date": "2025-01-15", "expected_nights": 2}

11. تحديث بيانات ضيف:
{"action": "update_booking_guest", "room_number": "101", "guest_name": "الاسم الجديد", "extend_nights": 1}

12. طلب تقرير (يُنفذ فوراً بدون تأكيد):
{"action": "report", "report_type": "daily"}
- report_type: daily, revenue, expenses, payroll, finance, occupancy, debts, room_prices
- date_from/date_to اختياريان بصيغة YYYY-MM-DD
- إذا أُرسل date_from فقط يتم اعتباره نفس date_to
- يمكن استخدام date_from بقيم: today, day, this_week, last_week, this_month, last_month, week, month

أمثلة:
{"action": "report", "report_type": "finance", "date_from": "2026-05-01", "date_to": "2026-05-31"}
{"action": "report", "report_type": "expenses", "date_from": "2026-05-10", "date_to": "2026-05-10"}
{"action": "report", "report_type": "payroll", "date_from": "today"}

═══ مرجع البيانات ═══
- حالات الغرف: available (شاغرة), occupied (محجوزة), cleaning (تنظيف), maintenance (صيانة), reserved (محجوزة مسبقاً)
- أنواع المصروفات: صيانة, طعام, كهرباء, ماء, تنظيف, نقل, أخرى
- أنواع الغرف: single, double, triple, suite, family
- طرق الدفع: cash (نقدي), transfer (تحويل), card (بطاقة), other (أخرى)
- أنواع الإيرادات: room_rent (إيجار غرفة), extra_services (خدمات إضافية), penalty (غرامات), other (أخرى)
- اليوم الفندقي: يبدأ من 14:00 ظهراً وينتهي 14:00 من اليوم التالي (قاعدة الحسم 14:00)
  - دخول قبل 14:00 يُحسب ضمن اليوم الفندقي السابق
  - دخول بعد 14:00 يُحسب ضمن يوم فندقي جديد
  - خروج بعد 14:00 يُحتسب كليالي إضافية
  - المفتاح بصيغة YYYY-MM-DD (مثال: 2025-01-15)
- ترحيل البيانات: كل يوم فندقي يُرحّل في دفتر اليوم (HotelDayLedger) الذي يخزن إجمالي الدخل والمصروفات والإشغال
- AutoFix: إصلاح تلقائي يُعيد حساب الليالي والمدفوعات عند تغيير الأسعار أو detect أخطاء
- تاريخ اليوم: $today''';
  }

  // ───────────────────────────────────────────────────────────
  //  تحليل JSON من رد Gemini
  // ───────────────────────────────────────────────────────────

  AiCommand? _parseCommand(String text) {
    try {
      // البحث عن JSON في النص — يدعم JSON متعدد الأسطر
      final jsonPattern = RegExp(r'\{[^{}]*\}', dotAll: true);
      final match = jsonPattern.firstMatch(text);
      if (match == null) {
        return null;
      }

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

        case 'fix_payments':
          return AiFixPaymentsCommand(
            roomNumber: json['room_number'] as String? ?? '',
            description: 'إصلاح دفعات الغرفة ${json['room_number']} — إعادة حساب كاملة',
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
        .replaceAll(RegExp('```'), '')
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
      final today = DateTime.now().toIso8601String().split('T')[0];

      String? resolvedFrom = dateFrom;
      String? resolvedTo = dateTo;

      if (resolvedFrom != null && resolvedTo == null) {
        resolvedTo = resolvedFrom;
      }

      if (resolvedFrom == 'today' || resolvedFrom == 'day') {
        resolvedFrom = today;
        resolvedTo = today;
      }

      if (resolvedFrom == 'week' || resolvedFrom == 'this_week') {
        final now = DateTime.now();
        final start = now.subtract(Duration(days: now.weekday - 1));
        resolvedFrom =
            '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
        resolvedTo = today;
      }

      if (resolvedFrom == 'last_week') {
        final now = DateTime.now();
        final startThisWeek = now.subtract(Duration(days: now.weekday - 1));
        final startLastWeek = startThisWeek.subtract(const Duration(days: 7));
        final endLastWeek = startThisWeek.subtract(const Duration(days: 1));
        resolvedFrom =
            '${startLastWeek.year}-${startLastWeek.month.toString().padLeft(2, '0')}-${startLastWeek.day.toString().padLeft(2, '0')}';
        resolvedTo =
            '${endLastWeek.year}-${endLastWeek.month.toString().padLeft(2, '0')}-${endLastWeek.day.toString().padLeft(2, '0')}';
      }

      if (resolvedFrom == 'month' || resolvedFrom == 'this_month') {
        final now = DateTime.now();
        resolvedFrom =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
        resolvedTo = today;
      }

      if (resolvedFrom == 'last_month') {
        final now = DateTime.now();
        final firstThisMonth = DateTime(now.year, now.month);
        final lastMonthEnd = firstThisMonth.subtract(const Duration(days: 1));
        final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month);
        resolvedFrom =
            '${lastMonthStart.year}-${lastMonthStart.month.toString().padLeft(2, '0')}-${lastMonthStart.day.toString().padLeft(2, '0')}';
        resolvedTo =
            '${lastMonthEnd.year}-${lastMonthEnd.month.toString().padLeft(2, '0')}-${lastMonthEnd.day.toString().padLeft(2, '0')}';
      }

      if (resolvedFrom == null && resolvedTo == null) {
        final now = DateTime.now();
        resolvedFrom =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
        resolvedTo = today;
      }

      switch (reportType) {
        case 'daily':
          return await _generateDailyReport(db);
        case 'revenue':
          return await _generateRevenueReport(db, resolvedFrom, resolvedTo);
        case 'occupancy':
          return await _generateOccupancyReport(db);
        case 'debts':
          return await _generateDebtsReport(db);
        case 'expenses':
          return await _generateExpensesReport(db, resolvedFrom, resolvedTo);
        case 'room_prices':
          return await _generateRoomPricesReport(db);
        case 'finance':
          return await _generateFinanceReport(db, resolvedFrom, resolvedTo);
        case 'payroll':
          return await _generatePayrollReport(db, resolvedFrom, resolvedTo);
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
          ..where((p) => p.paymentDate.like('$today%'))
          ..where((p) => p.deletedAt.isNull())
          ..where((p) => p.isVoided.equals(false)))
        .get();
    final totalIncome = todayPayments.fold<double>(0, (s, p) => s + p.amount);

    // المصروفات
    final todayExpenses = await (db.select(db.expenses)
          ..where((e) => e.date.like('$today%'))
          ..where((e) => e.deletedAt.isNull()))
        .get();
    final totalExpenses =
        todayExpenses.fold<double>(0, (s, e) => s + e.amount);

    final payrollPayments = await (db.select(db.salaryPayments)
          ..where((p) => p.paymentDateIso.like('$today%'))
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final payrollWithdrawals = await (db.select(db.salaryWithdrawals)
          ..where((w) => w.withdrawDate.like('$today%'))
          ..where((w) => w.deletedAt.isNull()))
        .get();
    final totalPayroll = payrollPayments.fold<int>(0, (s, p) => s + p.amount) +
        payrollWithdrawals.fold<double>(0, (s, w) => s + w.amount).round();

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
        '💰 الإيرادات: ${totalIncome.toStringAsFixed(0)} ريال (${todayPayments.length} دفعة)',);
    lines.add(
        '📉 المصروفات: ${totalExpenses.toStringAsFixed(0)} ريال (${todayExpenses.length} مصروف)',);
    lines.add('👥 الرواتب/السلف: ${totalPayroll.toStringAsFixed(0)} ريال',);
    lines.add(
        '📊 صافي الربح: ${(totalIncome - totalExpenses).toStringAsFixed(0)} ريال',);
    lines.add(
        '📌 صافي بعد الرواتب: ${(totalIncome - totalExpenses - totalPayroll).toStringAsFixed(0)} ريال',);
    lines.add('');
    lines.add(
        '🏠 إجمالي الغرف: $total | شاغرة: $available | مشغولة: $occupied',);
    lines.add('📈 نسبة الإشغال: $occRate%');

    // حجوزات جديدة اليوم
    final todayBookings = await (db.select(db.bookings)
          ..where((b) => b.checkinDate.like('$today%'))
          ..where((b) => b.deletedAt.isNull()))
        .get();
    lines.add('📋 حجوزات جديدة اليوم: ${todayBookings.length}');

    // خروج اليوم
    final todayCheckouts = await (db.select(db.bookings)
          ..where((b) => b.actualCheckout.like('$today%'))
          ..where((b) => b.deletedAt.isNull()))
        .get();
    lines.add('🚪 تسجيلات خروج اليوم: ${todayCheckouts.length}');

    final employees = await (db.select(db.employees)
          ..where((e) => e.deletedAt.isNull()))
        .get();
    if (employees.isNotEmpty) {
      final activeEmp =
          employees.where((e) => StatusUtils.isEmployeeActive(e.status)).length;
      final inactiveEmp = employees.length - activeEmp;
      lines.add('👤 الموظفون: إجمالي ${employees.length} | نشط $activeEmp | غير نشط $inactiveEmp');
    }

    return lines.join('\n');
  }

  Future<String> _generateRevenueReport(
      AppDatabase db, String? from, String? to,) async {
    final now = DateTime.now();
    final dateFrom =
        from ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final dateTo = to ?? now.toIso8601String().split('T')[0];
    final dateToEnd = '${dateTo}T23:59:59.999';

    final lines =
        <String>['💰 تقرير الإيرادات: $dateFrom إلى $dateTo', ''];

    final payments = await (db.select(db.payments)
          ..where((p) => p.paymentDate.isBiggerOrEqualValue(dateFrom))
          ..where((p) => p.paymentDate.isSmallerOrEqualValue(dateToEnd))
          ..where((p) => p.deletedAt.isNull())
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
        'إجمالي الإيرادات: ${totalIncome.toStringAsFixed(0)} ريال (${payments.length} دفعة)',);
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

  Future<String> _generatePayrollReport(
    AppDatabase db,
    String? from,
    String? to,
  ) async {
    final now = DateTime.now();
    final dateFrom =
        from ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final dateTo = to ?? now.toIso8601String().split('T')[0];
    final dateToEnd = '${dateTo}T23:59:59.999';

    final lines = <String>[
      '👥 تقرير الرواتب والموظفين: $dateFrom إلى $dateTo',
      '',
    ];

    final employees = await (db.select(db.employees)
          ..where((e) => e.deletedAt.isNull()))
        .get();
    if (employees.isNotEmpty) {
      final activeEmp =
          employees.where((e) => StatusUtils.isEmployeeActive(e.status)).length;
      final inactiveEmp = employees.length - activeEmp;
      final totalBaseSalaries = employees
          .where((e) => StatusUtils.isEmployeeActive(e.status))
          .fold<double>(0, (s, e) => s + e.basicSalary);
      lines.add('👤 الموظفون: إجمالي ${employees.length} | نشط $activeEmp | غير نشط $inactiveEmp');
      lines.add(
          '💼 إجمالي الرواتب الأساسية (للنشطين): ${totalBaseSalaries.toStringAsFixed(0)} ريال',);
    } else {
      lines.add('لا يوجد موظفون مسجلون.');
    }

    lines.add('');

    final salaryPayments = await (db.select(db.salaryPayments)
          ..where((p) => p.paymentDateIso.isBiggerOrEqualValue(dateFrom))
          ..where((p) => p.paymentDateIso.isSmallerOrEqualValue(dateToEnd))
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final withdrawals = await (db.select(db.salaryWithdrawals)
          ..where((w) => w.withdrawDate.isBiggerOrEqualValue(dateFrom))
          ..where((w) => w.withdrawDate.isSmallerOrEqualValue(dateToEnd))
          ..where((w) => w.deletedAt.isNull()))
        .get();

    final totalSalaryPayments =
        salaryPayments.fold<int>(0, (s, p) => s + p.amount);
    final totalWithdrawals =
        withdrawals.fold<double>(0, (s, w) => s + w.amount).round();

    lines.add(
        '💸 مدفوعات رواتب خلال الفترة: ${totalSalaryPayments.toStringAsFixed(0)} ريال (${salaryPayments.length})',);
    lines.add(
        '💳 سلف/مسحوبات خلال الفترة: ${totalWithdrawals.toStringAsFixed(0)} ريال (${withdrawals.length})',);
    lines.add(
        '📌 إجمالي المصروف على الموظفين: ${(totalSalaryPayments + totalWithdrawals).toStringAsFixed(0)} ريال',);

    if (employees.isNotEmpty && (salaryPayments.isNotEmpty || withdrawals.isNotEmpty)) {
      final byEmpPaid = <int, double>{};
      final cycles = await db.select(db.salaryCycles).get();
      final cycleById = {for (final c in cycles) c.id: c};

      for (final p in salaryPayments) {
        final cycle = cycleById[p.cycleId];
        if (cycle != null) {
          byEmpPaid[cycle.employeeId] =
              (byEmpPaid[cycle.employeeId] ?? 0) + p.amount;
        }
      }
      for (final w in withdrawals) {
        byEmpPaid[w.employeeId] = (byEmpPaid[w.employeeId] ?? 0) + w.amount;
      }

      final empById = {for (final e in employees) e.id: e};
      final sorted = byEmpPaid.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      lines.add('');
      lines.add('تفصيل حسب الموظف (الأعلى أولاً):');
      final limit = sorted.length < 50 ? sorted.length : 50;
      for (final entry in sorted.take(limit)) {
        final emp = empById[entry.key];
        final name = emp?.name ?? 'موظف غير معروف';
        final pos = emp?.position ?? '';
        lines.add(
            '  $name ${pos.isNotEmpty ? "($pos)" : ""}: ${entry.value.toStringAsFixed(0)} ريال',);
      }
      if (sorted.length > limit) {
        lines.add('  ... (${sorted.length - limit} موظف/سجل آخر)');
      }
    }

    if (employees.isNotEmpty) {
      lines.add('');
      lines.add('قائمة الموظفين (مختصر):');
      final active = employees
          .where((e) => StatusUtils.isEmployeeActive(e.status))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final inactive = employees
          .where((e) => !StatusUtils.isEmployeeActive(e.status))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final showActive = active.length < 60 ? active.length : 60;
      for (final e in active.take(showActive)) {
        lines.add(
            '  ✓ ${e.name} | ${e.position} | ${e.basicSalary.toStringAsFixed(0)} ريال | ${e.phone}',);
      }
      if (active.length > showActive) {
        lines.add('  ... (${active.length - showActive} موظف نشط آخر)');
      }

      if (inactive.isNotEmpty) {
        final showInactive = inactive.length < 30 ? inactive.length : 30;
        lines.add('');
        lines.add('غير النشطين (أول $showInactive):');
        for (final e in inactive.take(showInactive)) {
          lines.add('  ✗ ${e.name} | ${e.position} | ${e.phone}');
        }
        if (inactive.length > showInactive) {
          lines.add('  ... (${inactive.length - showInactive} موظف غير نشط آخر)');
        }
      }
    }

    return lines.join('\n');
  }

  Future<String> _generateFinanceReport(
    AppDatabase db,
    String? from,
    String? to,
  ) async {
    final now = DateTime.now();
    final dateFrom =
        from ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final dateTo = to ?? now.toIso8601String().split('T')[0];
    final dateToEnd = '${dateTo}T23:59:59.999';

    final lines = <String>[
      '📊 تقرير مالي شامل: $dateFrom إلى $dateTo',
      '',
    ];

    final payments = await (db.select(db.payments)
          ..where((p) => p.paymentDate.isBiggerOrEqualValue(dateFrom))
          ..where((p) => p.paymentDate.isSmallerOrEqualValue(dateToEnd))
          ..where((p) => p.deletedAt.isNull())
          ..where((p) => p.isVoided.equals(false)))
        .get();

    final expenses = await (db.select(db.expenses)
          ..where((e) => e.date.isBiggerOrEqualValue(dateFrom))
          ..where((e) => e.date.isSmallerOrEqualValue(dateToEnd))
          ..where((e) => e.deletedAt.isNull()))
        .get();

    final salaryPayments = await (db.select(db.salaryPayments)
          ..where((p) => p.paymentDateIso.isBiggerOrEqualValue(dateFrom))
          ..where((p) => p.paymentDateIso.isSmallerOrEqualValue(dateToEnd))
          ..where((p) => p.deletedAt.isNull()))
        .get();
    final withdrawals = await (db.select(db.salaryWithdrawals)
          ..where((w) => w.withdrawDate.isBiggerOrEqualValue(dateFrom))
          ..where((w) => w.withdrawDate.isSmallerOrEqualValue(dateToEnd))
          ..where((w) => w.deletedAt.isNull()))
        .get();

    final totalIncome = payments.fold<double>(0, (s, p) => s + p.amount);
    final totalExpenses = expenses.fold<double>(0, (s, e) => s + e.amount);
    final totalPayroll =
        salaryPayments.fold<int>(0, (s, p) => s + p.amount) +
            withdrawals.fold<double>(0, (s, w) => s + w.amount).round();

    final netBeforePayroll = totalIncome - totalExpenses;
    final netAfterPayroll = netBeforePayroll - totalPayroll;

    lines.add('ملخص تنفيذي:');
    lines.add('  - الإيرادات: ${totalIncome.toStringAsFixed(0)} ريال (${payments.length})');
    lines.add('  - المصروفات: ${totalExpenses.toStringAsFixed(0)} ريال (${expenses.length})');
    lines.add('  - الرواتب/السلف: ${totalPayroll.toStringAsFixed(0)} ريال');
    lines.add('  - صافي قبل الرواتب: ${netBeforePayroll.toStringAsFixed(0)} ريال');
    lines.add('  - صافي بعد الرواتب: ${netAfterPayroll.toStringAsFixed(0)} ريال');

    final byRevenueType = <String, double>{};
    final byPayMethod = <String, double>{};
    for (final p in payments) {
      byRevenueType[p.revenueType] =
          (byRevenueType[p.revenueType] ?? 0) + p.amount;
      byPayMethod[p.paymentMethod] =
          (byPayMethod[p.paymentMethod] ?? 0) + p.amount;
    }

    final byExpenseType = <String, double>{};
    for (final e in expenses) {
      byExpenseType[e.expenseType] =
          (byExpenseType[e.expenseType] ?? 0) + e.amount;
    }

    lines.add('');
    lines.add('تفصيل الإيرادات حسب النوع:');
    for (final entry in byRevenueType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))) {
      lines.add('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
    }

    lines.add('');
    lines.add('تفصيل الإيرادات حسب طريقة الدفع:');
    for (final entry in byPayMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))) {
      lines.add('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
    }

    lines.add('');
    lines.add('تفصيل المصروفات حسب الفئة:');
    for (final entry in byExpenseType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value))) {
      lines.add('  ${entry.key}: ${entry.value.toStringAsFixed(0)} ريال');
    }

    lines.add('');
    lines.add(await _generatePayrollReport(db, dateFrom, dateTo));

    return lines.join('\n');
  }

  Future<String> _generateOccupancyReport(AppDatabase db) async {
    final lines = <String>['📈 تقرير نسبة الإشغال', ''];

    final allRooms = await db.select(db.rooms).get();
    final activeRooms = allRooms.where((r) => r.deletedAt == null).toList();
    final total = activeRooms.length;

    if (total == 0) {
      return 'لا توجد غرف مسجلة';
    }

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
        'مشغولة: $occupied (${(occupied * 100 / total).toStringAsFixed(1)}%)',);
    lines.add(
        'شاغرة: $available (${(available * 100 / total).toStringAsFixed(1)}%)',);
    lines.add(
        'تنظيف: $cleaning (${(cleaning * 100 / total).toStringAsFixed(1)}%)',);
    lines.add(
        'صيانة: $maintenance (${(maintenance * 100 / total).toStringAsFixed(1)}%)',);
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
        'إجمالي المبالغ المتبقية: ${totalDebt.toStringAsFixed(0)} ريال',);
    lines.add(
        'إجمالي المدفوع: ${totalPaid.toStringAsFixed(0)} ريال',);
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
      AppDatabase db, String? from, String? to,) async {
    final now = DateTime.now();
    final dateFrom =
        from ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final dateTo = to ?? now.toIso8601String().split('T')[0];
    final dateToEnd = '${dateTo}T23:59:59.999';

    final lines =
        <String>['📉 تقرير المصروفات: $dateFrom إلى $dateTo', ''];

    final expenses = await (db.select(db.expenses)
          ..where((e) => e.date.isBiggerOrEqualValue(dateFrom))
          ..where((e) => e.date.isSmallerOrEqualValue(dateToEnd))
          ..where((e) => e.deletedAt.isNull())))
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
        'إجمالي المصروفات: ${totalExpenses.toStringAsFixed(0)} ريال (${expenses.length} مصروف)',);
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
      if (r.price < minPrice) {
        minPrice = r.price;
      }
      if (r.price > maxPrice) {
        maxPrice = r.price;
      }
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
          '${entry.key} (${rooms.length} غرف — متوسط ${typeAvg.toStringAsFixed(0)}):',);
      for (final r
          in rooms..sort((a, b) => a.roomNumber.compareTo(b.roomNumber))) {
        final statusEmoji = r.status == 'available'
            ? '✅'
            : (r.status == 'occupied' ? '🔴' : '⚪');
        lines.add(
            '  $statusEmoji ${r.roomNumber}: ${r.price.toStringAsFixed(0)} ريال (${r.status})',);
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

  const GeminiResponse({
    required this.text,
    this.command,
    this.requiresConfirmation = false,
  });
  final String text;
  final AiCommand? command;
  final bool requiresConfirmation;
}

class ChatMessage {

  ChatMessage({
    required this.id,
    required this.text,
    this.isUser = false,
    this.pendingCommand,
    DateTime? timestamp,
    this.isExecuted = false,
    this.executionResult,
  }) : timestamp = timestamp ?? DateTime.now();
  final String id;
  final String text;
  final bool isUser;
  final AiCommand? pendingCommand;
  final DateTime timestamp;
  final bool isExecuted;
  final String? executionResult;

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
