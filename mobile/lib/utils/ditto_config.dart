import 'dart:async';
import 'package:ditto_live/ditto_live.dart';
import 'package:flutter/foundation.dart';

class DittoConfig {
  static const String dittoAppId = '1507d904-d3ed-4ac3-824c-249c18170eee';
  static const String dittoOnlinePlaygroundToken = 'dbae5191-2cb5-4fb5-8aca-9f9d85e0409a';
  static const String dittoApiToken = 'Vc4wt9ruMMtlf9zS1wh8RSoqT8HN9aB8CYfeDY95KC4kKSEtkfmgHOupZBkO';
  static const String dittoBigPeerUrl = 'wss://i83inp.cloud.dittolive.app/1507d904-d3ed-4ac3-824c-249c18170eee';

  static Ditto? _instance;
  static bool _isInitialized = false;

  static Ditto get instance {
    if (_instance == null) {
      throw Exception(
        'Ditto not initialized. Call DittoConfig.initialize() first.',
      );
    }
    return _instance!;
  }

  static bool get isInitialized => _isInitialized;

  static Future<void> initialize({
    String? customAppId,
    String? customToken,
    String? customBigPeerUrl,
  }) async {
    if (_isInitialized) {
      debugPrint('⚠️ Ditto already initialized');
      return;
    }

    try {
      debugPrint('🔄 Initializing Ditto...');

      final appId = customAppId ?? dittoAppId;
      final token = customToken ?? dittoOnlinePlaygroundToken;
      final bigPeerUrl = customBigPeerUrl ?? dittoBigPeerUrl;

      debugPrint('🔑 Using Ditto App ID: $appId');
      debugPrint('🌐 Big Peer URL: $bigPeerUrl');

      final identity = OnlinePlaygroundIdentity(
        appID: appId,
        token: token,
        enableDittoCloudSync: true,
      );

      _instance = await Ditto.open(identity: identity);

      _instance!.startSync();

      if (bigPeerUrl.isNotEmpty) {
        _instance!.updateTransportConfig((config) {
          config.peerToPeer.bluetoothLE.isEnabled = true;
          config.peerToPeer.lan.isEnabled = true;
          config.peerToPeer.awdl.isEnabled = true;
          config.connect = Connect(webSocketUrls: {bigPeerUrl});
        });
        debugPrint('🌐 Connected to Big Peer: $bigPeerUrl');
      }

      _isInitialized = true;
      debugPrint('✅ Ditto initialized successfully');
      debugPrint('📱 Device ID: ${_instance!.deviceName}');
    } catch (e) {
      debugPrint('❌ Failed to initialize Ditto: $e');
      rethrow;
    }
  }

  static Future<void> startSync() async {
    if (!_isInitialized || _instance == null) {
      debugPrint('⚠️ Cannot start sync: Ditto not initialized');
      return;
    }

    try {
      _instance!.startSync();
      debugPrint('✅ Ditto sync started');
    } catch (e) {
      debugPrint('❌ Failed to start sync: $e');
      rethrow;
    }
  }

  static Future<void> stopSync() async {
    if (!_isInitialized || _instance == null) {
      return;
    }

    try {
      _instance!.stopSync();
      debugPrint('🛑 Ditto sync stopped');
    } catch (e) {
      debugPrint('❌ Failed to stop sync: $e');
      rethrow;
    }
  }

  static Stream<List<Peer>> observePeers() {
    if (!_isInitialized || _instance == null) {
      return Stream.empty();
    }

    final controller = StreamController<List<Peer>>.broadcast();
    _instance!.presence.observe((graph) {
      try {
        final peers = <Peer>[];
        peers.addAll(graph.remotePeers);
        controller.add(peers);
      } catch (e) {
        controller.addError(e);
      }
    });
    return controller.stream;
  }

  static Future<List<Peer>> getCurrentPeers() async {
    if (!_isInitialized || _instance == null) {
      return [];
    }
    try {
      final graph = _instance!.presence.graph;
      return [...graph.remotePeers];
    } catch (_) {
      return [];
    }
  }

  static Future<void> dispose() async {
    if (!_isInitialized || _instance == null) {
      return;
    }

    try {
      await stopSync();
      _instance = null;
      _isInitialized = false;
      debugPrint('🔌 Ditto disposed');
    } catch (e) {
      debugPrint('❌ Error disposing Ditto: $e');
    }
  }

  static Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'deviceName': _instance?.deviceName ?? 'N/A',
      'appId': dittoAppId,
      'bigPeerUrl': dittoBigPeerUrl,
    };
  }

  static Future<Map<String, dynamic>> getDetailedStatus() async {
    if (!_isInitialized || _instance == null) {
      return {
        'isInitialized': false,
        'error': 'Ditto not initialized',
      };
    }

    try {
      final peers = await getCurrentPeers();
      return {
        'isInitialized': true,
        'deviceName': _instance!.deviceName,
        'appId': dittoAppId,
        'bigPeerUrl': dittoBigPeerUrl,
        'connectedPeers': peers.length,
        'peers': peers.map((p) => {
          'deviceName': p.deviceName,
          'connections': p.connections.map((c) => c.toString()).toList(),
        }).toList(),
      };
    } catch (e) {
      return {
        'isInitialized': true,
        'error': e.toString(),
      };
    }
  }

  // Helper removed: use Ditto.store.registerObserver / execute directly with DQL queries in v4.12+

}
