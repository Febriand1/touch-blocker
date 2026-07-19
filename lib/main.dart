import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/dashboard/screens/home_screen.dart';
import 'package:touch_blocker/l10n/app_localizations.dart';
import 'core/channels/lock_method_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const TouchBlockerApp());
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

class TouchBlockerApp extends StatefulWidget {
  const TouchBlockerApp({super.key});

  @override
  State<TouchBlockerApp> createState() => _TouchBlockerAppState();
}

class _TouchBlockerAppState extends State<TouchBlockerApp> {
  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final modeStr = await LockMethodChannel.getThemeMode();
    switch (modeStr) {
      case 'dark':
        themeNotifier.value = ThemeMode.dark;
        break;
      case 'light':
        themeNotifier.value = ThemeMode.light;
        break;
      default:
        themeNotifier.value = ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Touch Blocker',
          themeMode: currentMode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6C63FF),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            fontFamily: 'GoogleSans',
            scaffoldBackgroundColor: const Color(0xFFFFFFFF),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6C63FF),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            fontFamily: 'GoogleSans',
            scaffoldBackgroundColor: const Color(0xFF0F0F0F),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}
