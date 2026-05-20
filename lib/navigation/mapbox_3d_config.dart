import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

/// Camera depth presets for Mapbox.
///
/// Keep enum names stable because [storageKey] may be saved in settings.
enum Mapbox3DMode {
  flat,
  soft3D,
  full3D,
  navigation3D,
}

extension Mapbox3DModeX on Mapbox3DMode {
  String get label {
    switch (this) {
      case Mapbox3DMode.flat:
        return 'Flat';
      case Mapbox3DMode.soft3D:
        return 'Soft 3D';
      case Mapbox3DMode.full3D:
        return 'Full 3D';
      case Mapbox3DMode.navigation3D:
        return 'Navigation 3D';
    }
  }

  String get shortLabel {
    switch (this) {
      case Mapbox3DMode.flat:
        return 'Flat';
      case Mapbox3DMode.soft3D:
        return 'Soft';
      case Mapbox3DMode.full3D:
        return 'Full';
      case Mapbox3DMode.navigation3D:
        return 'Nav';
    }
  }

  String get description {
    switch (this) {
      case Mapbox3DMode.flat:
        return 'Top-down map for clean route viewing.';
      case Mapbox3DMode.soft3D:
        return 'Slight pitch with subtle depth.';
      case Mapbox3DMode.full3D:
        return 'High pitch for immersive 3D buildings and terrain.';
      case Mapbox3DMode.navigation3D:
        return 'Driving-style camera with strong pitch and heading.';
    }
  }

  IconData get icon {
    switch (this) {
      case Mapbox3DMode.flat:
        return CupertinoIcons.square_grid_2x2;
      case Mapbox3DMode.soft3D:
        return CupertinoIcons.cube_box;
      case Mapbox3DMode.full3D:
        return CupertinoIcons.cube_box_fill;
      case Mapbox3DMode.navigation3D:
        return CupertinoIcons.location_north_line_fill;
    }
  }

  double get pitch {
    switch (this) {
      case Mapbox3DMode.flat:
        return 0.0;
      case Mapbox3DMode.soft3D:
        return 35.0;
      case Mapbox3DMode.full3D:
        return 58.0;
      case Mapbox3DMode.navigation3D:
        return 65.0;
    }
  }

  double get zoomBoost {
    switch (this) {
      case Mapbox3DMode.flat:
        return 0.0;
      case Mapbox3DMode.soft3D:
        return 0.20;
      case Mapbox3DMode.full3D:
        return 0.55;
      case Mapbox3DMode.navigation3D:
        return 0.75;
    }
  }

  bool get shouldEnable3DLayers => this != Mapbox3DMode.flat;

  bool get isFlat => this == Mapbox3DMode.flat;

  Color get accentColor {
    switch (this) {
      case Mapbox3DMode.flat:
        return Colors.white70;
      case Mapbox3DMode.soft3D:
        return const Color(0xFF60A5FA);
      case Mapbox3DMode.full3D:
        return const Color(0xFF22C55E);
      case Mapbox3DMode.navigation3D:
        return const Color(0xFFF59E0B);
    }
  }

  String get storageKey => name;

  Mapbox3DMode get next {
    switch (this) {
      case Mapbox3DMode.flat:
        return Mapbox3DMode.soft3D;
      case Mapbox3DMode.soft3D:
        return Mapbox3DMode.full3D;
      case Mapbox3DMode.full3D:
        return Mapbox3DMode.navigation3D;
      case Mapbox3DMode.navigation3D:
        return Mapbox3DMode.flat;
    }
  }

  static Mapbox3DMode fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return Mapbox3DMode.flat;

    for (final Mapbox3DMode mode in Mapbox3DMode.values) {
      if (mode.storageKey.toLowerCase() == normalized ||
          mode.label.toLowerCase() == normalized ||
          mode.shortLabel.toLowerCase() == normalized) {
        return mode;
      }
    }

    switch (normalized.replaceAll('-', '_').replaceAll(' ', '_')) {
      case 'soft':
      case 'soft3d':
      case 'soft_3d':
        return Mapbox3DMode.soft3D;
      case 'full':
      case 'full3d':
      case 'full_3d':
      case 'building':
      case 'buildings':
        return Mapbox3DMode.full3D;
      case 'nav':
      case 'navigation':
      case 'navigation3d':
      case 'navigation_3d':
      case 'drive':
      case 'driving':
        return Mapbox3DMode.navigation3D;
      case 'flat':
      case '2d':
      default:
        return Mapbox3DMode.flat;
    }
  }
}

/// Immutable 3D camera configuration for Mapbox.
class Mapbox3DConfig {
  const Mapbox3DConfig({
    required this.mode,
    this.bearing = 0.0,
    this.baseZoom = 15.5,
    this.fallbackLatitude = 11.5564,
    this.fallbackLongitude = 104.9282,
  });

  final Mapbox3DMode mode;
  final double bearing;
  final double baseZoom;
  final double fallbackLatitude;
  final double fallbackLongitude;

  static const double minZoom = 0.0;
  static const double maxZoom = 22.0;
  static const double maxPitch = 85.0;

  double get pitch => _clampDouble(mode.pitch, 0.0, maxPitch);

  double get zoom => _clampDouble(baseZoom + mode.zoomBoost, minZoom, maxZoom);

  double get safeBearing => normalizeBearing(bearing);

  bool get shouldEnable3DLayers => mode.shouldEnable3DLayers;

  bool get isFlat => mode.isFlat;

  mb.CameraOptions camera({
    required double latitude,
    required double longitude,
    double? zoomOverride,
    double? pitchOverride,
    double? bearingOverride,
  }) {
    final bool valid = isValidCoordinate(latitude, longitude);
    final double safeLat = valid ? latitude : safeLatitude(fallbackLatitude);
    final double safeLng = valid ? longitude : safeLongitude(fallbackLongitude);

    return mb.CameraOptions(
      center: mb.Point(
        coordinates: mb.Position(safeLng, safeLat),
      ),
      zoom: zoomOverride == null
          ? zoom
          : _clampDouble(zoomOverride, minZoom, maxZoom),
      pitch: pitchOverride == null
          ? pitch
          : _clampDouble(pitchOverride, 0.0, maxPitch),
      bearing: bearingOverride == null
          ? safeBearing
          : normalizeBearing(bearingOverride),
    );
  }

  Mapbox3DConfig forNavigation(double heading) {
    return copyWith(
      mode: Mapbox3DMode.navigation3D,
      bearing: heading,
      baseZoom: math.max(baseZoom, 16.0),
    );
  }

  Mapbox3DConfig forRoutePreview() {
    return copyWith(
      mode: mode == Mapbox3DMode.navigation3D ? Mapbox3DMode.full3D : mode,
      bearing: 0.0,
    );
  }

  Mapbox3DConfig copyWith({
    Mapbox3DMode? mode,
    double? bearing,
    double? baseZoom,
    double? fallbackLatitude,
    double? fallbackLongitude,
  }) {
    return Mapbox3DConfig(
      mode: mode ?? this.mode,
      bearing: bearing ?? this.bearing,
      baseZoom: baseZoom ?? this.baseZoom,
      fallbackLatitude: fallbackLatitude ?? this.fallbackLatitude,
      fallbackLongitude: fallbackLongitude ?? this.fallbackLongitude,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': mode.storageKey,
      'bearing': safeBearing,
      'baseZoom': _clampDouble(baseZoom, minZoom, maxZoom),
      'fallbackLatitude': safeLatitude(fallbackLatitude),
      'fallbackLongitude': safeLongitude(fallbackLongitude),
    };
  }

  static Mapbox3DConfig fromJson(Object? raw) {
    if (raw is! Map) return const Mapbox3DConfig(mode: Mapbox3DMode.flat);

    return Mapbox3DConfig(
      mode: Mapbox3DModeX.fromStorageKey(raw['mode']?.toString()),
      bearing: _readDouble(raw['bearing']),
      baseZoom: _readDouble(raw['baseZoom'], fallback: 15.5),
      fallbackLatitude: safeLatitude(_readDouble(raw['fallbackLatitude'])),
      fallbackLongitude: safeLongitude(_readDouble(raw['fallbackLongitude'])),
    );
  }

  static bool isValidCoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -90.0 &&
        latitude <= 90.0 &&
        longitude >= -180.0 &&
        longitude <= 180.0;
  }

  static double safeLatitude(double value, {double fallback = 11.5564}) {
    if (value.isFinite && value >= -90.0 && value <= 90.0) return value;
    if (fallback.isFinite && fallback >= -90.0 && fallback <= 90.0) {
      return fallback;
    }
    return 11.5564;
  }

  static double safeLongitude(double value, {double fallback = 104.9282}) {
    if (value.isFinite && value >= -180.0 && value <= 180.0) return value;
    if (fallback.isFinite && fallback >= -180.0 && fallback <= 180.0) {
      return fallback;
    }
    return 104.9282;
  }

  static double normalizeBearing(double value) {
    if (!value.isFinite) return 0.0;
    final double normalized = value % 360.0;
    return normalized < 0.0 ? normalized + 360.0 : normalized;
  }

  static double _readDouble(Object? value, {double fallback = 0.0}) {
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : fallback;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value.trim());
      return parsed != null && parsed.isFinite ? parsed : fallback;
    }
    return fallback;
  }

  static double _clampDouble(double value, double min, double max) {
    if (!value.isFinite) return min;
    return value.clamp(min, max).toDouble();
  }
}
