import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final isCI =
      Platform.environment.containsKey('CI') ||
      Platform.environment.containsKey('GITHUB_ACTIONS');

  test(
    'AppwriteService.initialize completes and sets initialized=true',
    () async {
      final service = AppwriteService();
      await service.initialize();
      final info = service.getProjectInfo();
      expect(info['initialized'], 'true');
    },
    skip: isCI ? 'اختبار تكاملي - يحتاج اتصال حقيقي بـ Appwrite' : null,
  );
}
