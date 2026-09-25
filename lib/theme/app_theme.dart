import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Apple Human Interface Guidelines (HIG) Dark Mode design tokens and colors.
class AppColors {
  const AppColors._();

  // ── Apple System Backgrounds ──────────────────────────────────────────────
  /// Primary background: Pure black for OLED screens
  static const Color black = Color(0xFF000000);
  static const Color background = Color(0xFF000000);

  /// Secondary system background (grouped tables, cards, modal sheets)
  static const Color surface = Color(0xFF1C1C1E);
  static const Color card = Color(0xFF1C1C1E);

  /// Tertiary system background (nested controls, search fields, insets)
  static const Color elevated = Color(0xFF2C2C2E);
  static const Color border = Color(0x38545458);
  static const Color separator = Color(0x38545458);
  static const Color opaqueSeparator = Color(0xFF38383A);

  // ── Apple System Text & Label Hierarchies ─────────────────────────────────
  static const Color label = Color(0xFFFFFFFF);
  static const Color secondaryLabel = Color(0x99EBEBF5);
  static const Color tertiaryLabel = Color(0x4DEBEBF5);
  static const Color quaternaryLabel = Color(0x29EBEBF5);

  static const Color white = Color(0xFFFFFFFF);
  static const Color white90 = Color(0xE6FFFFFF);
  static const Color white70 = Color(0x99EBEBF5);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white38 = Color(0x61FFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);

  // ── Apple System Accent Colors (Dark Mode) ────────────────────────────────
  /// Apple System Blue (Dark)
  static const Color blue = Color(0xFF0A84FF);
  static const Color blueSoft = Color(0xFF64D2FF);
  static const Color blueDeep = Color(0xFF0040DD);
  static const Color blueGlow = Color(0x660A84FF);

  /// Apple System Green (Dark)
  static const Color green = Color(0xFF30D158);

  /// Apple System Red (Dark)
  static const Color red = Color(0xFFFF453A);

  /// Apple System Orange (Dark)
  static const Color orange = Color(0xFFFF9F0A);

  /// Apple System Yellow / Gold (Dark)
  static const Color yellow = Color(0xFFFFD60A);
  static const Color gold = Color(0xFFFFD60A);

  /// Apple System Teal / Cyan (Dark)
  static const Color cyan = Color(0xFF64D2FF);

  /// Apple System Indigo (Dark)
  static const Color indigo = Color(0xFF5E5CE6);

  static const Color warning = Color(0xFFFF9F0A);

  // ── Apple Glass & Button Gradients ────────────────────────────────────────
  static const LinearGradient blueGlassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0x260A84FF), Color(0x0DFFFFFF)],
  );

  static const LinearGradient blueButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF007AFF), Color(0xFF0A84FF)],
  );

  static const LinearGradient goldGlassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0x26FFD60A), Color(0x0DFFFFFF)],
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    );

    return ThemeData(
      platform: TargetPlatform.iOS,
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      cardColor: AppColors.card,
      dividerColor: AppColors.separator,
      dividerTheme: const DividerThemeData(
        color: AppColors.separator,
        thickness: 0.5,
        space: 0.5,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      fontFamilyFallback: const <String>[
        '.AppleSystemUIFont',
        'SF Pro Display',
        'SF Pro Text',
        '-apple-system',
        'BlinkMacSystemFont',
        'Helvetica Neue',
        'Arial',
      ],
      cupertinoOverrideTheme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.blue,
        scaffoldBackgroundColor: AppColors.background,
        barBackgroundColor: Color(0xCC1C1C1E),
        textTheme: CupertinoTextThemeData(
          primaryColor: AppColors.blue,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: const TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.separator, width: 0.5),
        ),
      ),
    );
  }
}
