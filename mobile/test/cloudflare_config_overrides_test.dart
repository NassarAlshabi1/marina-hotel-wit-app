// ═══════════════════════════════════════════════════════════════
//  cloudflare_config_overrides_test.dart — اختبارات عقدية hermetic
//  لاعتمادات تسجيل الدخول القابلة للتغطية وقت التشغيل (2026-09-10):
//  شاشة تسجيل الدخول إلى Cloudflare تحفظ username/password بديلة
//  في SharedPreferences فتعمل على حساب المدمجة --dart-define.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CloudflareConfig.resetCredentialOverridesForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('CloudflareConfig credential overrides', () {
    test('بلا override — يعيد المدمج من Env', () async {
      await CloudflareConfig.loadCredentialOverrides();
      expect(CloudflareConfig.hasCredentialOverrides, isFalse);
      expect(CloudflareConfig.username, isNotEmpty);
      expect(CloudflareConfig.password, isNotEmpty);
    });

    test('setCredentialOverrides يغطي المدمج فوراً ويُثبّته', () async {
      await CloudflareConfig.setCredentialOverrides(
        username: 'hotel_admin',
        password: 's3cret!',
      );

      expect(CloudflareConfig.username, 'hotel_admin');
      expect(CloudflareConfig.password, 's3cret!');
      expect(CloudflareConfig.hasCredentialOverrides, isTrue);

      // الاستعادة من التخزين (محاكاة إطلاق جديد) تجلب القيم نفسها
      CloudflareConfig.resetCredentialOverridesForTests();
      await CloudflareConfig.loadCredentialOverrides();
      expect(CloudflareConfig.username, 'hotel_admin');
      expect(CloudflareConfig.password, 's3cret!');
    });

    test(
      'كلمة مرور فارغة/null تُبقي الكلمة السابقة — عقد شاشة الدخول',
      () async {
        await CloudflareConfig.setCredentialOverrides(
          username: 'user_a',
          password: 'pass_a',
        );

        // المستخدم عدّل الاسم فقط وترك حقل كلمة المرور فارغاً
        await CloudflareConfig.setCredentialOverrides(
          username: 'user_b',
        );

        expect(CloudflareConfig.username, 'user_b');
        expect(CloudflareConfig.password, 'pass_a');
      },
    );

    test('اسم مستخدم فارغ يزيل override الاسم فقط', () async {
      await CloudflareConfig.setCredentialOverrides(
        username: 'user_a',
        password: 'pass_a',
      );

      await CloudflareConfig.setCredentialOverrides(
        username: '   ',
      );

      expect(
        CloudflareConfig.hasCredentialOverrides,
        isTrue,
        reason: 'كلمة المرور override ما تزال موجودة',
      );
      expect(CloudflareConfig.username, isNot('user_a'));
      expect(CloudflareConfig.password, 'pass_a');
    });

    test('clearCredentialOverrides يرجع للمدمج ويمسح التخزين', () async {
      await CloudflareConfig.setCredentialOverrides(
        username: 'tmp_user',
        password: 'tmp_pass',
      );
      expect(CloudflareConfig.hasCredentialOverrides, isTrue);

      await CloudflareConfig.clearCredentialOverrides();
      expect(CloudflareConfig.hasCredentialOverrides, isFalse);

      // حتى بعد الاستعادة من التخزين — لا شيء يعود
      await CloudflareConfig.loadCredentialOverrides();
      expect(CloudflareConfig.hasCredentialOverrides, isFalse);
    });

    test('loadCredentialOverrides يتجاهل القيم الفارغة المخزنة', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CloudflareConfig.usernameOverrideKey: '  ',
        CloudflareConfig.passwordOverrideKey: '',
      });

      await CloudflareConfig.loadCredentialOverrides();
      expect(CloudflareConfig.hasCredentialOverrides, isFalse);
    });
  });
}
