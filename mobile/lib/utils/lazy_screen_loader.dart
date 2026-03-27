import 'package:flutter/material.dart';

/// Lazy screen loader - loads screens on demand with caching
class LazyScreenLoader {
  static final Map<String, Widget> _cache = {};
  static final Map<String, Future<Widget>?> _loading = {};

  /// Load screen with caching - first call loads, subsequent calls return cached
  static Widget cached<T extends Widget>({
    required String key,
    required Future<T> Function() loader,
    Widget? placeholder,
  }) {
    return FutureBuilder<T>(
      future: () async {
        // Check cache first
        if (_cache.containsKey(key)) {
          return _cache[key] as T;
        }

        // Check if already loading
        if (_loading.containsKey(key)) {
          final widget = await _loading[key];
          if (widget != null) {
            _cache[key] = widget;
            return widget as T;
          }
        }

        // Start loading
        _loading[key] = loader().then((widget) {
          _cache[key] = widget;
          _loading.remove(key);
          return widget;
        });

        return await _loading[key] as T;
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder ?? const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        return snapshot.data ?? const SizedBox.shrink();
      },
    );
  }

  /// Preload screen in background
  static Future<void> preload(String key, Future<Widget> Function() loader) async {
    if (!_cache.containsKey(key) && !_loading.containsKey(key)) {
      _loading[key] = loader().then((widget) {
        _cache[key] = widget;
        _loading.remove(key);
        return widget;
      });
    }
  }

  /// Clear cache for specific key
  static void clear(String key) {
    _cache.remove(key);
    _loading.remove(key);
  }

  /// Clear all cached screens
  static void clearAll() {
    _cache.clear();
    _loading.clear();
  }

  /// Check if screen is cached
  static bool isCached(String key) => _cache.containsKey(key);
}

/// Extension for lazy navigation
extension LazyNavigator on NavigatorState {
  /// Push screen lazily with optional preloading
  Future<T?> pushLazy<T>({
    required String routeName,
    required Future<T> Function() pageBuilder,
    bool preload = false,
  }) async {
    if (preload) {
      LazyScreenLoader.preload(routeName, pageBuilder as Future<Widget> Function());
    }
    final page = await pageBuilder();
    return push<T>(MaterialPageRoute(builder: (_) => page as Widget));
  }
}

/// Mixin for lazy loading StatefulWidgets
mixin LazyLoadMixin<T extends StatefulWidget> on State<T> {
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  void markLoaded() {
    if (mounted) {
      setState(() => _isLoaded = true);
    }
  }

  /// Load data only when widget is visible
  Future<void> loadWhenVisible() async {
    if (_isLoaded) return;
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      markLoaded();
    }
  }
}
