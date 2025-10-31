import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/firestore_shift_notes_service.dart';
import '../services/providers.dart';

class FirestoreSyncState {
  final bool isEnabled;
  final bool isConnected;
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final int syncedNotesCount;
  final String? errorMessage;
  final List<SyncEvent> recentEvents;

  const FirestoreSyncState({
    this.isEnabled = false,
    this.isConnected = false,
    this.isSyncing = false,
    this.lastSyncTime,
    this.syncedNotesCount = 0,
    this.errorMessage,
    this.recentEvents = const [],
  });

  FirestoreSyncState copyWith({
    bool? isEnabled,
    bool? isConnected,
    bool? isSyncing,
    DateTime? lastSyncTime,
    int? syncedNotesCount,
    String? errorMessage,
    List<SyncEvent>? recentEvents,
  }) {
    return FirestoreSyncState(
      isEnabled: isEnabled ?? this.isEnabled,
      isConnected: isConnected ?? this.isConnected,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      syncedNotesCount: syncedNotesCount ?? this.syncedNotesCount,
      errorMessage: errorMessage,
      recentEvents: recentEvents ?? this.recentEvents,
    );
  }
}

class SyncEvent {
  final String type;
  final String message;
  final DateTime timestamp;
  final bool isError;

  SyncEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.isError = false,
  });
}

class FirestoreSyncNotifier extends StateNotifier<FirestoreSyncState> {
  FirestoreSyncNotifier() : super(const FirestoreSyncState()) {
    _initialize();
  }

  static const String _prefsEnabledKey = 'firestore_sync_enabled';
  Timer? _connectionCheckTimer;

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(_prefsEnabledKey) ?? true;

    state = state.copyWith(isEnabled: isEnabled);

    if (isEnabled) {
      await _checkConnection();
      _startConnectionMonitoring();
    }
  }

  Future<void> _checkConnection() async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      state = state.copyWith(isSyncing: true);

      await firestore
          .collection('_connection_test')
          .doc('test')
          .set({'timestamp': FieldValue.serverTimestamp()});

      final snapshot = await firestore
          .collection('shift_notes')
          .limit(1)
          .get(const GetOptions(source: Source.server));

      state = state.copyWith(
        isConnected: true,
        isSyncing: false,
        lastSyncTime: DateTime.now(),
        errorMessage: null,
      );

      _addEvent(SyncEvent(
        type: 'connection',
        message: 'تم الاتصال بـ Firestore بنجاح',
        timestamp: DateTime.now(),
      ));

      debugPrint('✅ متصل بـ Firestore');
    } catch (e) {
      state = state.copyWith(
        isConnected: false,
        isSyncing: false,
        errorMessage: 'فشل الاتصال: ${e.toString()}',
      );

      _addEvent(SyncEvent(
        type: 'error',
        message: 'فشل الاتصال بـ Firestore: $e',
        timestamp: DateTime.now(),
        isError: true,
      ));

      debugPrint('❌ فشل الاتصال بـ Firestore: $e');
    }
  }

  void _startConnectionMonitoring() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _checkConnection(),
    );
  }

  void _stopConnectionMonitoring() {
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = null;
  }

  void _addEvent(SyncEvent event) {
    final events = List<SyncEvent>.from(state.recentEvents);
    events.insert(0, event);
    if (events.length > 20) {
      events.removeLast();
    }
    state = state.copyWith(recentEvents: events);
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, enabled);

    state = state.copyWith(isEnabled: enabled);

    if (enabled) {
      await _checkConnection();
      _startConnectionMonitoring();

      _addEvent(SyncEvent(
        type: 'config',
        message: 'تم تفعيل المزامنة اللحظية',
        timestamp: DateTime.now(),
      ));
    } else {
      _stopConnectionMonitoring();

      _addEvent(SyncEvent(
        type: 'config',
        message: 'تم إيقاف المزامنة اللحظية',
        timestamp: DateTime.now(),
      ));
    }

    debugPrint('🔧 المزامنة اللحظية: ${enabled ? "مُفعلة" : "معطلة"}');
  }

  Future<void> forceSync() async {
    _addEvent(SyncEvent(
      type: 'sync',
      message: 'بدء المزامنة اليدوية...',
      timestamp: DateTime.now(),
    ));

    await _checkConnection();
  }

  void updateSyncedCount(int count) {
    state = state.copyWith(syncedNotesCount: count);
  }

  @override
  void dispose() {
    _stopConnectionMonitoring();
    super.dispose();
  }
}

final firestoreSyncProvider =
    StateNotifierProvider<FirestoreSyncNotifier, FirestoreSyncState>((ref) {
  return FirestoreSyncNotifier();
});

final firestoreConnectionStatusProvider = Provider<bool>((ref) {
  final syncState = ref.watch(firestoreSyncProvider);
  return syncState.isConnected;
});
