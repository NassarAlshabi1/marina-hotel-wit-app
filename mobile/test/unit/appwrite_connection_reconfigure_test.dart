// test/unit/appwrite_connection_reconfigure_test.dart
//
// ✅ اختبارات إصلاح شاشة إعدادات Appwrite Cloud (2026-11-03).
// تثبت أن تغيير إعدادات الاتصال (Endpoint/Project/Database/API Key)
// وحفظها من شاشة الإعدادات يُطبَّق فوراً على عميل Appwrite دون
// إعادة تشغيل التطبيق:
//  - reconfigure(): يعيد بناء العميل بالقيم الفعّالة الجديدة.
//  - reconfigureIfNeeded(): لا يعيد البناء عند عدم التغيير (idempotent)
//    ويعيده عند التغيير — وهذا ما يستدعيه ConnectionStatusNotifier
//    قبل كل فحص اتصال.
//
// قبل الإصلاح: العميل كان late final يُبنى مرة واحدة فقط، فكان زر
// «اختبار الاتصال» يفحص الإعدادات القديمة بعد الحفظ، والشاشة تعرض
// «غير متصل» رغم صحة القيم الجديدة (والمزامنة تستمر على القديمة
// حتى إعادة تشغيل التطبيق).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_config_manager.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ✅ مجلد مستقر طوال عمر ملف الاختبار — يُسجّل mock لـ path_provider
  // خاص بنا. السبب: ClientIO.init() في Appwrite SDK يعمل fire-and-forget
  // وينشئ <documents>/cookies؛ إذا كان مجلد المستندات الوهمي العام
  // (flutter_test_config) محذوفاً لحظة التشغيل، يتسرب
  // PathNotFoundException غير معالج إلى الاختبار الجاري ويفشله
  // دون أي علاقة بمنطق الاختبار.
  late final Directory stableDocsDir;

  setUpAll(() async {
    stableDocsDir = await Directory.systemTemp.createTemp(
      'appwrite_reconfig_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            switch (methodCall.method) {
              case 'getApplicationDocumentsDirectory':
              case 'getTemporaryDirectory':
              case 'getApplicationSupportDirectory':
              case 'getLibraryDirectory':
              case 'getDownloadsDirectory':
                return stableDocsDir.path;
              default:
                return null;
            }
          },
        );
  });

  tearDownAll(() async {
    // مهلة قصيرة قبل الحذف حتى تكتمل التهيئة غير المتزامنة fire-and-forget
    // لآخر عميل بُني، فلا يتسرب خطأ بعد انتهاء الاختبارات.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      if (stableDocsDir.existsSync()) {
        await stableDocsDir.delete(recursive: true);
      }
    } catch (_) {
      // silent — best-effort cleanup
    }
  });

  tearDown(() async {
    // إعادة الإعدادات الافتراضية — الحالة static مشتركة عبر الاختبارات
    // في نفس الـ isolate (نفس singleton AppwriteService وConfigManager).
    await AppwriteConfigManager.resetToDefaults();
    await AppwriteService().reconfigure();
  });

  test('reconfigure يعيد بناء العميل بالإعدادات الجديدة فوراً', () async {
    // 1. التهيئة بالإعدادات الافتراضية (كما عند بدء التطبيق)
    SharedPreferences.setMockInitialValues({});
    await AppwriteConfigManager.init();
    final service = AppwriteService();
    await service.initialize();
    final clientBefore = service.client;
    final endpointBefore = clientBefore.endPoint;

    // 2. المستخدم يغيّر الإعدادات من شاشة إعدادات الاتصال ويحفظها
    const newEndpoint = 'https://nyc.cloud.appwrite.io/v1';
    const newProjectId = 'project_after_change_123';
    await AppwriteConfigManager.saveConfig(
      endpoint: newEndpoint,
      projectId: newProjectId,
      databaseId: 'db_after_change_123',
      apiKey: 'standard_key_after_change',
    );

    // 3. توثيق السلوك القديم المعطوب: initialize() يبقى no-op بعد
    //    التهيئة الأولى — لا يُطبّق القيم الجديدة.
    await service.initialize();
    expect(
      service.client.endPoint,
      endpointBefore,
      reason:
          'initialize() على العميل المهيأ يجب أن يبقى no-op — '
          'لهذا وُجد reconfigure()',
    );

    // 4. الإصلاح: reconfigure يعيد البناء بالقيم الجديدة فوراً.
    await service.reconfigure();
    expect(
      identical(clientBefore, service.client),
      isFalse,
      reason: 'يجب أن يُبنى عميل جديد بعد reconfigure',
    );
    expect(service.client.endPoint, newEndpoint);
    expect(service.client.config['project'], newProjectId);
  });

  test('reconfigureIfNeeded لا يعيد البناء دون تغيير الإعدادات', () async {
    SharedPreferences.setMockInitialValues({});
    await AppwriteConfigManager.init();
    final service = AppwriteService();
    await service.initialize();
    final clientBefore = service.client;

    await service.reconfigureIfNeeded();
    expect(
      identical(clientBefore, service.client),
      isTrue,
      reason: 'الإعدادات لم تتغير — لا داعي لإعادة بناء العميل',
    );
  });

  test(
    'reconfigureIfNeeded يلتقط التغيير تلقائياً (مسار checkConnection)',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppwriteConfigManager.init();
      final service = AppwriteService();
      await service.initialize();
      final clientBefore = service.client;

      // المستخدم حفظ إعدادات جديدة من شاشة إعدادات الاتصال ثم ضغط
      // «اختبار الاتصال» في الشاشة الرئيسية:
      await AppwriteConfigManager.saveConfig(
        endpoint: 'https://tor.cloud.appwrite.io/v1',
        projectId: 'project_picked_up_automatically',
        databaseId: 'db_auto_1',
        apiKey: 'standard_auto_key',
      );

      // ConnectionStatusNotifier.checkConnection يستدعي reconfigureIfNeeded
      // قبل الفحص — يجب أن يلتقط التغيير ويبني عميلاً جديداً (بالقيم
      // الجديدة) لا أن يفحص بالإعدادات القديمة.
      await service.reconfigureIfNeeded();
      expect(identical(clientBefore, service.client), isFalse);
      expect(
        service.client.config['project'],
        'project_picked_up_automatically',
      );
      expect(service.client.endPoint, 'https://tor.cloud.appwrite.io/v1');
    },
  );

  test('resetToDefaults يعود للعميل الافتراضي بعد إعادة التعيين', () async {
    // البدء بإعدادات مخصصة محفوظة (كجهاز سبق أن غيّر إعداداته)
    SharedPreferences.setMockInitialValues({
      'appwrite_endpoint': 'https://nyc.cloud.appwrite.io/v1',
      'appwrite_project_id': 'custom_project_9',
      'appwrite_database_id': 'custom_db_9',
      'appwrite_api_key': 'standard_custom_9',
    });
    await AppwriteConfigManager.init();
    final service = AppwriteService();
    // مثل بدء التطبيق على جهاز فيه إعدادات محفوظة مخصصة
    await service.reconfigure();
    expect(service.client.endPoint, 'https://nyc.cloud.appwrite.io/v1');
    expect(service.client.config['project'], 'custom_project_9');

    // المستخدم يضغط «إعادة تعيين» في شاشة إعدادات الاتصال
    await AppwriteConfigManager.resetToDefaults();
    await service.reconfigure();

    expect(service.client.endPoint, AppwriteConfigManager.endpoint);
    expect(service.client.config['project'], AppwriteConfigManager.projectId);
  });
}
