import 'package:flutter/material.dart';
import 'package:touch_blocker/l10n/app_localizations.dart';

import 'package:touch_blocker/core/channels/lock_method_channel.dart';
import 'package:touch_blocker/features/app_selector/screens/selector_screen.dart';

/// Dashboard screen — the initial route of the application.
///
/// Responsibilities:
///   1. Display real-time status of both required Android permissions.
///   2. Provide one-tap shortcuts to the relevant system settings pages.
///   3. Offer a master switch to start/stop the lock service (gated by perms).
///   4. Navigate to [SelectorScreen] for choosing target apps.
///
/// Lifecycle pattern:
///   Uses [WidgetsBindingObserver] instead of polling. When the user returns
///   from the Android Settings screen (after granting a permission), the OS
///   resumes this Activity, which fires [didChangeAppLifecycleState] →
///   [AppLifecycleState.resumed] → [_checkPermissions] re-evaluates both
///   permissions and calls setState exactly once.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // --------------------------------------------------------------------------
  // State
  // --------------------------------------------------------------------------

  bool _isOverlayGranted = false;
  bool _isAccessibilityGranted = false;
  bool _isServiceActive = false;
  bool _isTogglingService = false;

  bool get _allPermissionsGranted =>
      _isOverlayGranted && _isAccessibilityGranted;

  // --------------------------------------------------------------------------
  // Lifecycle — WidgetsBindingObserver (zero polling)
  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Fired by the OS whenever this app's lifecycle state changes.
  /// [AppLifecycleState.resumed] fires exactly when the user returns from
  /// Android Settings — the right moment to re-check permissions.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  // --------------------------------------------------------------------------
  // Data — single async burst, no loops.
  // --------------------------------------------------------------------------

  Future<void> _checkPermissions() async {
    final overlay = await LockMethodChannel.isOverlayGranted();
    final accessibility = await LockMethodChannel.isAccessibilityGranted();
    final serviceActive = await LockMethodChannel.isLockServiceActive();
    if (!mounted) return;
    setState(() {
      _isOverlayGranted = overlay;
      _isAccessibilityGranted = accessibility;

      // Logika Keamanan: Jika hasil dari native adalah true, TETAPI
      // _isOverlayGranted atau _isAccessibilityGranted bernilai false,
      // maka paksa _isServiceActive = false dan panggil stopLockService()
      if (serviceActive && (!overlay || !accessibility)) {
        _isServiceActive = false;
        LockMethodChannel.stopLockService();
      } else {
        _isServiceActive = serviceActive;
      }
    });
  }

  // --------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------

  Future<void> _onToggleService(bool value) async {
    if (_isTogglingService) return;
    setState(() => _isTogglingService = true);

    final success = value
        ? await LockMethodChannel.startLockService()
        : await LockMethodChannel.stopLockService();

    if (!mounted) return;
    setState(() {
      if (success) _isServiceActive = value;
      _isTogglingService = false;
    });
  }

  Future<void> _navigateToSelector() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelectorScreen()),
    );
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),
                  _SectionLabel(AppLocalizations.of(context)!.permissionStatusLabel),
                  const SizedBox(height: 10),
                  _PermissionCard(
                    icon: Icons.layers_rounded,
                    title: AppLocalizations.of(context)!.permissionOverlayTitle,
                    description: AppLocalizations.of(context)!.permissionOverlayDesc,
                    isGranted: _isOverlayGranted,
                    onRequest: LockMethodChannel.requestOverlayPermission,
                  ),
                  const SizedBox(height: 10),
                  _PermissionCard(
                    icon: Icons.accessibility_new_rounded,
                    title: AppLocalizations.of(context)!.permissionA11yTitle,
                    description: AppLocalizations.of(context)!.permissionA11yDesc,
                    isGranted: _isAccessibilityGranted,
                    onRequest: LockMethodChannel.requestAccessibilityPermission,
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel(AppLocalizations.of(context)!.serviceControlLabel),
                  const SizedBox(height: 10),
                  _ServiceControlCard(
                    isActive: _isServiceActive,
                    isEnabled: _allPermissionsGranted,
                    isToggling: _isTogglingService,
                    onToggle: _onToggleService,
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel(AppLocalizations.of(context)!.configurationLabel),
                  const SizedBox(height: 10),
                  _NavigationCard(
                    icon: Icons.apps_rounded,
                    title: AppLocalizations.of(context)!.configTargetAppsTitle,
                    description: AppLocalizations.of(context)!.configTargetAppsDesc,
                    onTap: _navigateToSelector,
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final double screenHeight = MediaQuery.of(context).size.height;

    return SliverAppBar(
      expandedHeight: screenHeight * 0.1,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF1A1A1A),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D1B69), Color(0xFF11001C)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withAlpha(50),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF6C63FF).withAlpha(100),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.enhanced_encryption_rounded,
                          color: Color(0xFF6C63FF),
                          size: 28,
                        ),
                      ),

                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.appTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLocalizations.of(context)!.appSubtitle,
                              style: TextStyle(
                                color: Colors.white.withAlpha(140),
                                fontSize: 13,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 16, bottom: 14),
      ),
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

/// Section heading label.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Permission status card. Green when granted, amber when not.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.onRequest,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final Future<void> Function() onRequest;

  Color get _accentColor =>
      isGranted ? const Color(0xFF1DB954) : const Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _accentColor.withAlpha(isGranted ? 80 : 120),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status icon container
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accentColor.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF777777),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (!isGranted) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 34,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: onRequest,
                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                        label: Text(AppLocalizations.of(context)!.grantPermissionButton),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Granted badge
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isGranted
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey(true),
                      color: _accentColor,
                      size: 22,
                    )
                  : Icon(
                      Icons.cancel_rounded,
                      key: const ValueKey(false),
                      color: _accentColor.withAlpha(160),
                      size: 22,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Master service control card with a large toggle.
class _ServiceControlCard extends StatelessWidget {
  const _ServiceControlCard({
    required this.isActive,
    required this.isEnabled,
    required this.isToggling,
    required this.onToggle,
  });

  final bool isActive;
  final bool isEnabled;
  final bool isToggling;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFF6C63FF);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? activeColor.withAlpha(120)
              : const Color(0xFF2A2A2A),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive
                    ? activeColor.withAlpha(40)
                    : const Color(0xFF252525),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isActive ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: isActive ? activeColor : const Color(0xFF555555),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive
                        ? AppLocalizations.of(context)!.serviceControlActiveTitle
                        : AppLocalizations.of(context)!.serviceControlInactiveTitle,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : const Color(0xFF555555),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isEnabled
                        ? (isActive
                            ? AppLocalizations.of(context)!.serviceControlActiveDesc
                            : AppLocalizations.of(context)!.serviceControlInactiveDesc)
                        : AppLocalizations.of(context)!.serviceControlDisabledDesc,
                    style: const TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            isToggling
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: activeColor,
                    ),
                  )
                : Switch(
                    value: isActive,
                    onChanged: isEnabled ? onToggle : null,
                    activeThumbColor: activeColor,
                    activeTrackColor: activeColor.withAlpha(80),
                    inactiveThumbColor: const Color(0xFF444444),
                    inactiveTrackColor: const Color(0xFF2A2A2A),
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Navigation card that pushes a new route on tap.
class _NavigationCard extends StatelessWidget {
  const _NavigationCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: const Color(0xFF6C63FF).withAlpha(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.apps_rounded,
                  color: Color(0xFF6C63FF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF444444),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
