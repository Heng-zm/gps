import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../services/settings_service.dart';

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

  String get storageKey => name;

  static MapboxRuntimeMode fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    for (final MapboxRuntimeMode mode in MapboxRuntimeMode.values) {
      if (mode.storageKey.toLowerCase() == normalized ||
          mode.label.toLowerCase() == normalized) {
        return mode;
      }
    }
    if (normalized == 'fallback' || normalized == 'web_fallback') {
      return MapboxRuntimeMode.webFallback;
    }
    return MapboxRuntimeMode.auto;
  }
}

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

  String get storageKey => name;

  static MapboxStandardPreset fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    for (final MapboxStandardPreset preset in MapboxStandardPreset.values) {
      if (preset.storageKey.toLowerCase() == normalized ||
          preset.label.toLowerCase() == normalized ||
          preset.mapboxValue.toLowerCase() == normalized) {
        return preset;
      }
    }
    return MapboxStandardPreset.day;
  }
}

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

  String get storageKey => name;

  static DirectionsProfile fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    for (final DirectionsProfile profile in DirectionsProfile.values) {
      if (profile.storageKey.toLowerCase() == normalized ||
          profile.label.toLowerCase() == normalized ||
          profile.shortLabel.toLowerCase() == normalized ||
          profile.apiProfile.toLowerCase() == normalized) {
        return profile;
      }
    }
    switch (normalized) {
      case 'traffic':
      case 'driving-traffic':
      case 'drive+traffic':
        return DirectionsProfile.drivingTraffic;
      case 'walk':
        return DirectionsProfile.walking;
      case 'bike':
      case 'bicycle':
        return DirectionsProfile.cycling;
      case 'drive':
      case 'car':
      default:
        return DirectionsProfile.driving;
    }
  }
}

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

  double get safeDistanceMeters =>
      distanceMeters.isFinite && distanceMeters > 0 ? distanceMeters : 0.0;

  double get safeDurationSeconds =>
      durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 0.0;

  double get distanceKm => safeDistanceMeters / 1000.0;

  double get distanceMiles => safeDistanceMeters / 1609.344;

  String get distanceLabelMetric {
    final double km = distanceKm;
    if (!km.isFinite || km <= 0.0) return '0 m';
    if (km >= 1.0) return '${km.toStringAsFixed(2)} km';
    return '${(km * 1000).toStringAsFixed(0)} m';
  }

  String distanceLabel(SettingsService settings) {
    final double displayDistance = settings.toDisplayDistance(distanceMiles);
    return '${displayDistance.toStringAsFixed(1)} ${settings.distanceUnit}';
  }

  String durationLabel() {
    final int total = safeDurationSeconds.round().clamp(0, 1 << 31).toInt();
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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'points': points
          .where(isValidLatLng)
          .map((LatLng point) => <String, double>{
                'lat': point.latitude,
                'lng': point.longitude,
              })
          .toList(growable: false),
      'distanceMeters': safeDistanceMeters,
      'durationSeconds': safeDurationSeconds,
      'profile': profile.storageKey,
    };
  }

  static PlannedRoute? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
    final List<LatLng> parsedPoints = _parsePoints(json['points']);

    final PlannedRoute route = PlannedRoute(
      points: List<LatLng>.unmodifiable(parsedPoints),
      distanceMeters: _readDouble(json['distanceMeters'] ?? json['distance']),
      durationSeconds: _readDouble(json['durationSeconds'] ?? json['duration']),
      profile: DirectionsProfileX.fromStorageKey(json['profile']?.toString()),
    );

    return route.isValid ? route : null;
  }

  static List<LatLng> _parsePoints(Object? raw) {
    if (raw is! List) return const <LatLng>[];

    final List<LatLng> points = <LatLng>[];

    for (final Object? item in raw) {
      if (item is Map) {
        final LatLng point = LatLng(
          _readDouble(item['lat'] ?? item['latitude']),
          _readDouble(item['lng'] ?? item['lon'] ?? item['longitude']),
        );
        if (isValidLatLng(point)) points.add(point);
      } else if (item is List && item.length >= 2) {
        final LatLng point = LatLng(
          _readDouble(item[1]),
          _readDouble(item[0]),
        );
        if (isValidLatLng(point)) points.add(point);
      }
    }

    return points;
  }
}

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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'address': address,
      'lat': position.latitude,
      'lng': position.longitude,
    };
  }

  static MapboxPlaceResult? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    final LatLng point = LatLng(
      _readDouble(raw['lat'] ?? raw['latitude']),
      _readDouble(raw['lng'] ?? raw['lon'] ?? raw['longitude']),
    );

    if (!isValidLatLng(point)) return null;

    return MapboxPlaceResult(
      name: raw['name']?.toString() ?? 'Pinned location',
      address: raw['address']?.toString() ?? '',
      position: point,
    );
  }
}

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

class MapboxRoutePlannerOptions {
  const MapboxRoutePlannerOptions._();

  static List<T> immutable<T>(Iterable<T> items) {
    return List<T>.unmodifiable(items);
  }

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

String mapboxStandardStyleUri({
  required bool satellite,
}) {
  return satellite
      ? mb.MapboxStyles.STANDARD_SATELLITE
      : mb.MapboxStyles.STANDARD;
}

bool isValidLatLng(LatLng point) {
  return point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= -90.0 &&
      point.latitude <= 90.0 &&
      point.longitude >= -180.0 &&
      point.longitude <= 180.0;
}

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

double _readDouble(Object? value) {
  if (value is num) {
    final double parsed = value.toDouble();
    return parsed.isFinite ? parsed : 0.0;
  }

  if (value is String) {
    final double? parsed = double.tryParse(value.trim());
    return parsed != null && parsed.isFinite ? parsed : 0.0;
  }

  return 0.0;
}

extension DirectionsProfileUxX on DirectionsProfile {
  bool get isMotorized {
    switch (this) {
      case DirectionsProfile.drivingTraffic:
      case DirectionsProfile.driving:
        return true;
      case DirectionsProfile.walking:
      case DirectionsProfile.cycling:
        return false;
    }
  }

  bool get prefersTrafficAwareRouting => this == DirectionsProfile.drivingTraffic;

  String get uxHint {
    switch (this) {
      case DirectionsProfile.drivingTraffic:
        return 'Best for live traffic and city driving';
      case DirectionsProfile.driving:
        return 'Best for simple car routing';
      case DirectionsProfile.walking:
        return 'Best for short walking routes';
      case DirectionsProfile.cycling:
        return 'Best for bike-friendly routes';
    }
  }
}

extension PlannedRouteUxX on PlannedRoute {
  bool get hasUsefulMetrics => safeDistanceMeters > 0.0 || safeDurationSeconds > 0.0;

  double get averageSpeedKmh {
    final double hours = safeDurationSeconds / 3600.0;
    if (hours <= 0.0) return 0.0;
    final double value = distanceKm / hours;
    return value.isFinite && value > 0.0 ? value : 0.0;
  }

  String get averageSpeedLabel {
    final double speed = averageSpeedKmh;
    if (speed <= 0.0) return '—';
    return '${speed.toStringAsFixed(speed >= 10 ? 0 : 1)} km/h';
  }

  String get compactDistanceLabel {
    final double meters = safeDistanceMeters;
    if (meters <= 0.0) return '0 m';
    if (meters < 1000.0) return '${meters.round()} m';
    return '${(meters / 1000.0).toStringAsFixed(meters >= 10000.0 ? 1 : 2)} km';
  }

  String get compactDurationLabel {
    final int seconds = safeDurationSeconds.round().clamp(0, 1 << 31).toInt();
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';

    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    return '${minutes}m';
  }

  PlannedRoute sanitized({int maxPoints = 2500}) {
    final List<LatLng> validPoints = points
        .where(isValidLatLng)
        .take(maxPoints <= 0 ? points.length : maxPoints)
        .toList(growable: false);

    return copyWith(
      points: List<LatLng>.unmodifiable(validPoints),
      distanceMeters: safeDistanceMeters,
      durationSeconds: safeDurationSeconds,
    );
  }
}

extension MapboxPlaceResultUxX on MapboxPlaceResult {
  String get displayTitle => name.trim().isEmpty ? 'Pinned location' : name.trim();

  String get displaySubtitle {
    final String trimmed = address.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
  }
}
