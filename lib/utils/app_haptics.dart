import 'package:flutter/services.dart';

class AppHaptics {
  const AppHaptics._();

  static Future<void> light() => HapticFeedback.lightImpact();

  static Future<void> medium() => HapticFeedback.mediumImpact();

  static Future<void> heavy() => HapticFeedback.heavyImpact();

  static Future<void> select() => HapticFeedback.selectionClick();
}
