import 'package:flutter/material.dart';

enum HudColorTheme {
  neonCyan(Color(0xFF00F0FF), 'Neon Cyan'),
  electricLime(Color(0xFF00FF66), 'Electric Lime'),
  amberHud(Color(0xFFFFB300), 'Amber Glow'),
  stealthRed(Color(0xFFFF3B30), 'Stealth Red');

  const HudColorTheme(this.color, this.label);
  final Color color;
  final String label;
}

class HolographicHudService {
  HolographicHudService._();
  static final HolographicHudService instance = HolographicHudService._();

  final ValueNotifier<bool> isMirroredN = ValueNotifier<bool>(true);
  final ValueNotifier<HudColorTheme> themeN =
      ValueNotifier<HudColorTheme>(HudColorTheme.neonCyan);
  final ValueNotifier<bool> showGlosaAdvisoryN = ValueNotifier<bool>(true);
  final ValueNotifier<bool> showVectorGforceN = ValueNotifier<bool>(true);

  void toggleMirror() {
    isMirroredN.value = !isMirroredN.value;
  }

  void cycleTheme() {
    final List<HudColorTheme> values = HudColorTheme.values;
    final int next = (values.indexOf(themeN.value) + 1) % values.length;
    themeN.value = values[next];
  }
}
