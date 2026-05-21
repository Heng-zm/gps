import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Visual style used by AppLocationPuck and the settings/history replay UI.
///
/// Keep enum names stable because [storageKey] uses [name] for persistence.
/// New styles should be added at the end to avoid changing existing saved values.
enum LocationPuckStyle {
  classicBlue(
    label: 'Classic',
    description: 'Default GPS puck with a clean blue center.',
    icon: CupertinoIcons.location_fill,
    accentColor: Color(0xFF3B82F6),
    centerColor: Color(0xFF2563EB),
    markerSize: 76,
  ),

  neonBlue(
    label: 'Neon',
    description: 'Bright glowing puck for dark maps.',
    icon: CupertinoIcons.sparkles,
    accentColor: Color(0xFF60A5FA),
    centerColor: Color(0xFF2563EB),
    usesPulseRing: true,
    markerSize: 76,
  ),

  compass(
    label: 'Compass',
    description: 'Puck with heading cone for navigation.',
    icon: CupertinoIcons.compass_fill,
    accentColor: Color(0xFF38BDF8),
    centerColor: Color(0xFF2563EB),
    showsHeadingCone: true,
    markerSize: 76,
  ),

  vehicle(
    label: 'Vehicle',
    description: 'Automotive style for trip display.',
    icon: CupertinoIcons.car_detailed,
    accentColor: Color(0xFF818CF8),
    centerColor: Color(0xFF2563EB),
    showsHeadingCone: true,
    showsSpeedBadge: true,
    usesVehicleBody: true,
    markerSize: 86,
  ),

  minimalDot(
    label: 'Minimal',
    description: 'Small low-profile dot.',
    icon: CupertinoIcons.circle_fill,
    accentColor: Color(0xFFFFFFFF),
    centerColor: Color(0xFFFFFFFF),
    markerSize: 44,
  ),

  earner(
    label: 'Earner',
    description: 'Premium earner style with gold accent.',
    icon: CupertinoIcons.money_dollar_circle_fill,
    accentColor: Color(0xFFFBBF24),
    centerColor: Color(0xFF111827),
    showsHeadingCone: true,
    showsSpeedBadge: true,
    markerSize: 86,
  ),

  navigator(
    label: 'Navigator',
    description: 'Sharp arrow style for active navigation.',
    icon: CupertinoIcons.location_north_fill,
    accentColor: Color(0xFF22D3EE),
    centerColor: Color(0xFF0F172A),
    showsHeadingCone: true,
    showsSpeedBadge: true,
    usesArrowBody: true,
    usesPulseRing: true,
    markerSize: 86,
  ),

  pulseHalo(
    label: 'Pulse Halo',
    shortLabel: 'Pulse',
    description: 'Clean halo puck with strong visibility.',
    icon: CupertinoIcons.scope,
    accentColor: Color(0xFF34D399),
    centerColor: Color(0xFF052E2B),
    usesPulseRing: true,
    markerSize: 78,
  ),

  stealth(
    label: 'Stealth',
    description: 'Low-glare dark puck for night and satellite maps.',
    icon: CupertinoIcons.moon_stars_fill,
    accentColor: Color(0xFFA3A3A3),
    centerColor: Color(0xFF0F172A),
    markerSize: 68,
  ),

  rider(
    label: 'Rider',
    description: 'Rider style for motorcycle and delivery trips.',
    icon: Icons.motorcycle,
    accentColor: Color(0xFFF97316),
    centerColor: Color(0xFF431407),
    showsHeadingCone: true,
    showsSpeedBadge: true,
    usesVehicleBody: true,
    markerSize: 86,
  ),

  sportArrow(
    label: 'Sport',
    description: 'Fast arrow style for high-speed replay.',
    icon: CupertinoIcons.bolt_fill,
    accentColor: Color(0xFFFF3B30),
    centerColor: Color(0xFF0F172A),
    showsHeadingCone: true,
    showsSpeedBadge: true,
    usesArrowBody: true,
    usesPulseRing: true,
    markerSize: 86,
  );

  const LocationPuckStyle({
    required this.label,
    String? shortLabel,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.centerColor,
    this.showsHeadingCone = false,
    this.showsSpeedBadge = false,
    this.usesArrowBody = false,
    this.usesVehicleBody = false,
    this.usesPulseRing = false,
    required this.markerSize,
  }) : shortLabel = shortLabel ?? label;

  final String label;
  final String shortLabel;
  final String description;
  final IconData icon;
  final Color accentColor;
  final Color centerColor;
  final bool showsHeadingCone;
  final bool showsSpeedBadge;
  final bool usesArrowBody;
  final bool usesVehicleBody;
  final bool usesPulseRing;
  final double markerSize;

  String get storageKey => name;

  bool get isCompact => markerSize <= 52;

  static const Map<String, LocationPuckStyle> aliases =
      <String, LocationPuckStyle>{
    'blue': LocationPuckStyle.classicBlue,
    'classic': LocationPuckStyle.classicBlue,
    'default': LocationPuckStyle.classicBlue,
    'neon': LocationPuckStyle.neonBlue,
    'car': LocationPuckStyle.vehicle,
    'auto': LocationPuckStyle.vehicle,
    'minimal': LocationPuckStyle.minimalDot,
    'dot': LocationPuckStyle.minimalDot,
    'gold': LocationPuckStyle.earner,
    'premium': LocationPuckStyle.earner,
    'nav': LocationPuckStyle.navigator,
    'arrow': LocationPuckStyle.navigator,
    'pulse': LocationPuckStyle.pulseHalo,
    'halo': LocationPuckStyle.pulseHalo,
    'night': LocationPuckStyle.stealth,
    'dark': LocationPuckStyle.stealth,
    'motor': LocationPuckStyle.rider,
    'motorcycle': LocationPuckStyle.rider,
    'delivery': LocationPuckStyle.rider,
    'fast': LocationPuckStyle.sportArrow,
    'sport': LocationPuckStyle.sportArrow,
  };


  /// Styles shown by default in picker UIs. Kept separate from [values] so
  /// future experimental styles can be hidden without breaking persistence.
  static const List<LocationPuckStyle> selectorStyles = <LocationPuckStyle>[
    LocationPuckStyle.classicBlue,
    LocationPuckStyle.neonBlue,
    LocationPuckStyle.compass,
    LocationPuckStyle.vehicle,
    LocationPuckStyle.navigator,
    LocationPuckStyle.earner,
    LocationPuckStyle.pulseHalo,
    LocationPuckStyle.stealth,
    LocationPuckStyle.rider,
    LocationPuckStyle.sportArrow,
    LocationPuckStyle.minimalDot,
  ];

  static LocationPuckStyle fromIndex(int index) {
    if (index < 0 || index >= LocationPuckStyle.values.length) {
      return LocationPuckStyle.classicBlue;
    }
    return LocationPuckStyle.values[index];
  }

  static LocationPuckStyle fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return LocationPuckStyle.classicBlue;

    final LocationPuckStyle? alias = aliases[normalized];
    if (alias != null) return alias;

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

extension LocationPuckStyleUxX on LocationPuckStyle {
  /// Cycles through only user-facing styles, keeping hidden/experimental values safe.
  LocationPuckStyle get nextSelectorStyle {
    final List<LocationPuckStyle> styles = LocationPuckStyle.selectorStyles;
    final int index = styles.indexOf(this);
    if (index < 0 || styles.isEmpty) return LocationPuckStyle.classicBlue;
    return styles[(index + 1) % styles.length];
  }

  bool get isVehicleFocused => usesVehicleBody || this == LocationPuckStyle.rider;

  bool get isNavigationFocused =>
      showsHeadingCone || usesArrowBody || this == LocationPuckStyle.compass;

  bool get isHighVisibility =>
      usesPulseRing ||
      this == LocationPuckStyle.neonBlue ||
      this == LocationPuckStyle.navigator ||
      this == LocationPuckStyle.sportArrow;

  bool get recommendedForDarkMap {
    switch (this) {
      case LocationPuckStyle.neonBlue:
      case LocationPuckStyle.navigator:
      case LocationPuckStyle.pulseHalo:
      case LocationPuckStyle.sportArrow:
      case LocationPuckStyle.minimalDot:
        return true;
      default:
        return false;
    }
  }

  bool get recommendedForSatellite {
    switch (this) {
      case LocationPuckStyle.earner:
      case LocationPuckStyle.rider:
      case LocationPuckStyle.sportArrow:
      case LocationPuckStyle.pulseHalo:
        return true;
      default:
        return false;
    }
  }

  Color get readableTextColor {
    final double luminance = centerColor.computeLuminance();
    return luminance > 0.45 ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
  }

  String get uxBadge {
    if (isVehicleFocused) return 'Trip';
    if (isNavigationFocused) return 'Nav';
    if (isHighVisibility) return 'Visible';
    if (isCompact) return 'Clean';
    return 'GPS';
  }
}
