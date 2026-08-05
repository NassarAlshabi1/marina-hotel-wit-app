// ============================================================================
//  Constants & SystemSettingKeys — Unit Tests
//  ============================================================================
//  اختبارات بسيطة للثوابت والمفاتيح:
//    - Constants تحتوي على قيم صحيحة
//    - SystemSettingKeys تحتوي على جميع المفاتيح المتوقعة
// ============================================================================

library marina_hotel_mobile.test.constants_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/constants.dart';
import 'package:marina_hotel_mobile/utils/system_settings_keys.dart';

void main() {
  group('Constants', () {
    test('appName ليس فارغاً', () {
      expect(Constants.appName, isNotEmpty);
      expect(Constants.appName, 'مارينا بلازا');
    });

    test('baseApiUrl افتراضياً HTTPS', () {
      // في CI بدون --dart-define، يستخدم defaultValue
      expect(Constants.baseApiUrl, startsWith('https://'));
    });

    test('appVersion ليس فارغاً', () {
      expect(Constants.appVersion, isNotEmpty);
      expect(Constants.appVersion, contains(RegExp(r'\d+\.\d+')));
    });

    test('apiTimeoutSeconds قيمة منطقية', () {
      expect(Constants.apiTimeoutSeconds, greaterThan(0));
      expect(Constants.apiTimeoutSeconds, lessThan(120));
    });
  });

  group('SystemSettingKeys', () {
    test('يحتوي على جميع المفاتيح المتوقعة', () {
      expect(SystemSettingKeys.autoBackupEnabled, 'auto_backup_enabled');
      expect(SystemSettingKeys.autoBackupTime, 'auto_backup_time');
      expect(SystemSettingKeys.autoBackupFrequency, 'auto_backup_frequency');
      expect(SystemSettingKeys.scheduledBackupEnabled, 'scheduled_backup_enabled');
      expect(SystemSettingKeys.autoLocalBackupEnabled, 'auto_local_backup_enabled');
      expect(SystemSettingKeys.smartSyncInterval, 'smart_sync_interval');
      expect(SystemSettingKeys.wifiOnlySync, 'wifi_only_sync');
    });

    test('all تحتوي على جميع المفاتيح', () {
      final all = SystemSettingKeys.all;
      expect(all.length, 7);
      expect(all, contains(SystemSettingKeys.autoBackupEnabled));
      expect(all, contains(SystemSettingKeys.autoBackupTime));
      expect(all, contains(SystemSettingKeys.autoBackupFrequency));
      expect(all, contains(SystemSettingKeys.scheduledBackupEnabled));
      expect(all, contains(SystemSettingKeys.autoLocalBackupEnabled));
      expect(all, contains(SystemSettingKeys.smartSyncInterval));
      expect(all, contains(SystemSettingKeys.wifiOnlySync));
    });

    test('all لا تحتوي على تكرارات', () {
      final all = SystemSettingKeys.all;
      final unique = all.toSet();
      expect(unique.length, all.length);
    });

    test('جميع المفاتيح غير فارغة', () {
      for (final key in SystemSettingKeys.all) {
        expect(key, isNotEmpty);
      }
    });

    test('جميع المفاتيح بصيغة snake_case', () {
      for (final key in SystemSettingKeys.all) {
        // لا تحتوي على uppercase أو مسافات
        expect(key.toLowerCase(), equals(key));
        expect(key.contains(' '), isFalse);
      }
    });
  });
}
