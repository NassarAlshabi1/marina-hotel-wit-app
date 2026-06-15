import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../appwrite_logger.dart';
import '../appwrite_service.dart';
import '../appwrite_sync_utils.dart';
import '../booking_derived_fields_service.dart';
import '../conflict_manager.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../repositories/bookings_repository.dart';
import '../repositories/rooms_repository.dart';
import '../sync_constants.dart';
import '../sync_enums.dart';
import '../sync_mutex.dart';
import 'sync_error_service.dart';

class SyncPullService {
  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  late final AdapterRegistry _adapterRegistry;
  late final BookingsRepository _bookingsRepository;
  late final RoomsRepository _roomsRepository;
  final SyncMutex _mutex;
  final SyncErrorService _err;
  SyncStatus _currentStatus = SyncStatus.idle;
  final _syncController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncController.stream;

  SyncPullService({
    required this.appwriteService,
    required this.database,
    required this.outboxDao,
    AdapterRegistry? adapterRegistry,
    BookingsRepository? bookingsRepository,
    RoomsRepository? roomsRepository,
    SyncMutex? mutex,
    SyncErrorService? errorService,
  })  : _adapterRegistry = adapterRegistry ?? AdapterRegistry(database),
        _bookingsRepository = bookingsRepository ?? BookingsRepository(database),
        _roomsRepository = roomsRepository ?? RoomsRepository(database),
        _mutex = mutex ?? SyncMutex(),
        _err = errorService ?? SyncErrorService(tag: 'PULL');

  /// دلتا سحب
  Future<Map<String, int>> pullAllEntities({
    required bool remoteEpochIsMillis,
    required int lastPullTs,
  }) async {
    final recordsPulled = <String, int>{};
    final deltaQ = _buildDeltaQueries(lastPullTs, remoteEpochIsMillis: remoteEpochIsMillis);
    _err.info(deltaQ.isEmpty ? 'Pull all (full)' : 'Delta sync since ');

    for (final entity in ['rooms', 'bookings', 'employees', 'booking_nights',
        'payments', 'expenses', 'debts', 'cash_transactions', 'booking_notes',
        'shift_notes', 'guest_infos', 'blacklist', 'salary_withdrawals',
        'salary_cycles', 'salary_payments', 'booking_price_adjustments',
        'price_adjustments', 'audit_logs', 'payment_voids', 'app_settings']) {
      try {
        final synced = await _syncEntity(entity, deltaQ);
        recordsPulled[entity] = synced;
      } catch (e, st) {
        _err.error('Failed to sync $entity', error: e, stackTrace: st);
      }
    }
    return recordsPulled;
  }

  Future<int> _syncEntity(String entity, List<String> queries) async {
    return 0; // simplified
  }

  Future<bool> _isRemoteEpochMillis() async {
    try {
      final rooms = await appwriteService.listRooms(queries: [Query.limit(1)]);
      if (rooms.isEmpty) return false;
      final ts = rooms.first.data['lastModified'];
      return ts is int && ts > 10000000000;
    } catch (_) { return false; }
  }

  List<String> _buildDeltaQueries(int lastPullTs, {required bool remoteEpochIsMillis}) {
    if (lastPullTs > 0) {
      final cutoff = lastPullTs - 5;
      return remoteEpochIsMillis
          ? [Query.greaterThan('lastModified', cutoff * 1000)]
          : [Query.greaterThan('lastModified', cutoff)];
    }
    return [];
  }

  List<String> _bookingNightsDeltaQueries(int lastPullTs, {required bool remoteEpochIsMillis}) {
    if (lastPullTs > 0) {
      final cutoff = lastPullTs - 5;
      return remoteEpochIsMillis
          ? [Query.greaterThan('lastModified', cutoff * 1000)]
          : [Query.greaterThan('lastModified', cutoff)];
    }
    return [];
  }

  Future<int> _getLastPullTs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('sync_last_pull_ts') ?? 0;
  }

  Future<void> _updateLastPullTs(int ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_last_pull_ts', ts);
  }

  Future<int> _getBookingNightsPullTs() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('sync_last_pull_booking_nights') ?? 0;
    return ts > 10000000000 ? ts ~/ 1000 : ts;
  }

  Future<void> _updateBookingNightsPullTs(int ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_last_pull_booking_nights', ts);
  }

  Future<int> _syncRooms(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.rooms.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) { _err.warning('Room sync: $e'); }
    }
    return processed;
  }

  Future<int> _syncBookings(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.bookings)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1)).getSingleOrNull();
        if (existing != null && !_isRemoteDataNewer(data, existing.lastModified, localDeletedAt: existing.deletedAt)) {
          continue;
        }
        await _adapterRegistry.bookings.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) { _err.warning('Booking sync: $e'); }
    }
    return processed;
  }

  Future<int> _syncEmployees(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.employees.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) { _err.warning('Employee sync: $e'); }
    }
    return processed;
  }

  Future<int> _syncBookingNights(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final deferred = <models.Document>[];
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.bookingNights)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1)).getSingleOrNull();
        if (existing != null && !_isRemoteDataNewer(data, existing.lastModified, localDeletedAt: existing.deletedAt)) {
          continue;
        }
        await _adapterRegistry.nights.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) {
        final s = e.toString();
        if (s.contains('FOREIGN KEY') || s.contains('NOT NULL')) {
          deferred.add(doc);
        } else { _err.warning('Night sync: $e'); }
      }
    }
    for (final doc in deferred) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.nights.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) { _err.warning('Deferred night sync: $e'); }
    }
    return processed;
  }

  bool _isRemoteDataNewer(Map<String, dynamic> remoteData, int? localLastModified, {int? localDeletedAt}) {
    if (localLastModified == null) return true;
    final remote = (remoteData['lastModified'] as int?) ?? 0;
    return remote > localLastModified;
  }

  void dispose() {
    _syncController.close();
  }
}
