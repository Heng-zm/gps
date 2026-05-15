import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../services/settings_service.dart';

/// Runtime engine selection for Mapbox rendering.
///
/// - [auto]: Native Mapbox on mobile, Flutter/web fallback on web.
/// - [native]: Force native Mapbox when supported.
/// - [webFallback]: Force tile fallback renderer.
enum MapboxRuntimeMode {
  auto,
  native,
  webFallback,
}

extension MapboxRuntimeModeX on MapboxRuntimeMode {
  String get label {
    switch (this) {
      case MapboxRuntimeMode.auto:
        return 'AUTO';
      case MapboxRuntimeMode.native:
        return 'NATIVE';
      case MapboxRuntimeMode.webFallback:
        return 'WEB';
    }
  }

  String get description {
    switch (this) {
      case MapboxRuntimeMode.auto:
        return 'Native Mapbox on mobile, fallback on web';
      case MapboxRuntimeMode.native:
        return 'Force native Mapbox where supported';
      case MapboxRuntimeMode.webFallback:
        return 'Force flutter_map fallback';
    }
  }

  IconData get icon {
    switch (this) {
      case MapboxRuntimeMode.auto:
        return CupertinoIcons.sparkles;
      case MapboxRuntimeMode.native:
        return CupertinoIcons.device_phone_portrait;
      case MapboxRuntimeMode.webFallback:
        return CupertinoIcons.globe;
    }
  }

  MapboxRuntimeMode get next {
    switch (this) {
      case MapboxRuntimeMode.auto:
        return MapboxRuntimeMode.native;
      case MapboxRuntimeMode.native:
        return MapboxRuntimeMode.webFallback;
      case MapboxRuntimeMode.webFallback:
        return MapboxRuntimeMode.auto;
    }
  }
}

/// Mapbox Standard style light presets.
///
/// These are used with:
/// `map.style.setStyleImportConfigProperty('basemap', 'lightPreset', value)`.
enum MapboxStandardPreset {
  day,
  dusk,
  dawn,
  night,
}

extension MapboxStandardPresetX on MapboxStandardPreset {
  String get label {
    switch (this) {
      case MapboxStandardPreset.day:
        return 'DAY';
      case MapboxStandardPreset.dusk:
        return 'DUSK';
      case MapboxStandardPreset.dawn:
        return 'DAWN';
      case MapboxStandardPreset.night:
        return 'NIGHT';
    }
  }

  String get mapboxValue {
    switch (this) {
      case MapboxStandardPreset.day:
        return 'day';
      case MapboxStandardPreset.dusk:
        return 'dusk';
      case MapboxStandardPreset.dawn:
        return 'dawn';
      case MapboxStandardPreset.night:
        return 'night';
    }
  }

  IconData get icon {
    switch (this) {
      case MapboxStandardPreset.day:
        return CupertinoIcons.sun_max_fill;
      case MapboxStandardPreset.dusk:
        return CupertinoIcons.sunset_fill;
      case MapboxStandardPreset.dawn:
        return CupertinoIcons.sunrise_fill;
      case MapboxStandardPreset.night:
        return CupertinoIcons.moon_stars_fill;
    }
  }

  MapboxStandardPreset get next {
    switch (this) {
      case MapboxStandardPreset.day:
        return MapboxStandardPreset.dusk;
      case MapboxStandardPreset.dusk:
        return MapboxStandardPreset.dawn;
      case MapboxStandardPreset.dawn:
        return MapboxStandardPreset.night;
      case MapboxStandardPreset.night:
        return MapboxStandardPreset.day;
    }
  }
}

/// Mapbox Directions API travel profiles.
enum DirectionsProfile {
  drivingTraffic,
  driving,
  walking,
  cycling,
}

extension DirectionsProfileX on DirectionsProfile {
  String get label {
    switch (this) {
      case DirectionsProfile.drivingTraffic:
        return 'DRIVE+TRAFFIC';
      case DirectionsProfile.driving:
        return 'DRIVING';
      case DirectionsProfile.walking:
        return 'WALKING';
      case DirectionsProfile.cycling:
        return 'CYCLING';
    }
  }

  String get shortLabel {
    switch (this) {
      case DirectionsProfile.drivingTraffic:
        return 'Drive+Traffic';
      case DirectionsProfile.driving:
        return 'Driving';
      case DirectionsProfile.walking:
        return 'Walking';
      case DirectionsProfile.cycling:
        return 'Cycling';
    }
  }

  String get apiProfile {
    switch (this) {
      case DirectionsProfile.drivingTraffic:
        return 'mapbox/driving-traffic';
      case DirectionsProfile.driving:
        return 'mapbox/driving';
      case DirectionsProfile.walking:
        return 'mapbox/walking';
      case DirectionsProfile.cycling:
        return 'mapbox/cycling';
    }
  }

  IconData get icon {
    switch (this) {
      case DirectionsProfile.drivingTraffic:
      case DirectionsProfile.driving:
        return CupertinoIcons.car_detailed;
      case DirectionsProfile.walking:
        return CupertinoIcons.person_fill;
      case DirectionsProfile.cycling:
        return Icons.directions_bike_rounded;
    }
  }

  DirectionsProfile get next {
    switch (this) {
      case DirectionsProfile.drivingTraffic:
        return DirectionsProfile.driving;
      case DirectionsProfile.driving:
        return DirectionsProfile.walking;
      case DirectionsProfile.walking:
        return DirectionsProfile.cycling;
      case DirectionsProfile.cycling:
        return DirectionsProfile.drivingTraffic;
    }
  }
}

/// A planned route returned from Mapbox Directions API.
///
/// Keep this model UI-safe and immutable. It can be shared by:
/// - tracking screen
/// - map screen
/// - route planner sheet
class PlannedRoute {
  const PlannedRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.profile,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final DirectionsProfile profile;

  bool get isValid => points.length >= 2;

  double get distanceKm => distanceMeters / 1000.0;

  double get distanceMiles => distanceMeters / 1609.344;

  String get distanceLabelMetric {
    final double km = distanceKm;
    if (!km.isFinite || km <= 0.0) return '0 m';
    if (km >= 1.0) return '${km.toStringAsFixed(2)} km';
    return '${(km * 1000).toStringAsFixed(0)} m';
  }

  String distanceLabel(SettingsService settings) {
    final double miles = distanceMiles;
    final double displayDistance = settings.toDisplayDistance(
      miles.isFinite && miles >= 0.0 ? miles : 0.0,
    );
    return '${displayDistance.toStringAsFixed(1)} ${settings.distanceUnit}';
  }

  String durationLabel() {
    final int total = durationSeconds.isFinite
        ? durationSeconds.round().clamp(0, 1 << 31)
        : 0;
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }

    return '${minutes}m';
  }

  PlannedRoute copyWith({
    List<LatLng>? points,
    double? distanceMeters,
    double? durationSeconds,
    DirectionsProfile? profile,
  }) {
    return PlannedRoute(
      points: points ?? this.points,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      profile: profile ?? this.profile,
    );
  }
}

/// Geocoding result from Mapbox Search / Geocoding API.
class MapboxPlaceResult {
  const MapboxPlaceResult({
    required this.name,
    required this.address,
    required this.position,
  });

  final String name;
  final String address;
  final LatLng position;

  bool get isValid => isValidLatLng(position);
}

/// Helper for the shared route planner widget.
/// Keeps the widget generic-friendly without duplicating summary formatting.
class PlannedRouteSummary {
  const PlannedRouteSummary({
    required this.distanceLabel,
    required this.durationLabel,
    required this.profileLabel,
  });

  factory PlannedRouteSummary.fromRoute(
    PlannedRoute route, {
    SettingsService? settings,
  }) {
    return PlannedRouteSummary(
      distanceLabel: settings == null
          ? route.distanceLabelMetric
          : route.distanceLabel(settings),
      durationLabel: route.durationLabel(),
      profileLabel: route.profile.label,
    );
  }

  final String distanceLabel;
  final String durationLabel;
  final String profileLabel;
}

/// Convert shared enums into route planner options.
///
/// Use these with `RoutePlannerSheet`.
class MapboxRoutePlannerOptions {
  const MapboxRoutePlannerOptions._();

  static List<T> immutable<T>(Iterable<T> items) {
    return List<T>.unmodifiable(items);
  }

  /// Use inside screens after importing `route_planner_sheet.dart`.
  ///
  /// Example:
  /// ```dart
  /// profileOptions: MapboxRoutePlannerOptions.profileOptions,
  /// ```
  ///
  /// This getter is intentionally dynamic-free at runtime, but kept here as
  /// helper data for screens that use the shared route planner widget.
  static List<MapboxRuntimeMode> get runtimeModes {
    return const <MapboxRuntimeMode>[
      MapboxRuntimeMode.auto,
      MapboxRuntimeMode.native,
      MapboxRuntimeMode.webFallback,
    ];
  }

  static List<MapboxStandardPreset> get standardPresets {
    return const <MapboxStandardPreset>[
      MapboxStandardPreset.day,
      MapboxStandardPreset.dusk,
      MapboxStandardPreset.dawn,
      MapboxStandardPreset.night,
    ];
  }

  static List<DirectionsProfile> get directionProfiles {
    return const <DirectionsProfile>[
      DirectionsProfile.drivingTraffic,
      DirectionsProfile.driving,
      DirectionsProfile.walking,
      DirectionsProfile.cycling,
    ];
  }
}

/// Mapbox style helper.
///
/// Uses Mapbox Standard by default and Standard Satellite for satellite mode.
String mapboxStandardStyleUri({
  required bool satellite,
}) {
  return satellite ? mb.MapboxStyles.STANDARD_SATELLITE : mb.MapboxStyles.STANDARD;
}

/// Coordinate validation shared by route planner and map screens.
bool isValidLatLng(LatLng point) {
  return point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= -90.0 &&
      point.latitude <= 90.0 &&
      point.longitude >= -180.0 &&
      point.longitude <= 180.0;
}

/// Parses user-pasted coordinates like:
/// - `11.5564, 104.9282`
/// - `11.5564 104.9282`
LatLng? tryParseLatLng(String input) {
  final RegExpMatch? match = RegExp(
    r'^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$',
  ).firstMatch(input);

  if (match == null) return null;

  final double? lat = double.tryParse(match.group(1)!);
  final double? lng = double.tryParse(match.group(2)!);

  if (lat == null || lng == null) return null;

  final LatLng point = LatLng(lat, lng);
  return isValidLatLng(point) ? point : null;
}
