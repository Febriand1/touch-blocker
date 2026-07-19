import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import 'package:touch_blocker/features/app_selector/models/app_item.dart';

/// Service responsible for fetching the list of user-installed, launchable apps.
///
/// Caching strategy:
///   - First call: fetches from OS via [InstalledApps.getInstalledApps] (slow IPC).
///   - Subsequent calls: returns [_cachedApps] directly — O(1), zero IPC overhead.
///   - Cache is process-scoped (static field) and lives for the app's lifetime.
///   - Call [invalidateCache] if you need to force a fresh fetch (e.g., after
///     the user installs/uninstalls an app while the app is in the foreground).
///
/// Filtering:
///   - System apps and non-launchable background processes are excluded at source.
///   - Result is sorted alphabetically by app name.
class AppFetcherService {
  const AppFetcherService();

  // --------------------------------------------------------------------------
  // Static in-memory cache
  // --------------------------------------------------------------------------

  /// Null = cache is cold (never fetched). Non-null = hot (return immediately).
  static List<AppItem>? _cachedApps;

  /// Clears the cache. Call this if the installed app list may have changed
  /// (e.g., the user navigates back from a package manager screen).
  static void invalidateCache() => _cachedApps = null;

  // --------------------------------------------------------------------------
  // Public API
  // --------------------------------------------------------------------------

  /// Returns a sorted list of user-installed, launchable [AppItem]s with icons.
  ///
  /// On first call: hits the OS platform channel (~100–500 ms depending on
  /// device and number of apps). On subsequent calls: returns the cached list
  /// instantly without any platform invocation.
  ///
  /// Throws on unrecoverable platform errors; callers should wrap in try-catch.
  Future<List<AppItem>> fetchLaunchableApps() async {
    // Cache hit — return immediately without hitting the platform channel.
    if (_cachedApps != null) {
      return _cachedApps!;
    }

    // Cache miss — fetch from OS, map, sort, then store.
    final List<AppInfo> rawApps = await InstalledApps.getInstalledApps(
      excludeSystemApps: true,
      excludeNonLaunchableApps: true,
      withIcon: true,
    );

    final List<AppItem> items = rawApps
        .map(
          (info) => AppItem(
            name: info.name,
            packageName: info.packageName,
            icon: info.icon,
          ),
        )
        .toList();

    // Sort alphabetically by display name (case-insensitive).
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Populate cache so the next call is O(1).
    _cachedApps = items;

    return items;
  }
}
