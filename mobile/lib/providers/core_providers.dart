import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../services/ditto_sync_service.dart';

final dbProvider = Provider<AppDatabase>((ref) => AppDatabase());
final syncProvider = Provider<SyncService>((ref) => SyncService(ref.read(dbProvider)));
