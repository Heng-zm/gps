import 'package:flutter/cupertino.dart';

/// Visual style used by AppLocationPuck and the settings/history replay UI.
enum LocationPuckStyle {
  classicBlue,
  neonBlue,
  compass,
  vehicle,
  minimalDot,
  earner,
  navigator,
}

extension LocationPuckStyleX on LocationPuckStyle {
  String get label {
    switch (this) {
      case LocationPuckStyle.classicBlue:
        return 'Classic';
      case LocationPuckStyle.neonBlue:
        return 'Neon';
      case LocationPuckStyle.compass:
        return 'Compass';
      case LocationPuckStyle.vehicle:
        return 'Vehicle';
      case LocationPuckStyle.minimalDot:
        return 'Minimal';
      case LocationPuckStyle.earner:
        return 'Earner';
      case LocationPuckStyle.navigator:
        return 'Navigator';
    }
  }

  String get shortLabel => label;

  String get description {
    switch (this) {
      case LocationPuckStyle.classicBlue:
        return 'Default GPS puck with a clean blue center.';
      case LocationPuckStyle.neonBlue:
        return 'Bright glowing puck for dark maps.';
      case LocationPuckStyle.compass:
        return 'Puck with heading cone for navigation.';
      case LocationPuckStyle.vehicle:
        return 'Automotive style for trip display.';
      case LocationPuckStyle.minimalDot:
        return 'Small low-profile dot.';
      case LocationPuckStyle.earner:
        return 'Premium earner style with gold accent.';
      case LocationPuckStyle.navigator:
        return 'Sharp arrow style for active navigation.';
    }
  }

  IconData get icon {
    switch (this) {
      case LocationPuckStyle.classicBlue:
        return CupertinoIcons.location_fill;
      case LocationPuckStyle.neonBlue:
        return CupertinoIcons.sparkles;
      case LocationPuckStyle.compass:
        return CupertinoIcons.compass_fill;
      case LocationPuckStyle.vehicle:
        return CupertinoIcons.car_detailed;
      case LocationPuckStyle.minimalDot:
        return CupertinoIcons.circle_fill;
      case LocationPuckStyle.earner:
        return CupertinoIcons.money_dollar_circle_fill;
      case LocationPuckStyle.navigator:
        return CupertinoIcons.location_north_fill;
    }
  }

  Color get accentColor {
    switch (this) {
      case LocationPuckStyle.classicBlue:
        return const Color(0xFF3B82F6);
      case LocationPuckStyle.neonBlue:
        return const Color(0xFF60A5FA);
      case LocationPuckStyle.compass:
        return const Color(0xFF38BDF8);
      case LocationPuckStyle.vehicle:
        return const Color(0xFF818CF8);
      case LocationPuckStyle.minimalDot:
        return const Color(0xFFFFFFFF);
      case LocationPuckStyle.earner:
        return const Color(0xFFFBBF24);
      case LocationPuckStyle.navigator:
        return const Color(0xFF22D3EE);
    }
  }

  Color get centerColor {
    switch (this) {
      case LocationPuckStyle.earner:
        return const Color(0xFF111827);
      case LocationPuckStyle.minimalDot:
        return const Color(0xFFFFFFFF);
      case LocationPuckStyle.navigator:
        return const Color(0xFF0F172A);
      default:
        return const Color(0xFF2563EB);
    }
  }

  bool get showsHeadingCone {
    switch (this) {
      case LocationPuckStyle.compass:
      case LocationPuckStyle.vehicle:
      case LocationPuckStyle.earner:
      case LocationPuckStyle.navigator:
        return true;
      default:
        return false;
    }
  }

  bool get showsSpeedBadge {
    switch (this) {
      case LocationPuckStyle.vehicle:
      case LocationPuckStyle.earner:
      case LocationPuckStyle.navigator:
        return true;
      default:
        return false;
    }
  }

  double get markerSize {
    switch (this) {
      case LocationPuckStyle.minimalDot:
        return 44;
      case LocationPuckStyle.vehicle:
      case LocationPuckStyle.earner:
      case LocationPuckStyle.navigator:
        return 86;
      default:
        return 76;
    }
  }

  /// Stable value used by SharedPreferences.
  String get storageKey => name;

  /// Safe parser for settings persistence.
  static LocationPuckStyle fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return LocationPuckStyle.classicBlue;

    for (final LocationPuckStyle style in LocationPuckStyle.values) {
      if (style.storageKey.toLowerCase() == normalized ||
          style.label.toLowerCase() == normalized ||
          style.shortLabel.toLowerCase() == normalized) {
        return style;
      }
    }

    return LocationPuckStyle.classicBlue;
  }
}
