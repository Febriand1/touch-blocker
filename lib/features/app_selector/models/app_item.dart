import 'dart:typed_data';

/// Lightweight data model for a single installed application.
///
/// Wraps only the fields needed by the selector UI — name, package name,
/// and icon bytes. All heavy AppInfo fields from installed_apps are
/// discarded at the service layer to keep memory footprint minimal.
class AppItem {
  const AppItem({
    required this.name,
    required this.packageName,
    this.icon,
  });

  /// Human-readable app label (e.g., "TikTok").
  final String name;

  /// Unique Android package identifier (e.g., "com.zhiliaoapp.musically").
  /// This is the value sent to the Kotlin layer via MethodChannel.
  final String packageName;

  /// Raw PNG/JPEG bytes of the app icon. Null if the package reported no icon.
  final Uint8List? icon;

  @override
  bool operator ==(Object other) =>
      other is AppItem && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;
}
