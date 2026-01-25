import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppwriteService.initialize completes and sets initialized=true', () async {
    final service = AppwriteService();
    await service.initialize();
    final info = service.getProjectInfo();
    expect(info['initialized'], 'true');
  });
}
