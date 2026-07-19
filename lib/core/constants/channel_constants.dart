/// Defines the IPC contract between Flutter and Kotlin native layer.
///
/// All channel names and method identifiers are centralized here to prevent
/// typo-driven runtime failures — treat this as the "API spec" for the bridge.
class ChannelConstants {
  ChannelConstants._(); // Prevent instantiation.

  /// Must match the channel name registered in [MainActivity.kt].
  static const String lockServiceChannel =
      'com.utility.touch_blocker/lock_service';

  // --------------------------------------------------------------------------
  // Service control  (Flutter → Kotlin)
  // --------------------------------------------------------------------------

  /// Sends a `List<String>` of package names that should be monitored.
  /// Kotlin will update its in-memory `Set<String>` cache on receipt
  /// AND persist the list to SharedPreferences.
  static const String setTargetPackages = 'setTargetPackages';

  /// Reads the persisted `List<String>` of package names from SharedPreferences.
  /// Used by Flutter on startup to hydrate UI state without re-fetching from OS.
  static const String getTargetPackages = 'getTargetPackages';

  /// Instructs Kotlin to start the overlay / lock engine.
  static const String startLockService = 'startLockService';

  /// Instructs Kotlin to stop the overlay / lock engine and destroy the view.
  static const String stopLockService = 'stopLockService';

  /// Queries whether the lock service has been started/is active in SharedPreferences.
  static const String isLockServiceActive = 'isLockServiceActive';

  // --------------------------------------------------------------------------
  // Permission checks  (Flutter → Kotlin, returns bool)
  // --------------------------------------------------------------------------

  /// Checks whether SYSTEM_ALERT_WINDOW ("Display over other apps") is granted.
  /// Required to draw the TYPE_APPLICATION_OVERLAY window.
  static const String isOverlayGranted = 'isOverlayGranted';

  /// Checks whether [LockAccessibilityService] is enabled in Android settings.
  /// Required for event-driven foreground app detection.
  static const String isAccessibilityGranted = 'isAccessibilityGranted';

  // --------------------------------------------------------------------------
  // Permission requests  (Flutter → Kotlin, opens system settings, returns void)
  // --------------------------------------------------------------------------

  /// Opens the "Display over other apps" system settings page for this app.
  /// Uses [Settings.ACTION_MANAGE_OVERLAY_PERMISSION].
  static const String requestOverlayPermission = 'requestOverlayPermission';

  /// Opens the system Accessibility Settings page.
  /// Uses [Settings.ACTION_ACCESSIBILITY_SETTINGS].
  static const String requestAccessibilityPermission =
      'requestAccessibilityPermission';
}
