import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/google_drive_logger.dart';

void main() {
  test('GoogleDriveLogger queues and formats entries', () {
    final logger = GoogleDriveLogger();
    logger.logInfo('sync', 'ok');
    logger.logError('sync', 'failed', StackTrace.fromString('stack')); 
    final entries = logger.dumpAndClear();
    expect(entries.length, 2);
    expect(entries.first['level'], 'info');
    expect(entries.last['level'], 'error');
    expect(logger.dumpAndClear(), isEmpty);
  });
}
