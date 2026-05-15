import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppRadius {
  const AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 32;
  static const double sheet = 34;
  static const double pill = 999;
}

class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppDurations {
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
}

class AppCurves {
  const AppCurves._();

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
  static const Curve bounce = Curves.easeOutBack;
}

class AppShadows {
  const AppShadows._();

  static List<BoxShadow> soft({Color? color}) {
    return <BoxShadow>[
      BoxShadow(
        color: (color ?? AppColors.black).withValues(alpha: 0.24),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> blueGlow() {
    return <BoxShadow>[
      BoxShadow(
        color: AppColors.blue.withValues(alpha: 0.28),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ];
  }
}

class AppInsets {
  const AppInsets._();

  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 10, 16, 24);
  static const EdgeInsets card = EdgeInsets.all(14);
  static const EdgeInsets cardLarge = EdgeInsets.all(18);
  static const EdgeInsets button = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );
}
