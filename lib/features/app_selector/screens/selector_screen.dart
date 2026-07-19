import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:touch_blocker/l10n/app_localizations.dart';

import 'package:touch_blocker/core/channels/lock_method_channel.dart';
import 'package:touch_blocker/features/app_selector/models/app_item.dart';
import 'package:touch_blocker/features/app_selector/services/app_fetcher_service.dart';

/// Control panel screen: lets the user pick which installed apps to monitor.
///
/// State management:
///   - [_isLoading]  : true while [AppFetcherService.fetchLaunchableApps] runs.
///   - [_apps]       : full sorted list of installed launchable apps.
///   - [_selected]   : `Set<String>` of currently checked package names.
///   - [_isSaving]   : true while [LockMethodChannel.setTargetPackages] is in flight.
///   - [_searchQuery]: current text in the search field for live filtering.
///
/// Flutter rules (from AGENTS.md):
///   - No background polling — fetch is a single async call on initState.
///   - No complex state management library — plain setState is sufficient here.
///   - All MethodChannel calls are handled inside LockMethodChannel with try-catch.
class SelectorScreen extends StatefulWidget {
  const SelectorScreen({super.key});

  @override
  State<SelectorScreen> createState() => _SelectorScreenState();
}

class _SelectorScreenState extends State<SelectorScreen> {
  static const _service = AppFetcherService();

  // --------------------------------------------------------------------------
  // State
  // --------------------------------------------------------------------------

  bool _isLoading = true;
  String? _errorMessage;
  List<AppItem> _apps = [];
  final Set<String> _selected = {};
  bool _isSaving = false;
  String _searchQuery = '';

  // --------------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadAppsAndSelection();
  }

  // --------------------------------------------------------------------------
  // Data fetching — single async call, no polling.
  // --------------------------------------------------------------------------

  /// Fetches the installed app list and the persisted selection concurrently.
  ///
  /// Both [AppFetcherService.fetchLaunchableApps] and
  /// [LockMethodChannel.getTargetPackages] run in parallel via [Future.wait]
  /// to minimise total loading time. The app list is served from the in-memory
  /// cache on subsequent opens — O(1), zero OS IPC.
  Future<void> _loadAppsAndSelection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Run both calls concurrently; neither depends on the other.
      final results = await Future.wait([
        _service.fetchLaunchableApps(),
        LockMethodChannel.getTargetPackages(),
      ]);

      if (mounted) {
        final apps = results[0] as List<AppItem>;
        final saved = results[1] as List<String>;
        setState(() {
          _apps = apps;
          // Hydrate selection from SharedPreferences. Only add packages that
          // still exist in the current installed-apps list to avoid stale state.
          final installedPkgs = apps.map((a) => a.packageName).toSet();
          _selected
            ..clear()
            ..addAll(saved.where(installedPkgs.contains));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '${AppLocalizations.of(context)!.selectorLoadError}\n${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  // --------------------------------------------------------------------------
  // Selection helpers
  // --------------------------------------------------------------------------

  void _toggleApp(String packageName) {
    setState(() {
      if (_selected.contains(packageName)) {
        _selected.remove(packageName);
      } else {
        _selected.add(packageName);
      }
    });
  }

  List<AppItem> get _filteredApps {
    if (_searchQuery.isEmpty) return _apps;
    final q = _searchQuery.toLowerCase();
    return _apps
        .where((a) =>
            a.name.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
  }

  // --------------------------------------------------------------------------
  // IPC: send selected packages to Kotlin layer via MethodChannel.
  // --------------------------------------------------------------------------

  Future<void> _onSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final packageList = _selected.toList();
    final success = await LockMethodChannel.setTargetPackages(packageList);

    if (!mounted) return;
    setState(() => _isSaving = false);

    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? l10n.selectorSaveSuccess(packageList.length)
              : l10n.selectorSaveError,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? const Color(0xFF1DB954)
            : Theme.of(context).colorScheme.error,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildSaveFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A1A),
      elevation: 0,
      title: Text(
        AppLocalizations.of(context)!.configTargetAppsTitle,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _SearchBar(
            onChanged: (q) => setState(() => _searchQuery = q),
          ),
        ),
      ),
      actions: [
        if (!_isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                AppLocalizations.of(context)!.selectorSelectedCount(_selected.length),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF6C63FF),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.selectorLoadingText,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _ErrorState(message: _errorMessage!, onRetry: _loadAppsAndSelection);
    }

    final displayed = _filteredApps;

    if (displayed.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.selectorEmptyText,
          style: const TextStyle(color: Color(0xFF888888)),
        ),
      );
    }

    return ListView.builder(
      // Extra bottom padding so the last item isn't hidden behind the FAB.
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: displayed.length,
      itemBuilder: (_, index) {
        final app = displayed[index];
        final isSelected = _selected.contains(app.packageName);
        return _AppTile(
          app: app,
          isSelected: isSelected,
          onToggle: () => _toggleApp(app.packageName),
        );
      },
    );
  }

  Widget _buildSaveFab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
          ),
          onPressed: _isSaving ? null : _onSave,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.lock_outline_rounded, size: 20),
          label: Text(
            _isSaving
                ? AppLocalizations.of(context)!.selectorApplyingText
                : AppLocalizations.of(context)!.selectorSaveButton(_selected.length),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-widgets — kept private; they have no business logic of their own.
// =============================================================================

/// Single app row with icon, name, package name, and a checkbox.
class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.isSelected,
    required this.onToggle,
  });

  final AppItem app;
  final bool isSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF6C63FF).withAlpha(30)
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF6C63FF).withAlpha(180)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        onTap: onToggle,
        leading: _AppIcon(iconBytes: app.icon),
        title: Text(
          app.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          app.packageName,
          style: const TextStyle(
            color: Color(0xFF666666),
            fontSize: 11,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isSelected
              ? const Icon(
                  Icons.check_circle_rounded,
                  key: ValueKey(true),
                  color: Color(0xFF6C63FF),
                  size: 24,
                )
              : const Icon(
                  Icons.circle_outlined,
                  key: ValueKey(false),
                  color: Color(0xFF444444),
                  size: 24,
                ),
        ),
      ),
    );
  }
}

/// Renders the app icon from raw [Uint8List] bytes.
/// Falls back to a generic app icon if bytes are null or fail to decode.
class _AppIcon extends StatelessWidget {
  const _AppIcon({this.iconBytes});

  final Uint8List? iconBytes;

  @override
  Widget build(BuildContext context) {
    if (iconBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          iconBytes!,
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (context, error, _) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.android_rounded,
          color: Color(0xFF555555),
          size: 22,
        ),
      );
}

/// Search bar displayed in the AppBar bottom area.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)!.selectorSearchHint,
        hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: Color(0xFF555555), size: 20),
        filled: true,
        fillColor: const Color(0xFF252525),
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Error state widget shown when app fetching fails.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFF888888), size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context)!.selectorRetryButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C63FF),
                side: const BorderSide(color: Color(0xFF6C63FF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
