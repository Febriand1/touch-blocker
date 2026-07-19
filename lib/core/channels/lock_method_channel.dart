import 'package:flutter/services.dart';
import 'package:touch_blocker/core/constants/channel_constants.dart';

/// Flutter-side abstraction of the MethodChannel IPC bridge.
///
/// This class is the **only** point of contact between Dart code and the
/// native Kotlin layer. All calls are typed, async, and wrapped in try-catch.
/// No background loops or polling — ever.
class LockMethodChannel {
  LockMethodChannel._();

  static final MethodChannel _channel =
      const MethodChannel(ChannelConstants.lockServiceChannel);

  // --------------------------------------------------------------------------
  // Service control
  // --------------------------------------------------------------------------

  /// Sends [packageNames] to Kotlin. Kotlin stores them in a `Set<String>`
  /// for O(1) lookups AND persists them to SharedPreferences.
  /// Returns `true` on success, `false` on failure.
  static Future<bool> setTargetPackages(List<String> packageNames) async {
    try {
      await _channel.invokeMethod<void>(
        ChannelConstants.setTargetPackages,
        packageNames,
      );
      return true;
    } on PlatformException catch (e) {
      _logError(ChannelConstants.setTargetPackages, e);
      return false;
    }
  }

  /// Reads the persisted target package list from Android SharedPreferences.
  ///
  /// Returns the saved `List<String>` on success, or an empty list on error.
  /// Call this in [initState] of any UI screen that needs to restore selection
  /// state without triggering an OS-level app re-fetch.
  static Future<List<String>> getTargetPackages() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        ChannelConstants.getTargetPackages,
      );
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      _logError(ChannelConstants.getTargetPackages, e);
      return [];
    }
  }

  /// Activates the overlay engine and begins app monitoring.
  /// Returns `true` on success, `false` on failure.
  static Future<bool> startLockService() async {
    try {
      await _channel.invokeMethod<void>(ChannelConstants.startLockService);
      return true;
    } on PlatformException catch (e) {
      _logError(ChannelConstants.startLockService, e);
      return false;
    }
  }

  /// Deactivates the engine and **destroys** the overlay view, freeing RAM.
  /// Returns `true` on success, `false` on failure.
  static Future<bool> stopLockService() async {
    try {
      await _channel.invokeMethod<void>(ChannelConstants.stopLockService);
      return true;
    } on PlatformException catch (e) {
      _logError(ChannelConstants.stopLockService, e);
      return false;
    }
  }

  /// Queries whether the lock service has been set as active in SharedPreferences.
  ///
  /// Returns `true` if active, `false` otherwise.
  static Future<bool> isLockServiceActive() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelConstants.isLockServiceActive,
      );
      return result ?? false;
    } on PlatformException catch (e) {
      _logError(ChannelConstants.isLockServiceActive, e);
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Permission checks  (return bool — no side effects)
  // --------------------------------------------------------------------------

  /// Returns `true` if SYSTEM_ALERT_WINDOW ("Display over other apps") is
  /// granted. Must be true before the overlay engine can start.
  static Future<bool> isOverlayGranted() async {
    try {
      final result =
          await _channel.invokeMethod<bool>(ChannelConstants.isOverlayGranted);
      return result ?? false;
    } on PlatformException catch (e) {
      _logError(ChannelConstants.isOverlayGranted, e);
      return false;
    }
  }

  /// Returns `true` if [LockAccessibilityService] is enabled in Android
  /// system settings. Must be true for foreground app detection to work.
  static Future<bool> isAccessibilityGranted() async {
    try {
      final result = await _channel.invokeMethod<bool>(
          ChannelConstants.isAccessibilityGranted);
      return result ?? false;
    } on PlatformException catch (e) {
      _logError(ChannelConstants.isAccessibilityGranted, e);
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Permission requests  (open system settings — void, no return value)
  // --------------------------------------------------------------------------

  /// Opens the Android "Display over other apps" settings page for this app.
  /// The UI should re-check [isOverlayGranted] when it resumes (via
  /// [WidgetsBindingObserver.didChangeAppLifecycleState]).
  static Future<void> requestOverlayPermission() async {
    try {
      await _channel
          .invokeMethod<void>(ChannelConstants.requestOverlayPermission);
    } on PlatformException catch (e) {
      _logError(ChannelConstants.requestOverlayPermission, e);
    }
  }

  /// Opens the Android Accessibility Settings page.
  /// The UI should re-check [isAccessibilityGranted] when it resumes.
  static Future<void> requestAccessibilityPermission() async {
    try {
      await _channel
          .invokeMethod<void>(ChannelConstants.requestAccessibilityPermission);
    } on PlatformException catch (e) {
      _logError(ChannelConstants.requestAccessibilityPermission, e);
    }
  }

  // --------------------------------------------------------------------------
  // Private helpers
  // --------------------------------------------------------------------------

  static void _logError(String method, PlatformException e) {
    // ignore: avoid_print
    print('[LockMethodChannel] $method failed — ${e.code}: ${e.message}');
  }
}
