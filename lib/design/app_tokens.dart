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

  static BorderRadius get xsRadius => BorderRadius.circular(xs);
  static BorderRadius get smRadius => BorderRadius.circular(sm);
  static BorderRadius get mdRadius => BorderRadius.circular(md);
  static BorderRadius get lgRadius => BorderRadius.circular(lg);
  static BorderRadius get xlRadius => BorderRadius.circular(xl);
  static BorderRadius get sheetRadius => BorderRadius.circular(sheet);
  static BorderRadius get pillRadius => BorderRadius.circular(pill);
}

class AppSpacing {
  const AppSpacing._();

  static const double zero = 0;
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
}

class AppDurations {
  const AppDurations._();

  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration slower = Duration(milliseconds: 520);
}

class AppCurves {
  const AppCurves._();

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
  static const Curve bounce = Curves.easeOutBack;
  static const Curve smooth = Curves.fastEaseInToSlowEaseOut;
}

class AppOpacity {
  const AppOpacity._();

  static const double disabled = 0.45;
  static const double pressed = 0.72;
  static const double muted = 0.68;
  static const double overlay = 0.12;
  static const double divider = 0.10;
}

class AppShadows {
  const AppShadows._();

  static List<BoxShadow> soft({Color? color}) {
    return <BoxShadow>[
      BoxShadow(
        color: (color ?? AppColors.black).withValues(alpha: 0.18),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> medium({Color? color}) {
    return <BoxShadow>[
      BoxShadow(
        color: (color ?? AppColors.black).withValues(alpha: 0.22),
        blurRadius: 26,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> floating({Color? color}) {
    return <BoxShadow>[
      BoxShadow(
        color: (color ?? AppColors.black).withValues(alpha: 0.20),
        blurRadius: 34,
        offset: const Offset(0, 18),
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

  static List<BoxShadow> blueStrongGlow() {
    return <BoxShadow>[
      BoxShadow(
        color: AppColors.blue.withValues(alpha: 0.38),
        blurRadius: 30,
        offset: const Offset(0, 14),
      ),
    ];
  }
}

class AppInsets {
  const AppInsets._();

  static const EdgeInsets zero = EdgeInsets.zero;

  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 10, 16, 24);
  static const EdgeInsets pageLarge = EdgeInsets.fromLTRB(20, 14, 20, 28);

  static const EdgeInsets card = EdgeInsets.all(14);
  static const EdgeInsets cardLarge = EdgeInsets.all(18);

  static const EdgeInsets button = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );

  static const EdgeInsets buttonCompact = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );

  static const EdgeInsets chip = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  static const EdgeInsets sheet = EdgeInsets.fromLTRB(18, 16, 18, 24);
}

class AppSizes {
  const AppSizes._();

  static const double iconXs = 14;
  static const double iconSm = 18;
  static const double iconMd = 22;
  static const double iconLg = 28;

  static const double minTapTarget = 44;
  static const double buttonHeight = 50;
  static const double inputHeight = 52;
  static const double bottomNavHeight = 68;
}
