import 'local_db.dart';
import 'google_drive_logger.dart';

enum ConflictResolutionStrategy { newerWins, olderWins, localWins, remoteWins, devicePriorityBased, manualReview }

class GoogleDriveConflictResolver {
  static final instance = GoogleDriveConflictResolver();

  void initialize(GoogleDriveLogger logger) {}

  Future<void> setStrategy(ConflictResolutionStrategy strategy) async {}

  Future<void> setConflictThreshold(int threshold) async {}
}
