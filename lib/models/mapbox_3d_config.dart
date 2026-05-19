import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

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
        return 0.2;
      case Mapbox3DMode.full3D:
        return 0.55;
      case Mapbox3DMode.navigation3D:
        return 0.75;
    }
  }

  bool get shouldEnable3DLayers => this != Mapbox3DMode.flat;

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

  static Mapbox3DMode fromStorageKey(String? value) {
    final String normalized = (value ?? '').trim().toLowerCase();

    for (final Mapbox3DMode mode in Mapbox3DMode.values) {
      if (mode.storageKey.toLowerCase() == normalized ||
          mode.label.toLowerCase() == normalized) {
        return mode;
      }
    }

    switch (normalized) {
      case 'soft':
      case 'soft3d':
      case 'soft_3d':
        return Mapbox3DMode.soft3D;
      case 'full':
      case 'full3d':
      case 'full_3d':
        return Mapbox3DMode.full3D;
      case 'nav':
      case 'navigation':
      case 'navigation3d':
      case 'navigation_3d':
        return Mapbox3DMode.navigation3D;
      case 'flat':
      default:
        return Mapbox3DMode.flat;
    }
  }
}

class Mapbox3DConfig {
  const Mapbox3DConfig({
    required this.mode,
    this.bearing = 0.0,
    this.baseZoom = 15.5,
  });

  final Mapbox3DMode mode;
  final double bearing;
  final double baseZoom;

  double get pitch => mode.pitch.clamp(0.0, 85.0).toDouble();

  double get zoom => (baseZoom + mode.zoomBoost).clamp(0.0, 22.0).toDouble();

  double get safeBearing {
    if (!bearing.isFinite) return 0.0;
    final double normalized = bearing % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  mb.CameraOptions camera({
    required double latitude,
    required double longitude,
  }) {
    return mb.CameraOptions(
      center: mb.Point(
        coordinates: mb.Position(longitude, latitude),
      ),
      zoom: zoom,
      pitch: pitch,
      bearing: safeBearing,
    );
  }

  Mapbox3DConfig copyWith({
    Mapbox3DMode? mode,
    double? bearing,
    double? baseZoom,
  }) {
    return Mapbox3DConfig(
      mode: mode ?? this.mode,
      bearing: bearing ?? this.bearing,
      baseZoom: baseZoom ?? this.baseZoom,
    );
  }
}
