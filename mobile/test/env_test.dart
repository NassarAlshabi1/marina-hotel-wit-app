// ============================================================================
//  Env — Unit Tests
//  ============================================================================
//  اختبارات Env (إدارة المتغيرات البيئية):
//    - جميع الحقول الافتراضية فارغة (لا تسرّب أسراراً)
//    - convenience checks تُرجع false عندما تكون الحقول فارغة
//    - defaultValue لـ agentRouterBaseUrl و posthogHost صحيحة
// ============================================================================

library marina_hotel_mobile.test.env_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/env.dart';

void main() {
  // ملاحظة: هذه الاختبارات تعتمد على القيم الافتراضية لـ --dart-define
  // في بيئة CI، لا تُمرّر أي --dart-define، لذا جميعها يجب أن تكون فارغة.

  group('Env - default values (no --dart-define)', () {
    // ✅ (2026-09-17) طلب المالك: توكن/محادثة بوت الفندق مدمجة كقيم
    // افتراضية حتى تعمل إشعارات Telegram من أول تشغيل بلا --dart-define
    // (تمرير --dart-define يظل يتجاوزها).
    test('telegramBotToken له قيمة افتراضية مدمجة (بوت الفندق)', () {
      expect(Env.telegramBotToken, isNotEmpty);
      expect(Env.telegramBotToken, startsWith('7602573830:'));
    });

    test('telegramChatId له قيمة افتراضية مدمجة', () {
      expect(Env.telegramChatId, isNotEmpty);
      expect(Env.telegramChatId, '5944227208');
    });

    test('whatsappPhoneNumber فارغ افتراضياً', () {
      expect(Env.whatsappPhoneNumber, isEmpty);
    });

    test('whatsappApiKey فارغ افتراضياً', () {
      expect(Env.whatsappApiKey, isEmpty);
    });

    test('whatsappApiToken فارغ افتراضياً', () {
      expect(Env.whatsappApiToken, isEmpty);
    });

    test('whatsappInstanceId فارغ افتراضياً', () {
      expect(Env.whatsappInstanceId, isEmpty);
    });

    test('hotelContactPhone فارغ افتراضياً', () {
      expect(Env.hotelContactPhone, isEmpty);
    });

    test('agentRouterApiKey فارغ افتراضياً', () {
      expect(Env.agentRouterApiKey, isEmpty);
    });

    test('fcmServerKey فارغ افتراضياً', () {
      expect(Env.fcmServerKey, isEmpty);
    });

    test('posthogApiKey فارغ افتراضياً', () {
      expect(Env.posthogApiKey, isEmpty);
    });
  });

  group('Env - default values with defaults', () {
    test('agentRouterBaseUrl له default value صحيحة', () {
      expect(Env.agentRouterBaseUrl, 'https://openrouter.ai/api/v1');
    });

    test('posthogHost له default value صحيحة', () {
      expect(Env.posthogHost, 'https://us.i.posthog.com');
    });
  });

  group('Env - convenience checks', () {
    // ✅ (2026-09-17) مع القيم الافتراضية المدمجة أعلاه صار Telegram
    // مهيأاً من اللحظة الأولى (isConfigured = true بلا --dart-define).
    test('isTelegramConfigured = true افتراضياً (قيم مدمجة)', () {
      expect(Env.isTelegramConfigured, isTrue);
    });

    test('isWhatsAppCallMeBotConfigured = false افتراضياً', () {
      expect(Env.isWhatsAppCallMeBotConfigured, isFalse);
    });

    test('isWhatsAppGreenApiConfigured = false افتراضياً', () {
      expect(Env.isWhatsAppGreenApiConfigured, isFalse);
    });

    test('isApiConfigured = false افتراضياً', () {
      expect(Env.isApiConfigured, isFalse);
    });

    test('isAgentRouterConfigured = false افتراضياً', () {
      expect(Env.isAgentRouterConfigured, isFalse);
    });

    test('isFcmSendConfigured = false افتراضياً', () {
      expect(Env.isFcmSendConfigured, isFalse);
    });

    test('isPosthogConfigured = false افتراضياً', () {
      expect(Env.isPosthogConfigured, isFalse);
    });
  });

  group('Env - baseApiUrl قابل للتعديل (متغير non-const)', () {
    test('baseApiUrl يمكن تعديله في runtime', () {
      const testUrl = 'https://test.example.com/api/v1';
      Env.baseApiUrl = testUrl;
      expect(Env.baseApiUrl, testUrl);
      expect(Env.isApiConfigured, isTrue);

      // تنظيف
      Env.baseApiUrl = '';
      expect(Env.isApiConfigured, isFalse);
    });
  });
}
