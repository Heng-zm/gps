import 'package:flutter/material.dart';

/// Shared black / white / blue app theme.
///
/// Keep all high-level app colors here so screens and widgets do not duplicate
/// theme constants. This makes future rebranding safer.
class AppColors {
  const AppColors._();

  static const Color black = Color(0xFF000000);
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF070A12);
  static const Color card = Color(0xFF0B1220);
  static const Color elevated = Color(0xFF101522);
  static const Color border = Color(0xFF1E293B);

  static const Color white = Color(0xFFFFFFFF);
  static const Color white90 = Color(0xE6FFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white38 = Color(0x61FFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);

  static const Color blue = Color(0xFF2563EB);
  static const Color blueSoft = Color(0xFF93C5FD);
  static const Color blueDeep = Color(0xFF1E3A8A);
  static const Color blueGlow = Color(0x662563EB);

  static const Color green = Color(0xFF27AE60);
  static const Color red = Color(0xFFE74C3C);
  static const Color warning = Color(0xFF93C5FD);

  static const LinearGradient blueGlassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0x1A60A5FA), Color(0x0DFFFFFF)],
  );

  static const LinearGradient blueButtonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF1D4ED8), Color(0xFF3B82F6)],
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
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      cardColor: AppColors.card,
      dividerColor: AppColors.border,
      splashColor: AppColors.blue.withValues(alpha: 0.10),
      highlightColor: AppColors.blue.withValues(alpha: 0.08),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.white,
        elevation: 0,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.card,
        contentTextStyle: const TextStyle(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
