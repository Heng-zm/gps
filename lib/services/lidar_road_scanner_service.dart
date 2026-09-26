import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

enum RoadAnomalyType {
  pothole,
  speedBump,
  sunkenManhole,
  roughPavement,
}

class LidarPoint3D {
  const LidarPoint3D({
    required this.x,
    required this.y,
    required this.z,
    required this.depthMeters,
    required this.intensity,
  });

  final double x; // Horizontal offset (-1.0 to 1.0)
  final double y; // Vertical height offset
  final double z; // Distance ahead in meters (0 to 30m)
  final double depthMeters;
  final double intensity; // Reflectance (0.0 to 1.0)
}

class LidarRoadAnomaly {
  const LidarRoadAnomaly({
    required this.type,
    required this.distanceMeters,
    required this.depthCm,
    required this.widthCm,
    required this.severityScore, // 0 to 100
    required this.label,
  });

  final RoadAnomalyType type;
  final double distanceMeters;
  final double depthCm;
  final double widthCm;
  final int severityScore;
  final String label;
}

class LidarScanFrame {
  const LidarScanFrame({
    required this.points,
    required this.anomalies,
    required this.surfaceSmoothnessScore, // 0 to 100
    required this.laserPointCount,
    required this.nearestHazardMeters,
    required this.timestamp,
  });

  final List<LidarPoint3D> points;
  final List<LidarRoadAnomaly> anomalies;
  final int surfaceSmoothnessScore;
  final int laserPointCount;
  final double? nearestHazardMeters;
  final DateTime timestamp;

  static final LidarScanFrame empty = LidarScanFrame(
    points: const <LidarPoint3D>[],
    anomalies: const <LidarRoadAnomaly>[],
    surfaceSmoothnessScore: 100,
    laserPointCount: 0,
    nearestHazardMeters: null,
    timestamp: DateTime.now(),
  );
}

/// Service managing iPhone LiDAR 3D Road Mesh Profiling & Hazard Detection
class LidarRoadScannerService {
  LidarRoadScannerService._();
  static final LidarRoadScannerService instance = LidarRoadScannerService._();

  final ValueNotifier<bool> isScanningN = ValueNotifier<bool>(false);
  final ValueNotifier<LidarScanFrame> frameN =
      ValueNotifier<LidarScanFrame>(LidarScanFrame.empty);

  Timer? _scanTimer;
  double _frameTick = 0.0;

  void startScanning() {
    if (isScanningN.value) return;
    isScanningN.value = true;

    // Scan cycle: 12 Hz
    _scanTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _frameTick += 0.08;
      _generateScanFrame();
    });
  }

  void stopScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    isScanningN.value = false;
    frameN.value = LidarScanFrame.empty;
  }

  void _generateScanFrame() {
    final List<LidarPoint3D> points = <LidarPoint3D>[];
    final List<LidarRoadAnomaly> anomalies = <LidarRoadAnomaly>[];

    // Synthesize road grid (30 distance rays x 12 lateral lanes)
    const int lateralCols = 12;
    const int distanceRows = 24;

    // Simulate occasional pothole or bump moving towards vehicle
    final double cycle = (_frameTick * 6.0) % 36.0;
    final double hazardDist = 36.0 - cycle; // Moves closer from 36m to 0m
    final bool hasPothole = hazardDist < 26.0 && hazardDist > 3.0;

    for (int r = 1; r <= distanceRows; r++) {
      final double zDist = r * 1.25; // 1.25m to 30m ahead
      for (int c = 0; c < lateralCols; c++) {
        final double xOffset = ((c / (lateralCols - 1)) - 0.5) * 3.6; // -1.8m to +1.8m road width

        double yElevation = 0.0;
        double intensity = 0.85;

        // Perturb if in hazard zone
        if (hasPothole && (zDist - hazardDist).abs() < 1.4 && xOffset.abs() < 0.8) {
          yElevation = -0.075; // 7.5cm pothole dip
          intensity = 0.35; // Lower reflectivity
        } else {
          // Slight road camber
          yElevation = -(xOffset.abs() * 0.02);
        }

        points.add(
          LidarPoint3D(
            x: xOffset,
            y: yElevation,
            z: zDist,
            depthMeters: zDist,
            intensity: intensity,
          ),
        );
      }
    }

    if (hasPothole) {
      anomalies.add(
        LidarRoadAnomaly(
          type: RoadAnomalyType.pothole,
          distanceMeters: hazardDist,
          depthCm: 7.5,
          widthCm: 65.0,
          severityScore: 82,
          label: 'Pothole (${hazardDist.toStringAsFixed(1)}m ahead)',
        ),
      );
    }

    final int smoothness = hasPothole
        ? (55 + math.sin(_frameTick * 3.0) * 10).round()
        : (94 + math.sin(_frameTick) * 4).round();

    frameN.value = LidarScanFrame(
      points: points,
      anomalies: anomalies,
      surfaceSmoothnessScore: smoothness.clamp(0, 100),
      laserPointCount: points.length * 48, // Equivalent point cloud density
      nearestHazardMeters: hasPothole ? hazardDist : null,
      timestamp: DateTime.now(),
    );
  }
}
