import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../services/ditto_sync_service.dart';

final dbProvider = Provider<AppDatabase>((ref) => DatabaseManager.instance);
final syncProvider = Provider<DittoSyncService>((ref) => DittoSyncService(ref.read(dbProvider)));
