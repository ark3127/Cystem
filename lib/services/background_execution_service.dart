import 'package:flutter_background/flutter_background.dart';

/// Keeps Cystem's Flutter isolate alive while a response is being generated.
/// The foreground notification exists only during active generation.
class BackgroundExecutionService {
  static bool _initialized = false;

  Future<void> start() async {
    try {
      if (!_initialized) {
        _initialized = await FlutterBackground.initialize(
          androidConfig: const FlutterBackgroundAndroidConfig(
            notificationTitle: 'CYSTEM',
            notificationText: 'CYSTEM is generating a response…',
            notificationImportance: AndroidNotificationImportance.normal,
            enableWifiLock: true,
            showBadge: false,
          ),
        );
      }
      if (_initialized && !FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
    } catch (_) {
      // A response should still work if the device refuses background execution.
    }
  }

  Future<void> stop() async {
    try {
      if (_initialized && FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (_) {
      // Best effort; generation itself must not fail because of service cleanup.
    }
  }
}
