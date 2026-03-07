import 'package:flutter/material.dart';
import '../services/screen_sync_controller.dart';

mixin SyncOnExitMixin<T extends StatefulWidget> on State<T> {
  late final ScreenSyncController _syncController;

  String get screenId;

  Duration get debounceDelay => const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _syncController = ScreenSyncController(
      screenId: screenId,
      debounceDelay: debounceDelay,
    );
  }

  @override
  void dispose() {
    _syncController.dispose();
    super.dispose();
  }

  void markDataChanged() {
    _syncController.markChanged();
  }

  bool get hasUnsyncedChanges => _syncController.hasChanges;

  Future<bool> syncNow() => _syncController.syncNow();

  Stream<SyncStatus> get syncStatusStream => _syncController.syncStatusStream;

  Widget wrapWithSyncOnExit({required Widget child}) {
    return WillPopScope(
      onWillPop: () async {
        await _syncController.syncOnExit();
        return true;
      },
      child: child,
    );
  }
}
