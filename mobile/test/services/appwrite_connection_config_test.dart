// اختبارات شاشة «إعدادات الاتصال بـ Appwrite» على مستوى الخدمات التي
// تستند إليها: تطبيع القيم، مفتاح API الفارغ، إعادة بناء العميل، وتشخيص
// طبقة الفشل في اختبار الاتصال.
//
// كل حالة هنا تقابل عطلاً مؤكداً في الشيفرة قبل الإصلاح:
//  1) شرطة مائلة نهائية في الـ Endpoint ⇒ مسار مزدوج ⇒ 404 وهمي.
//  2) مفتاح API فارغ كان يُحفظ '' ويطمس المفتاح المدمج ⇒ 401 على كل طلب.
//  3) العميل كان `late final` فلا يمكن إعادة بنائه ⇒ «إعادة تشغيل مطلوبة».
//  4) فشل الاختبار كان سطراً واحداً لا يميّز طبقة العطل.

import 'package:appwrite/appwrite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_config.dart';
import 'package:marina_hotel_mobile/services/appwrite_config_manager.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await AppwriteConfigManager.resetToDefaults();
  });

  group('تطبيع قيم الاتصال', () {
    test('الـ Endpoint يُحفظ بلا شرطة مائلة نهائية ولا فراغات', () async {
      await AppwriteConfigManager.saveConfig(
        endpoint: '  https://fra.cloud.appwrite.io/v1//  ',
        projectId: ' 6ae118bc00263ddb1cd5 ',
        databaseId: ' 6ae119d7001046bbdb3e ',
        apiKey: ' standard_key ',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        AppwriteConfigManager.endpoint,
        'https://fra.cloud.appwrite.io/v1',
      );
      expect(
        prefs.getString('appwrite_endpoint'),
        'https://fra.cloud.appwrite.io/v1',
      );
      expect(AppwriteConfigManager.projectId, '6ae118bc00263ddb1cd5');
      expect(AppwriteConfigManager.databaseId, '6ae119d7001046bbdb3e');
      expect(AppwriteConfigManager.apiKey, 'standard_key');
    });

    test('normalizeEndpoint يتعامل مع الحالات الحدّية', () {
      expect(
        AppwriteConfigManager.normalizeEndpoint('https://x/v1/'),
        'https://x/v1',
      );
      expect(
        AppwriteConfigManager.normalizeEndpoint('https://x/v1///'),
        'https://x/v1',
      );
      expect(
        AppwriteConfigManager.normalizeEndpoint(' https://x/v1 '),
        'https://x/v1',
      );
      expect(AppwriteConfigManager.normalizeEndpoint(''), '');
    });
  });

  group('مفتاح API الفارغ', () {
    test('لا يُخزَّن إطلاقاً حتى لا يطمس المفتاح المدمج', () async {
      await AppwriteConfigManager.saveConfig(
        endpoint: AppwriteConfig.endpoint,
        projectId: AppwriteConfig.projectId,
        databaseId: AppwriteConfig.databaseId,
        apiKey: '   ',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey('appwrite_api_key'),
        isFalse,
        reason:
            'حفظ \'\' كان يجعل init() يتجاوز المفتاح المدمج (?? لا يلتقط '
            'السلسلة الفارغة) فتُرفض كل الطلبات بـ 401',
      );
      // القيمة الفعّالة وقت التشغيل ترجع إلى المفتاح المدمج مباشرة.
      expect(AppwriteConfigManager.apiKey, AppwriteConfig.defaultApiKey);
      expect(AppwriteConfigManager.isUsingCustomConfig, isFalse);
    });

    test('init() يشفى من مفتاح فارغ مخزَّن في نسخة سابقة', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('appwrite_api_key', '');
      await prefs.setString(
        'appwrite_endpoint',
        'https://fra.cloud.appwrite.io/v1/',
      );

      await AppwriteConfigManager.init();

      expect(AppwriteConfigManager.apiKey, AppwriteConfig.defaultApiKey);
      expect(
        AppwriteConfigManager.endpoint,
        'https://fra.cloud.appwrite.io/v1',
        reason: 'قيمة مخزَّنة بشرطة مائلة نهائية يجب أن تُطبَّع عند التحميل',
      );
    });

    test('مفتاح غير فارغ يُخزَّن ويُستخدم', () async {
      await AppwriteConfigManager.saveConfig(
        endpoint: AppwriteConfig.endpoint,
        projectId: AppwriteConfig.projectId,
        databaseId: AppwriteConfig.databaseId,
        apiKey: 'standard_custom_key',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appwrite_api_key'), 'standard_custom_key');
      expect(AppwriteConfigManager.apiKey, 'standard_custom_key');
      expect(AppwriteConfigManager.isUsingCustomConfig, isTrue);
    });

    test('resetToDefaults يحذف المفتاح المخزَّن ويعيد المدمج', () async {
      await AppwriteConfigManager.saveConfig(
        endpoint: 'https://other.appwrite.io/v1',
        projectId: 'p1',
        databaseId: 'd1',
        apiKey: 'standard_custom_key',
      );
      await AppwriteConfigManager.resetToDefaults();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('appwrite_api_key'), isFalse);
      expect(prefs.containsKey('appwrite_endpoint'), isFalse);
      expect(AppwriteConfigManager.endpoint, AppwriteConfig.endpoint);
      expect(AppwriteConfigManager.apiKey, AppwriteConfig.defaultApiKey);
    });
  });

  group('بصمة هدف المزامنة', () {
    test('targetIdentity = endpoint|project|database بصيغة مطبَّعة', () async {
      await AppwriteConfigManager.saveConfig(
        endpoint: 'https://x.appwrite.io/v1/',
        projectId: 'proj',
        databaseId: 'db',
        apiKey: '',
      );

      expect(
        AppwriteConfigManager.targetIdentity,
        'https://x.appwrite.io/v1|proj|db',
      );
    });
  });

  group('إعادة بناء العميل بعد تغيير الإعدادات', () {
    test('reinitialize يبني عميلاً جديداً بدل الإبقاء على القديم', () async {
      final service = AppwriteService();

      await AppwriteConfigManager.saveConfig(
        endpoint: 'https://first.appwrite.io/v1',
        projectId: 'proj_a',
        databaseId: 'db_a',
        apiKey: 'standard_a',
      );
      await service.initialize();
      final firstClient = service.client;

      await AppwriteConfigManager.saveConfig(
        endpoint: 'https://second.appwrite.io/v1',
        projectId: 'proj_b',
        databaseId: 'db_b',
        apiKey: 'standard_b',
      );
      await service.reinitialize();

      expect(
        identical(service.client, firstClient),
        isFalse,
        reason:
            'late final كان يمنع إعادة الإسناد تماماً، فتبقى الطلبات على '
            'المشروع القديم حتى إعادة تشغيل التطبيق',
      );
      expect(service.isInitialized, isTrue);
    });

    test('initialize المتكرر آمن (idempotent)', () async {
      final service = AppwriteService();
      await service.initialize();
      await service.initialize();
      expect(service.isInitialized, isTrue);
    });
  });

  group('تشخيص طبقة الفشل في اختبار الاتصال', () {
    String hintFor(Object error) =>
        AppwriteService.describeConnectionFailure(error);

    test('401/403 ⇒ مشكلة مفتاح API', () {
      expect(
        hintFor(AppwriteException('Unauthorized', 401)),
        contains('المفتاح'),
      );
      expect(hintFor(AppwriteException('Forbidden', 403)), contains('المفتاح'));
    });

    test('Database/Collection غير موجودة ⇒ مشكلة قاعدة البيانات', () {
      expect(
        hintFor(AppwriteException('Database not found', 404)),
        contains('Database ID'),
      );
      expect(
        hintFor(
          AppwriteException(
            'The requested route was not found: collection_not_found',
            404,
          ),
        ),
        contains('Database ID'),
      );
    });

    test('Project غير موجود ⇒ مشكلة المشروع', () {
      expect(
        hintFor(AppwriteException('project_not_found', 404)),
        contains('Project ID'),
      );
    });

    test('فشل شبكي ⇒ مشكلة Endpoint/الشبكة', () {
      expect(
        hintFor(Exception('SocketException: Failed host lookup: x')),
        contains('الـ Endpoint'),
      );
      expect(
        hintFor(AppwriteException('Connection timed out', 0)),
        contains('الـ Endpoint'),
      );
    });

    test('خطأ غير معروف لا يُصنَّف زوراً', () {
      expect(hintFor(Exception('weird')), contains('غير مصنّف'));
    });
  });
}
