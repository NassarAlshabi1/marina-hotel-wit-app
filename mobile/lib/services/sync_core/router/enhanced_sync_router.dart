import 'dart:async';

import 'package:flutter/foundation.dart';

import '../events/sync_event.dart';
import '../adapters/sync_target_adapter.dart';
import '../enhanced_event_bus.dart';

enum RoutingStrategy { all, primaryFirst, roundRobin, priority, failover }

class SyncRouterConfig {
  final RoutingStrategy strategy;
  final Duration debounceWindow;
  final int maxBatchSize;
  final int maxRetries;
  final Duration retryDelay;
  final bool enableParallel;
  final SyncTargetType? primaryTarget;
  final List<SyncTargetType> targetPriority;

  const SyncRouterConfig({
    this.strategy = RoutingStrategy.all,
    this.debounceWindow = const Duration(seconds: 2),
    this.maxBatchSize = 50,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.enableParallel = true,
    this.primaryTarget,
    this.targetPriority = const [
      SyncTargetType.appwrite,
      SyncTargetType.googleDrive,
      SyncTargetType.localJson,
    ],
  });

  SyncRouterConfig copyWith({
    RoutingStrategy? strategy,
    Duration? debounceWindow,
    int? maxBatchSize,
    int? maxRetries,
    Duration? retryDelay,
    bool? enableParallel,
    SyncTargetType? primaryTarget,
    List<SyncTargetType>? targetPriority,
  }) {
    return SyncRouterConfig(
      strategy: strategy ?? this.strategy,
      debounceWindow: debounceWindow ?? this.debounceWindow,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      enableParallel: enableParallel ?? this.enableParallel,
      primaryTarget: primaryTarget ?? this.primaryTarget,
      targetPriority: targetPriority ?? this.targetPriority,
    );
  }
}

class RouteResult {
  final bool success;
  final Map<SyncTargetType, SyncPushResult> results;
  final Duration totalDuration;
  final int successCount;
  final int failureCount;

  const RouteResult({
    required this.success,
    required this.results,
    required this.totalDuration,
    required this.successCount,
    required this.failureCount,
  });

  factory RouteResult.empty() {
    return const RouteResult(
      success: true,
      results: {},
      totalDuration: Duration.zero,
      successCount: 0,
      failureCount: 0,
    );
  }

  String? get firstError {
    for (final result in results.values) {
      if (!result.success && result.error != null) {
        return result.error;
      }
    }
    return null;
  }
}

class EnhancedSyncRouter {
  final EnhancedEventBus _eventBus;
  final Map<SyncTargetType, SyncTargetAdapter> _adapters = {};
  SyncRouterConfig _config;

  StreamSubscription<EnhancedSyncEvent>? _subscription;
  final _pendingEvents = <EnhancedSyncEvent>[];
  Timer? _debounceTimer;
  bool _processing = false;
  bool _started = false;
  int _roundRobinIndex = 0;

  final _stateController = StreamController<SyncRouterState>.broadcast();
  SyncRouterState _state = SyncRouterState.idle;

  EnhancedSyncRouter({
    required EnhancedEventBus eventBus,
    SyncRouterConfig config = const SyncRouterConfig(),
  }) : _eventBus = eventBus,
       _config = config;

  Stream<SyncRouterState> get stateStream => _stateController.stream;
  SyncRouterState get state => _state;
  SyncRouterConfig get config => _config;
  bool get isStarted => _started;
  int get pendingCount => _pendingEvents.length;

  void registerAdapter(SyncTargetAdapter adapter) {
    _adapters[adapter.type] = adapter;
    debugPrint('SyncRouter: Registered adapter ${adapter.name}');
  }

  void unregisterAdapter(SyncTargetType type) {
    _adapters.remove(type);
    debugPrint('SyncRouter: Unregistered adapter $type');
  }

  SyncTargetAdapter? getAdapter(SyncTargetType type) => _adapters[type];

  List<SyncTargetAdapter> get allAdapters => _adapters.values.toList();

  List<SyncTargetAdapter> get enabledAdapters =>
      _adapters.values.where((a) => a.isEnabled && a.isAvailable).toList();

  List<SyncTargetAdapter> get availableAdapters =>
      _adapters.values.where((a) => a.isAvailable).toList();

  void updateConfig(SyncRouterConfig config) {
    _config = config;
  }

  Future<void> start() async {
    if (_started) return;

    for (final adapter in _adapters.values) {
      if (!adapter.isInitialized) {
        try {
          await adapter.initialize();
        } catch (e) {
          debugPrint('SyncRouter: Failed to initialize ${adapter.name}: $e');
        }
      }
    }

    _subscription = _eventBus.stream.listen(_handleEvent);
    _started = true;
    _emitState(SyncRouterState.idle);
    debugPrint('SyncRouter: Started with ${_adapters.length} adapters');
  }

  void _handleEvent(EnhancedSyncEvent event) {
    _pendingEvents.add(event);

    if (event.isCritical) {
      _flush();
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_config.debounceWindow, _flush);

    if (_pendingEvents.length >= _config.maxBatchSize) {
      _flush();
    }
  }

  Future<RouteResult> _flush() async {
    if (_processing || _pendingEvents.isEmpty) {
      return RouteResult.empty();
    }

    _processing = true;
    _debounceTimer?.cancel();
    _emitState(SyncRouterState.syncing);

    final batch = List<EnhancedSyncEvent>.from(_pendingEvents);
    _pendingEvents.clear();

    batch.sort((a, b) => a.priority.value.compareTo(b.priority.value));

    final stopwatch = Stopwatch()..start();
    final results = <SyncTargetType, SyncPushResult>{};
    var successCount = 0;
    var failureCount = 0;

    final adapters = enabledAdapters;
    if (adapters.isEmpty) {
      _processing = false;
      _emitState(SyncRouterState.idle);
      return RouteResult.empty();
    }

    try {
      switch (_config.strategy) {
        case RoutingStrategy.all:
          final strategyResults = await _routeToAll(batch, adapters);
          results.addAll(strategyResults);
          break;

        case RoutingStrategy.primaryFirst:
          final strategyResults = await _routePrimaryFirst(batch, adapters);
          results.addAll(strategyResults);
          break;

        case RoutingStrategy.roundRobin:
          final strategyResults = await _routeRoundRobin(batch, adapters);
          results.addAll(strategyResults);
          break;

        case RoutingStrategy.priority:
          final strategyResults = await _routeByPriority(batch, adapters);
          results.addAll(strategyResults);
          break;

        case RoutingStrategy.failover:
          final strategyResults = await _routeWithFailover(batch, adapters);
          results.addAll(strategyResults);
          break;
      }

      for (final result in results.values) {
        if (result.success) {
          successCount++;
        } else {
          failureCount++;
        }
      }

      for (final event in batch) {
        await _eventBus.acknowledge(event.id);
      }
    } finally {
      stopwatch.stop();
      _processing = false;
      _emitState(
        failureCount > 0 ? SyncRouterState.error : SyncRouterState.idle,
      );
    }

    return RouteResult(
      success: failureCount == 0,
      results: results,
      totalDuration: stopwatch.elapsed,
      successCount: successCount,
      failureCount: failureCount,
    );
  }

  Future<Map<SyncTargetType, SyncPushResult>> _routeToAll(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    final results = <SyncTargetType, SyncPushResult>{};

    if (_config.enableParallel) {
      final futures = adapters.map((adapter) async {
        final result = await _pushWithRetry(adapter, events);
        return MapEntry(adapter.type, result);
      });

      final entries = await Future.wait(futures);
      results.addAll(Map.fromEntries(entries));
    } else {
      for (final adapter in adapters) {
        results[adapter.type] = await _pushWithRetry(adapter, events);
      }
    }

    return results;
  }

  Future<Map<SyncTargetType, SyncPushResult>> _routePrimaryFirst(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    final results = <SyncTargetType, SyncPushResult>{};

    final primaryType = _config.primaryTarget ?? SyncTargetType.appwrite;
    final primary = adapters.firstWhere(
      (a) => a.type == primaryType,
      orElse: () => adapters.first,
    );

    final primaryResult = await _pushWithRetry(primary, events);
    results[primary.type] = primaryResult;

    if (primaryResult.success) {
      final others = adapters.where((a) => a != primary);

      if (_config.enableParallel) {
        final futures = others.map((adapter) async {
          final result = await _pushWithRetry(adapter, events);
          return MapEntry(adapter.type, result);
        });

        final entries = await Future.wait(futures);
        results.addAll(Map.fromEntries(entries));
      } else {
        for (final adapter in others) {
          results[adapter.type] = await _pushWithRetry(adapter, events);
        }
      }
    }

    return results;
  }

  Future<Map<SyncTargetType, SyncPushResult>> _routeRoundRobin(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    final results = <SyncTargetType, SyncPushResult>{};
    final eventGroups = <SyncTargetType, List<EnhancedSyncEvent>>{};

    for (final event in events) {
      final adapter = adapters[_roundRobinIndex % adapters.length];
      eventGroups.putIfAbsent(adapter.type, () => []).add(event);
      _roundRobinIndex++;
    }

    for (final entry in eventGroups.entries) {
      final adapter = _adapters[entry.key];
      if (adapter != null) {
        results[entry.key] = await _pushWithRetry(adapter, entry.value);
      }
    }

    return results;
  }

  Future<Map<SyncTargetType, SyncPushResult>> _routeByPriority(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    final results = <SyncTargetType, SyncPushResult>{};

    final criticalEvents = events
        .where((e) => e.priority == SyncPriority.critical)
        .toList();
    final highEvents = events
        .where((e) => e.priority == SyncPriority.high)
        .toList();
    final normalEvents = events
        .where(
          (e) =>
              e.priority != SyncPriority.critical &&
              e.priority != SyncPriority.high,
        )
        .toList();

    if (criticalEvents.isNotEmpty) {
      final criticalResults = await _routeToAll(criticalEvents, adapters);
      for (final entry in criticalResults.entries) {
        results[entry.key] = entry.value;
      }
    }

    if (highEvents.isNotEmpty) {
      final primaryType = _config.primaryTarget ?? SyncTargetType.appwrite;
      final primary = adapters.firstWhere(
        (a) => a.type == primaryType,
        orElse: () => adapters.first,
      );

      final highResult = await _pushWithRetry(primary, highEvents);
      results[primary.type] = SyncPushResult(
        success: (results[primary.type]?.success ?? true) && highResult.success,
        affectedCount:
            (results[primary.type]?.affectedCount ?? 0) +
            highResult.affectedCount,
        syncedIds: [
          ...(results[primary.type]?.syncedIds ?? []),
          ...highResult.syncedIds,
        ],
        failedIds: [
          ...(results[primary.type]?.failedIds ?? []),
          ...highResult.failedIds,
        ],
      );
    }

    if (normalEvents.isNotEmpty) {
      final localAdapter = adapters.firstWhere(
        (a) => a.type == SyncTargetType.localJson,
        orElse: () => adapters.first,
      );

      final normalResult = await _pushWithRetry(localAdapter, normalEvents);
      results[localAdapter.type] = SyncPushResult(
        success:
            (results[localAdapter.type]?.success ?? true) &&
            normalResult.success,
        affectedCount:
            (results[localAdapter.type]?.affectedCount ?? 0) +
            normalResult.affectedCount,
        syncedIds: [
          ...(results[localAdapter.type]?.syncedIds ?? []),
          ...normalResult.syncedIds,
        ],
        failedIds: [
          ...(results[localAdapter.type]?.failedIds ?? []),
          ...normalResult.failedIds,
        ],
      );
    }

    return results;
  }

  Future<Map<SyncTargetType, SyncPushResult>> _routeWithFailover(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    final results = <SyncTargetType, SyncPushResult>{};

    final sortedAdapters = List<SyncTargetAdapter>.from(adapters);
    sortedAdapters.sort((a, b) {
      final aIndex = _config.targetPriority.indexOf(a.type);
      final bIndex = _config.targetPriority.indexOf(b.type);
      return aIndex.compareTo(bIndex);
    });

    for (final adapter in sortedAdapters) {
      final result = await _pushWithRetry(adapter, events);
      results[adapter.type] = result;

      if (result.success) {
        debugPrint('SyncRouter: Failover succeeded with ${adapter.name}');
        break;
      } else {
        debugPrint(
          'SyncRouter: Failover failed with ${adapter.name}, trying next...',
        );
      }
    }

    return results;
  }

  Future<SyncPushResult> _pushWithRetry(
    SyncTargetAdapter adapter,
    List<EnhancedSyncEvent> events,
  ) async {
    var attempts = 0;
    SyncPushResult? lastResult;

    while (attempts < _config.maxRetries) {
      try {
        lastResult = await adapter.push(events);
        if (lastResult.success) return lastResult;
      } catch (e) {
        lastResult = SyncPushResult.failure(error: e.toString());
      }

      attempts++;
      if (attempts < _config.maxRetries) {
        final delay = _config.retryDelay * (1 << (attempts - 1));
        await Future.delayed(delay);
      }
    }

    return lastResult ?? SyncPushResult.failure(error: 'Max retries exceeded');
  }

  Future<RouteResult> syncNow({
    bool push = true,
    bool pull = true,
    List<SyncTargetType>? targets,
  }) async {
    final adapters = targets != null
        ? enabledAdapters.where((a) => targets.contains(a.type)).toList()
        : enabledAdapters;

    if (adapters.isEmpty) {
      return RouteResult.empty();
    }

    final stopwatch = Stopwatch()..start();
    final results = <SyncTargetType, SyncPushResult>{};
    var successCount = 0;
    var failureCount = 0;

    _emitState(SyncRouterState.syncing);

    try {
      if (push && _pendingEvents.isNotEmpty) {
        final flushResult = await _flush();
        results.addAll(flushResult.results);
        successCount += flushResult.successCount;
        failureCount += flushResult.failureCount;
      }

      if (pull) {
        for (final adapter in adapters) {
          try {
            final pullResult = await adapter.pull();
            if (!pullResult.success) {
              failureCount++;
            }
          } catch (e) {
            failureCount++;
            debugPrint('SyncRouter: Pull failed for ${adapter.name}: $e');
          }
        }
      }
    } finally {
      stopwatch.stop();
      _emitState(
        failureCount > 0 ? SyncRouterState.error : SyncRouterState.idle,
      );
    }

    return RouteResult(
      success: failureCount == 0,
      results: results,
      totalDuration: stopwatch.elapsed,
      successCount: successCount,
      failureCount: failureCount,
    );
  }

  Future<Map<SyncTargetType, SyncTargetStatus>> getAdapterStatuses() async {
    final statuses = <SyncTargetType, SyncTargetStatus>{};

    for (final adapter in _adapters.values) {
      statuses[adapter.type] = await adapter.getStatus();
    }

    return statuses;
  }

  void _emitState(SyncRouterState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _started = false;
    _emitState(SyncRouterState.stopped);
  }

  Future<void> dispose() async {
    await stop();
    await _stateController.close();

    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }
    _adapters.clear();
  }
}

enum SyncRouterState { idle, syncing, error, stopped }
