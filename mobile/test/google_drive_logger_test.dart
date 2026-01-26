import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/google_drive_logger.dart';
import 'package:marina_hotel_mobile/services/logging/log_models.dart';

void main() {
  test('GoogleDriveLogger stores entries by level', () {
    final logger = GoogleDriveLogger();
    logger.info('ok', tag: 'sync');
    logger.error('failed',
        tag: 'sync', stackTrace: StackTrace.fromString('stack'));
    final entries = logger.getLogs();
    expect(entries.length, 2);
    expect(entries.first.level, LogLevel.info);
    expect(entries.last.level, LogLevel.error);
    logger.dispose();
  });
}
