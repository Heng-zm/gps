import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../models/mapbox_3d_config.dart';

class Mapbox3DService {
  const Mapbox3DService._();

  /// Applies camera pitch/bearing/zoom for 3D viewing.
  ///
  /// Safe to call after the Mapbox map is created.
  static Future<void> applyCameraMode({
    required mb.MapboxMap mapboxMap,
    required Mapbox3DConfig config,
    required double latitude,
    required double longitude,
    Duration duration = const Duration(milliseconds: 650),
  }) async {
    try {
      await mapboxMap.flyTo(
        config.camera(
          latitude: latitude,
          longitude: longitude,
        ),
        mb.MapAnimationOptions(duration: duration.inMilliseconds),
      );
    } catch (error, stackTrace) {
      debugPrint('Mapbox3DService.applyCameraMode failed: $error\n$stackTrace');
    }
  }

  /// Terrain API support differs across mapbox_maps_flutter versions.
  ///
  /// This method intentionally stays a safe no-op so the app compiles on
  /// versions where `Terrain` is not exposed. 3D camera pitch still works.
  static Future<void> tryEnableTerrain({
    required mb.MapboxMap mapboxMap,
    double exaggeration = 1.35,
  }) async {
    return;
  }

  /// Enables 3D buildings when supported by the active style.
  ///
  /// Works best with Standard, Standard Satellite, Streets, and Navigation styles.
  static Future<void> tryEnable3DBuildings({
    required mb.MapboxMap mapboxMap,
    double opacity = 0.72,
  }) async {
    try {
      await mapboxMap.style.addLayer(
        mb.FillExtrusionLayer(
          id: '3d-buildings',
          sourceId: 'composite',
          sourceLayer: 'building',
          minZoom: 14,
          fillExtrusionColor: 0xFF9CA3AF,
          fillExtrusionOpacity: opacity,
          fillExtrusionHeightExpression: <Object>[
            'coalesce',
            <Object>['get', 'height'],
            0,
          ],
          fillExtrusionBaseExpression: <Object>[
            'coalesce',
            <Object>['get', 'min_height'],
            0,
          ],
        ),
      );
    } catch (error) {
      debugPrint('Mapbox 3D buildings not applied: $error');
    }
  }

  static Future<void> apply3D({
    required mb.MapboxMap mapboxMap,
    required Mapbox3DMode mode,
    required double latitude,
    required double longitude,
    double bearing = 0.0,
    double baseZoom = 15.5,
  }) async {
    final Mapbox3DConfig config = Mapbox3DConfig(
      mode: mode,
      bearing: bearing,
      baseZoom: baseZoom,
    );

    await applyCameraMode(
      mapboxMap: mapboxMap,
      config: config,
      latitude: latitude,
      longitude: longitude,
    );

    if (mode.shouldEnable3DLayers) {
      await tryEnableTerrain(mapboxMap: mapboxMap);
      await tryEnable3DBuildings(mapboxMap: mapboxMap);
    }
  }
}
