import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/env.dart';
import 'gemini_service.dart'; // لاستخدام AiCommand و GeminiResponse و AiAuditLog

// ═══════════════════════════════════════════════════════════════
//  خدمة AgentRouter AI — عميل OpenAI-compatible API
//  تستخدم واجهة برمجة تطبيقات متوافقة مع OpenAI (مثل OpenRouter)
//  كبديل لـ Gemini AI عبر Firebase AI Logic
// ═══════════════════════════════════════════════════════════════

class AgentRouterService {
  AgentRouterService._();
  static final AgentRouterService _instance = AgentRouterService._();
  static AgentRouterService get instance => _instance;

  /// عميل HTTP
  late final Dio _dio;

  /// هل تم التهيئة بنجاح؟
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// سجل المحادثة (يُدار يدوياً لأن API لا يديره تلقائياً)
  final List<Map<String, String>> _chatHistory = [];

  /// آخر خطأ
  String? _lastError;
  String? get lastError => _lastError;

  /// آخر خطأ في التهيئة
  String? _initError;
  String? get initError => _initError;

  /// اسم النموذج المستخدم
  String _model = 'google/gemini-2.5-flash-preview:thinking';

  /// قائمة النماذج المتاحة
  static const List<Map<String, String>> availableModels = [
    {'id': 'google/gemini-2.5-flash-preview:thinking', 'name': 'Gemini 2.5 Flash (Thinking)'},
    {'id': 'google/gemini-2.5-pro-preview', 'name': 'Gemini 2.5 Pro'},
    {'id': 'anthropic/claude-sonnet-4', 'name': 'Claude Sonnet 4'},
    {'id': 'openai/gpt-4o', 'name': 'GPT-4o'},
    {'id': 'openai/gpt-4o-mini', 'name': 'GPT-4o Mini'},
    {'id': 'deepseek/deepseek-r1', 'name': 'DeepSeek R1'},
  ];

  /// System prompt — يُعيد استخدام نفس prompt من GeminiService
  String? _systemPrompt;

  /// تهيئة الخدمة
  Future<void> initialize({bool forceRetry = false}) async {
    if (_isInitialized && !forceRetry) return;

    if (forceRetry) {
      _isInitialized = false;
      _initError = null;
      _lastError = null;
    }

    const apiKey = Env.agentRouterApiKey;
    const baseUrl = Env.agentRouterBaseUrl;

    if (apiKey.isEmpty) {
      _initError = 'مفتاح AgentRouter API غير مُعرَّف — أضفه عبر --dart-define=AGENT_ROUTER_API_KEY';
      debugPrint('⚠️ $_initError');
      return;
    }

    try {
      _dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://marina-hotel.app',
          'X-Title': 'Marina Hotel AI Assistant',
        },
      ));

      // بناء system prompt (نفس المستخدم في GeminiService)
      _systemPrompt = GeminiService.instance.buildSystemPrompt();

      _isInitialized = true;
      _lastError = null;
      debugPrint('✅ تم تهيئة AgentRouter AI — النموذج: $_model');
    } catch (e) {
      _initError = 'فشل تهيئة AgentRouter: $e';
      _lastError = _initError;
      debugPrint('⚠️ $_initError');
    }
  }

  /// تغيير النموذج
  void setModel(String modelId) {
    _model = modelId;
    _chatHistory.clear(); // مسح السجل عند تغيير النموذج
    debugPrint('🔄 تم تغيير نموذج AgentRouter إلى: $modelId');
  }

  /// الحصول على النموذج الحالي
  String get currentModel => _model;

  /// إعادة تعيين الحالة
  void reset() {
    _chatHistory.clear();
    _isInitialized = false;
    _initError = null;
    _lastError = null;
  }

  /// مسح سجل المحادثة
  void clearHistory() {
    _chatHistory.clear();
  }

  /// هل الخدمة متاحة؟
  bool get isAvailable => _isInitialized;

  // ───────────────────────────────────────────────────────────
  //  إرسال رسالة والحصول على رد
  // ───────────────────────────────────────────────────────────

  /// إرسال رسالة مع السياق الحي
  Future<GeminiResponse> chat(String userMessage, String hotelContext) async {
    if (!_isInitialized) {
      return const GeminiResponse(
        text: 'خدمة AgentRouter غير متاحة. تأكد من توفير مفتاح API صالح.',
      );
    }

    try {
      // دمج السياق مع رسالة المستخدم
      final fullMessage = 'سياق الفندق الحالي:\n$hotelContext\n\nطلب المستخدم: $userMessage';

      // إضافة رسالة المستخدم للسجل
      _chatHistory.add({'role': 'user', 'content': fullMessage});

      // بناء قائمة الرسائل
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': _systemPrompt ?? 'أنت مساعد ذكي لنظام إدارة فندق.'},
        ..._chatHistory,
      ];

      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/completions',
        data: {
          'model': _model,
          'messages': messages,
          'temperature': 0.2,
          'top_p': 0.9,
          'max_tokens': 4096,
        },
      );

      final data = response.data;
      if (data == null) {
        _chatHistory.removeLast(); // إزالة الرسالة عند الفشل
        return const GeminiResponse(text: 'لم يتم استلام رد من الخادم.');
      }

      // استخراج الرد
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        _chatHistory.removeLast();
        return const GeminiResponse(text: 'لم يتم استلام رد من النموذج.');
      }

      final message = choices[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String? ?? '';

      // إضافة رد المساعد للسجل
      _chatHistory.add({'role': 'assistant', 'content': content});

      _lastError = null;

      // تحليل الأمر من الرد (نفس المنطق المستخدم في GeminiService)
      final command = _parseCommand(content);
      final cleanText = _stripJsonFromResponse(content);

      // التقارير وإصلاح الدفعات تُنفذ فوراً بدون تأكيد
      if (command is AiReportCommand || command is AiFixPaymentsCommand) {
        final reportResult = await GeminiService.instance.executeCommand(command!);
        return GeminiResponse(text: reportResult);
      }

      return GeminiResponse(
        text: cleanText,
        command: command,
        requiresConfirmation: command != null && command is! AiNoActionCommand && command is! AiQueryCommand,
      );
    } on DioException catch (e) {
      _chatHistory.removeLast(); // إزالة رسالة المستخدم عند الفشل
      final errorMsg = _handleDioError(e);
      _lastError = errorMsg;
      return GeminiResponse(text: errorMsg);
    } catch (e) {
      _chatHistory.removeLast();
      _lastError = 'خطأ غير متوقع: $e';
      return GeminiResponse(text: _lastError!);
    }
  }

  // ───────────────────────────────────────────────────────────
  //  معالجة أخطاء Dio
  // ───────────────────────────────────────────────────────────

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'انتهت مهلة الاتصال — تحقق من الإنترنت وحاول مرة أخرى.';
      case DioExceptionType.connectionError:
        return 'لا يمكن الاتصال بالخادم — تحقق من الإنترنت.';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;
        if (statusCode == 401) {
          return 'مفتاح API غير صالح — تحقق من AGENT_ROUTER_API_KEY.';
        } else if (statusCode == 402) {
          return 'رصيد غير كافٍ — تحقق من حسابك على AgentRouter/OpenRouter.';
        } else if (statusCode == 429) {
          return 'تم تجاوز حد الطلبات — انتظر قليلاً ثم حاول مرة أخرى.';
        } else if (statusCode == 404) {
          return 'النموذج غير موجود — تحقق من اسم النموذج: $_model';
        } else if (statusCode != null && statusCode >= 500) {
          return 'خطأ في الخادم ($statusCode) — حاول مرة أخرى لاحقاً.';
        }
        // محاولة استخراج رسالة الخطأ من الرد
        if (data is Map<String, dynamic>) {
          final error = data['error'] as Map<String, dynamic>?;
          final message = error?['message'] as String?;
          if (message != null) {
            return 'خطأ: $message';
          }
        }
        return 'خطأ في الاستجابة ($statusCode).';
      case DioExceptionType.cancel:
        return 'تم إلغاء الطلب.';
      default:
        return 'خطأ في الاتصال: ${e.message}';
    }
  }

  // ───────────────────────────────────────────────────────────
  //  تحليل الأوامر من الرد (نفس المنطق من GeminiService)
  // ───────────────────────────────────────────────────────────

  /// تحليل أمر JSON من رد AI
  AiCommand? _parseCommand(String responseText) {
    try {
      // البحث عن JSON في الرد
      final jsonRegex = RegExp(r'\{[^{}]*"action"\s*:\s*"[^"]+ "[^{}]*\}');
      final match = jsonRegex.firstMatch(responseText);

      String? jsonStr;
      if (match != null) {
        jsonStr = match.group(0);
      } else {
        // محاولة البحث عن JSON بين أقواس أكبر
        final braceStart = responseText.lastIndexOf('{');
        final braceEnd = responseText.indexOf('}', braceStart);
        if (braceStart != -1 && braceEnd != -1 && braceEnd > braceStart) {
          jsonStr = responseText.substring(braceStart, braceEnd + 1);
        }
      }

      if (jsonStr == null) return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final action = json['action'] as String?;

      if (action == null) return null;

      return _mapActionToCommand(action, json);
    } catch (e) {
      debugPrint('⚠️ خطأ في تحليل أمر AI: $e');
      return null;
    }
  }

  /// تحويل الإجراء إلى كائن أمر
  AiCommand? _mapActionToCommand(String action, Map<String, dynamic> json) {
    switch (action) {
      case 'update_room_price':
        return AiUpdateRoomPriceCommand(
          roomNumber: json['room_number'] as String? ?? '',
          newPrice: (json['new_price'] as num?)?.toDouble() ?? 0,
          reason: json['reason'] as String?,
          description: 'تغيير سعر غرفة ${json['room_number']} إلى ${json['new_price']}',
        );
      case 'bulk_price_adjust':
        return AiBulkPriceAdjustCommand(
          roomType: json['room_type'] as String?,
          mode: json['mode'] as String? ?? 'percent_increase',
          value: (json['value'] as num?)?.toDouble() ?? 0,
          reason: json['reason'] as String?,
          description: 'تعديل جماعي للأسعار',
        );
      case 'booking_discount':
        return AiBookingDiscountCommand(
          roomNumber: json['room_number'] as String? ?? '',
          discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
          discountType: json['discount_type'] as String? ?? 'total',
          reason: json['reason'] as String?,
          description: 'خصم على حجز غرفة ${json['room_number']}',
        );
      case 'update_room_status':
        return AiUpdateRoomStatusCommand(
          roomNumber: json['room_number'] as String? ?? '',
          newStatus: json['new_status'] as String? ?? 'available',
          description: 'تغيير حالة غرفة ${json['room_number']}',
        );
      case 'add_expense':
        return AiAddExpenseCommand(
          expenseType: json['expense_type'] as String? ?? 'أخرى',
          desc: json['description'] as String? ?? '',
          amount: (json['amount'] as num?)?.toDouble() ?? 0,
          description: 'إضافة مصروف ${json['expense_type']}',
        );
      case 'add_payment':
        return AiAddPaymentCommand(
          roomNumber: json['room_number'] as String? ?? '',
          amount: (json['amount'] as num?)?.toDouble() ?? 0,
          notes: json['notes'] as String?,
          description: 'تسجيل دفعة لغرفة ${json['room_number']}',
        );
      case 'checkout':
        return AiCheckoutCommand(
          roomNumber: json['room_number'] as String? ?? '',
          description: 'إنهاء حجز غرفة ${json['room_number']}',
        );
      case 'fix_payments':
        return AiFixPaymentsCommand(
          roomNumber: json['room_number'] as String? ?? '',
          description: 'إصلاح دفعات غرفة ${json['room_number']}',
        );
      case 'settle_debt':
        return AiSettleDebtCommand(
          debtId: json['debt_id'] as int?,
          guestName: json['guest_name'] as String? ?? '',
          amount: (json['amount'] as num?)?.toDouble() ?? 0,
          description: 'تسوية دين ${json['guest_name']}',
        );
      case 'add_booking':
        return AiAddBookingCommand(
          roomNumber: json['room_number'] as String? ?? '',
          guestName: json['guest_name'] as String? ?? '',
          guestPhone: json['guest_phone'] as String? ?? '',
          guestNationality: json['guest_nationality'] as String? ?? '',
          checkinDate: json['checkin_date'] as String? ?? '',
          expectedNights: (json['expected_nights'] as num?)?.toInt() ?? 1,
          price: (json['price'] as num?)?.toDouble(),
          description: 'إضافة حجز جديد لغرفة ${json['room_number']}',
        );
      case 'update_booking_guest':
        return AiUpdateBookingGuestCommand(
          roomNumber: json['room_number'] as String? ?? '',
          guestName: json['guest_name'] as String?,
          guestPhone: json['guest_phone'] as String?,
          extendNights: (json['extend_nights'] as num?)?.toInt(),
          description: 'تحديث بيانات ضيف غرفة ${json['room_number']}',
        );
      case 'report':
        return AiReportCommand(
          reportType: json['report_type'] as String? ?? 'daily',
          dateFrom: json['date_from'] as String?,
          dateTo: json['date_to'] as String?,
          description: 'طلب تقرير ${json['report_type']}',
        );
      default:
        debugPrint('⚠️ إجراء غير معروف: $action');
        return null;
    }
  }

  /// إزالة JSON من نص الرد
  String _stripJsonFromResponse(String responseText) {
    // إزالة كتل JSON من الرد
    var cleanText = responseText.replaceAllMapped(
      RegExp(r'\{[^{}]*"action"\s*:\s*"[^"]+"[^{}]*\}'),
      (match) => '',
    );

    // إزالة الأسطر الفارغة المتعددة
    cleanText = cleanText.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    // إذا أصبح النص فارغاً بعد الإزالة، أعد النص الأصلي بدون JSON block الأخير
    if (cleanText.isEmpty) {
      final lastBrace = responseText.lastIndexOf('{');
      if (lastBrace > 0) {
        return responseText.substring(0, lastBrace).trim();
      }
      return responseText;
    }

    return cleanText;
  }
}
