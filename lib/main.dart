import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/dashboard/screens/home_screen.dart';
import 'package:touch_blocker/l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const TouchBlockerApp());
}

class TouchBlockerApp extends StatelessWidget {
  const TouchBlockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Touch Blocker',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'GoogleSans',
      ),
      home: const HomeScreen(),
    );
  }
}
