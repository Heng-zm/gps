import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/settings_service.dart';
import 'screens/tracking_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  // 1. Core initialization
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Load persisted user settings before the app starts
  // This ensures Units (KM/MI) and Screen-Wake settings are ready immediately.
  try {
    await SettingsService.instance.load();
  } catch (e) {
    debugPrint('Critical Error: Failed to load settings: $e');
  }

  // 3. Lock orientation to portrait for a consistent GPS dashboard experience
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 4. Configure System UI (Status Bar & Navigation Bar) for OLED Dark Mode
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark, // iOS
    statusBarIconBrightness: Brightness.light, // Android
    systemNavigationBarColor: const Color(0xFF0D0D0D),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const GpsTrackerPro());
}

class GpsTrackerPro extends StatelessWidget {
  const GpsTrackerPro({super.key});

  @override
  Widget build(BuildContext context) {
    // We use CupertinoApp for the high-end iOS aesthetic, but add
    // Material support via delegates for the AI and Chart components.
    return CupertinoApp(
      title: 'GPS Tracker Pro',
      debugShowCheckedModeBanner: false,

      // ── THE FIX: LOCALIZATION DELEGATES ──────────────────────────────────
      // Required to use Material Icons and Modal Sheets inside CupertinoApp
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US')],
      // ───────────────────────────────────────────────────────────────────

      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: Color(0xFF4ECDC4), // Global Teal Accent
        primaryContrastingColor: Colors.white,
        scaffoldBackgroundColor: Color(0xFF0D0D0D), // OLED Black
        barBackgroundColor: Color(0xFF111111),
        textTheme: CupertinoTextThemeData(
          primaryColor: Color(0xFF4ECDC4),
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Screens are marked const for performance
  static const List<Widget> _tabs = [
    TrackingScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      // Persistent Bottom Navigation Bar
      tabBar: CupertinoTabBar(
        backgroundColor: const Color(0xFF0D0D0D).withValues(alpha: 0.95),
        activeColor: const Color(0xFF4ECDC4),
        inactiveColor: const Color(0xFF555555),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.speedometer),
            activeIcon:
                Icon(CupertinoIcons.speedometer, color: Color(0xFF4ECDC4)),
            label: 'TRACK',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.clock_fill),
            label: 'HISTORY',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings_solid),
            label: 'SETTINGS',
          ),
        ],
      ),
      // tabBuilder handles the lazy-loading of pages
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) => _tabs[index],
        );
      },
    );
  }
}
