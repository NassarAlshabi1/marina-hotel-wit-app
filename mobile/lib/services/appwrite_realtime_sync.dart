import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_service.dart';
import 'appwrite_config.dart';
import 'appwrite_delta_sync.dart';

class AppwriteRealtimeSync {
  static final AppwriteRealtimeSync _instance =
      AppwriteRealtimeSync._internal();
  factory AppwriteRealtimeSync() => _instance;
  AppwriteRealtimeSync._internal();

  Realtime? _realtime;
  RealtimeSubscription? _subscription;
  String? _currentDeviceId;
  bool _isListening = false;
  Timer? _debounceTimer;

  static const _collections = [
    AppwriteConfig.roomsCollectionId,
    AppwriteConfig.bookingsCollectionId,
    AppwriteConfig.bookingNotesCollectionId,
    AppwriteConfig.bookingNightsCollectionId,
    AppwriteConfig.paymentsCollectionId,
    AppwriteConfig.expensesCollectionId,
    AppwriteConfig.cashTransactionsCollectionId,
    AppwriteConfig.debtsCollectionId,
    AppwriteConfig.employeesCollectionId,
    AppwriteConfig.salaryCyclesCollectionId,
    AppwriteConfig.salaryPaymentsCollectionId,
    AppwriteConfig.shiftNotesCollectionId,
  ];

  Future<void> initialize({
    required String deviceId,
  }) async {
    _currentDeviceId = deviceId;
    _realtime = Realtime(AppwriteService().client);
    debugPrint('📡 AppwriteRealtimeSync initialized');
  }

  Future<void> start() async {
    if (_isListening || _realtime == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('appwrite_sync_enabled') ?? false)) return;

    final channels = _collections
        .map(
          (c) =>
              'databases.${AppwriteConfig.databaseId}.collections.$c.documents',
        )
        .toList();

    _subscription = _realtime!.subscribe(channels);
    _isListening = true;

    debugPrint('📡 Realtime: listening...');

    _subscription!.stream.listen(
      _onEvent,
      onError: (e) {
        debugPrint('❌ Realtime error: $e');
        _isListening = false;
        _reconnect();
      },
      onDone: () {
        _isListening = false;
      },
    );
  }

  void _onEvent(RealtimeMessage message) {
    final payload = message.payload;
    final sourceDevice = payload['device_id'] ?? payload['lastModifiedBy'];

    if (sourceDevice == _currentDeviceId) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await AppwriteDeltaSync.instance.pullDeltaChanges();
        debugPrint('✅ Realtime delta sync done');
      } catch (e) {
        debugPrint('❌ Realtime sync error: $e');
      }
    });
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isListening) start();
    });
  }

  Future<void> stop() async {
    _subscription?.close();
    _subscription = null;
    _isListening = false;
    _debounceTimer?.cancel();
  }

  void dispose() => stop();

  bool get isListening => _isListening;
}
