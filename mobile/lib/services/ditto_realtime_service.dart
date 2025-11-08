import 'dart:async';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/ditto_config.dart';
import 'providers.dart';

enum RealtimeStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class RealtimeEvent {
  final String collection;
  final String eventType;
  final Map<String, dynamic> document;
  final DateTime timestamp;

  RealtimeEvent({
    required this.collection,
    required this.eventType,
    required this.document,
    required this.timestamp,
  });
}

class RealtimeStats {
  int insertEvents = 0;
  int updateEvents = 0;
  int deleteEvents = 0;
  DateTime? lastEventTime;
  final Map<String, int> eventsByCollection = {};

  void recordEvent(String collection, String eventType) {
    switch (eventType) {
      case 'insert':
        insertEvents++;
        break;
      case 'update':
        updateEvents++;
        break;
      case 'delete':
        deleteEvents++;
        break;
    }

    eventsByCollection[collection] = (eventsByCollection[collection] ?? 0) + 1;
    lastEventTime = DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'insertEvents': insertEvents,
      'updateEvents': updateEvents,
      'deleteEvents': deleteEvents,
      'lastEventTime': lastEventTime?.toIso8601String(),
      'eventsByCollection': eventsByCollection,
      'totalEvents': insertEvents + updateEvents + deleteEvents,
    };
  }
}

class DittoRealtimeService {
  Ditto get _ditto => DittoConfig.instance;

  final _statusController = StreamController<RealtimeStatus>.broadcast();
  Stream<RealtimeStatus> get statusStream => _statusController.stream;
  RealtimeStatus _currentStatus = RealtimeStatus.disconnected;
  RealtimeStatus get currentStatus => _currentStatus;

  final _eventsController = StreamController<RealtimeEvent>.broadcast();
  Stream<RealtimeEvent> get eventsStream => _eventsController.stream;

  final Map<String, StoreObserver> _liveQueries = {};
  final _stats = RealtimeStats();
  StreamSubscription<List<Peer>>? _peerSubscription;

  static const List<String> _collections = [
    'rooms',
    'bookings',
    'booking_notes',
    'employees',
    'expenses',
    'cash_transactions',
    'payments',
    'debts',
  ];

  Future<void> subscribeToAll() async {
    if (_liveQueries.isNotEmpty) {
      debugPrint('⚠️ Already subscribed to collections');
      return;
    }

    if (!DittoConfig.isInitialized) {
      debugPrint('❌ Ditto not initialized');
      _updateStatus(RealtimeStatus.error);
      return;
    }

    try {
      _updateStatus(RealtimeStatus.connecting);
      debugPrint('🔄 Subscribing to all collections...');

      _setupPeerMonitoring();

      for (final collectionName in _collections) {
        await _subscribeToCollection(collectionName);
      }

      _updateStatus(RealtimeStatus.connected);
      debugPrint('✅ Successfully subscribed to all collections');
    } catch (e) {
      debugPrint('❌ Error subscribing to collections: $e');
      _updateStatus(RealtimeStatus.error);
      rethrow;
    }
  }

  void _setupPeerMonitoring() {
    _peerSubscription?.cancel();
    _peerSubscription = DittoConfig.observePeers().listen(
      (peers) {
        debugPrint('👥 Connected peers: ${peers.length}');
        if (peers.isNotEmpty && _currentStatus != RealtimeStatus.connected) {
          _updateStatus(RealtimeStatus.connected);
        } else if (peers.isEmpty && _currentStatus == RealtimeStatus.connected) {
          _updateStatus(RealtimeStatus.disconnected);
        }
      },
      onError: (error) {
        debugPrint('❌ Peer monitoring error: $error');
        _updateStatus(RealtimeStatus.error);
      },
    );
  }

  Future<void> _subscribeToCollection(String collectionName) async {
    try {
      final observer = _ditto.store.registerObserver(
        'SELECT * FROM $collectionName',
        onChange: (result) {
          _handleCollectionChange(collectionName, result);
        },
      );
      _liveQueries[collectionName] = observer;
      debugPrint('✓ Subscribed to: $collectionName');
    } catch (e) {
      debugPrint('❌ Failed to subscribe to $collectionName: $e');
    }
  }

  void _handleCollectionChange(
    String collectionName,
    QueryResult result,
  ) {
    try {
      for (final item in result.items) {
        final data = item.value;
        final event = RealtimeEvent(
          collection: collectionName,
          eventType: _determineEventType(data),
          document: data,
          timestamp: DateTime.now(),
        );
        _stats.recordEvent(collectionName, event.eventType);
        _eventsController.add(event);
        debugPrint('📥 ${event.eventType} in $collectionName: ${data['local_uuid'] ?? 'unknown'}');
      }
    } catch (e) {
      debugPrint('❌ Error handling collection change: $e');
    }
  }

  String _determineEventType(Map<String, dynamic> data) {
    if (data.containsKey('deleted_at') && data['deleted_at'] != null) {
      return 'delete';
    }
    
    if (data.containsKey('created_at') && data.containsKey('updated_at')) {
      final created = data['created_at'];
      final updated = data['updated_at'];
      if (created == updated) {
        return 'insert';
      }
    }

    return 'update';
  }

  Future<void> unsubscribeAll() async {
    if (_liveQueries.isEmpty) {
      _updateStatus(RealtimeStatus.disconnected);
      return;
    }

    debugPrint('🔌 Unsubscribing from all collections...');

    for (final observer in _liveQueries.values) {
      try {
        observer.cancel();
      } catch (e) {
        debugPrint('⚠️ Error stopping observer: $e');
      }
    }

    _liveQueries.clear();
    await _peerSubscription?.cancel();
    _peerSubscription = null;

    _updateStatus(RealtimeStatus.disconnected);
    debugPrint('✅ Unsubscribed from all collections');
  }

  Future<void> subscribeToRooms(
    Function(List<Map<String, dynamic>>) onChanged,
  ) async {
    await _subscribeToSpecificCollection('rooms', onChanged);
  }

  Future<void> subscribeToBookings(
    Function(List<Map<String, dynamic>>) onChanged,
  ) async {
    await _subscribeToSpecificCollection('bookings', onChanged);
  }

  Future<void> subscribeToEmployees(
    Function(List<Map<String, dynamic>>) onChanged,
  ) async {
    await _subscribeToSpecificCollection('employees', onChanged);
  }

  Future<void> subscribeToExpenses(
    Function(List<Map<String, dynamic>>) onChanged,
  ) async {
    await _subscribeToSpecificCollection('expenses', onChanged);
  }

  Future<void> _subscribeToSpecificCollection(
    String collectionName,
    Function(List<Map<String, dynamic>>) onChanged,
  ) async {
    try {
      final observer = _ditto.store.registerObserver(
        'SELECT * FROM $collectionName',
        onChange: (result) {
          onChanged(result.items.map((e) => e.value).toList());
        },
      );
      _liveQueries['custom_$collectionName'] = observer;
      debugPrint('✓ Custom subscription to: $collectionName');
    } catch (e) {
      debugPrint('❌ Failed custom subscription to $collectionName: $e');
    }
  }

  Map<String, dynamic> getStats() {
    return _stats.toMap();
  }

  Future<List<Map<String, dynamic>>> getPeersInfo() async {
    try {
      final peers = await DittoConfig.getCurrentPeers();
      return peers.map((peer) {
        return {
          'deviceName': peer.deviceName,
          'connections': peer.connections.map((c) => c.toString()).toList(),
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ Error getting peers info: $e');
      return [];
    }
  }

  void _updateStatus(RealtimeStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  Future<void> dispose() async {
    await unsubscribeAll();
    await _statusController.close();
    await _eventsController.close();
    debugPrint('🔌 Ditto Realtime Service disposed');
  }
}

final dittoRealtimeServiceProvider = Provider<DittoRealtimeService>((ref) {
  final service = DittoRealtimeService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
