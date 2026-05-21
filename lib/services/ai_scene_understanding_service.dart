import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../models/ar_guidance_models.dart';

class AiSceneUnderstandingService {
  AiSceneUnderstandingService();

  final ValueNotifier<ArSceneSnapshot> sceneN =
      ValueNotifier<ArSceneSnapshot>(ArSceneSnapshot.idle());

  Timer? _scanTimer;
  DateTime? _lastUpdateAt;
  int _ticks = 0;
  double _scanConfidence = 0.0;
  double _anchorConfidence = 0.0;
  ArEnvironmentMode _mode = ArEnvironmentMode.street;
  ArScanState _scanState = ArScanState.idle;

  void start({ArEnvironmentMode mode = ArEnvironmentMode.street}) {
    _mode = mode;
    _scanState = ArScanState.scanning;
    _scanConfidence = 0.0;
    _anchorConfidence = 0.0;
    _ticks = 0;
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(
      const Duration(milliseconds: 460),
      (_) => tick(
        hasRoute: sceneN.value.anchor != null,
        distanceMeters: sceneN.value.anchor?.distanceMeters ?? 0.0,
        relativeBearing: sceneN.value.anchor?.relativeBearing ?? 0.0,
        instruction: sceneN.value.anchor?.instruction ?? 'Scan route',
        motionScore: 0.0,
        gpsAccuracyMeters: 18.0,
      ),
    );
  }

  void stop() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  void setMode(ArEnvironmentMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _scanState = ArScanState.scanning;
    _scanConfidence = 0.12;
    _anchorConfidence = 0.0;
    tick(
      hasRoute: sceneN.value.anchor != null,
      distanceMeters: sceneN.value.anchor?.distanceMeters ?? 0.0,
      relativeBearing: sceneN.value.anchor?.relativeBearing ?? 0.0,
      instruction: sceneN.value.anchor?.instruction ?? 'Scan route',
      motionScore: 0.0,
      gpsAccuracyMeters: 20.0,
      force: true,
    );
  }

  void resetScan() {
    _scanState = ArScanState.scanning;
    _scanConfidence = 0.0;
    _anchorConfidence = 0.0;
    _ticks = 0;
    tick(
      hasRoute: sceneN.value.anchor != null,
      distanceMeters: sceneN.value.anchor?.distanceMeters ?? 0.0,
      relativeBearing: sceneN.value.anchor?.relativeBearing ?? 0.0,
      instruction: sceneN.value.anchor?.instruction ?? 'Scan route',
      motionScore: 0.0,
      gpsAccuracyMeters: 20.0,
      force: true,
    );
  }

  void tick({
    required bool hasRoute,
    required double distanceMeters,
    required double relativeBearing,
    required String instruction,
    required double motionScore,
    required double gpsAccuracyMeters,
    List<AiSceneObject> detectedObjects = const <AiSceneObject>[],
    bool force = false,
  }) {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastUpdateAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 220)) {
      return;
    }
    _lastUpdateAt = now;
    _ticks++;

    final bool gpsGood =
        !gpsAccuracyMeters.isFinite || gpsAccuracyMeters <= 35.0;
    final bool stable = !motionScore.isFinite || motionScore <= 5.8;
    final bool veryShaky = motionScore.isFinite && motionScore >= 8.5;

    if (veryShaky) {
      _scanState = ArScanState.trackingLost;
      _anchorConfidence = math.max(0.0, _anchorConfidence - 0.16);
      _scanConfidence = math.max(0.0, _scanConfidence - 0.06);
    } else {
      final double scanGain = stable ? 0.055 : 0.025;
      final double gpsGain = gpsGood ? 0.018 : -0.025;
      _scanConfidence = (_scanConfidence + scanGain + gpsGain).clamp(0.0, 1.0);

      if (_scanConfidence < 0.22) {
        _scanState = ArScanState.scanning;
      } else if (_scanConfidence < 0.56) {
        _scanState = ArScanState.surfaceDetected;
      } else {
        _anchorConfidence =
            (_anchorConfidence + (stable ? 0.06 : 0.025)).clamp(0.0, 1.0);
        _scanState = _anchorConfidence >= 0.52
            ? ArScanState.anchorLocked
            : ArScanState.surfaceDetected;
      }
    }

    final List<AiSceneObject> objects = _mergeDetections(
      detectedObjects,
      motionScore: motionScore,
      hasRoute: hasRoute,
    );

    final bool hasObstacle = objects.any((AiSceneObject object) {
      if (!object.isObstacle || !object.isUsable) return false;
      final double centerX = object.normalizedBox.center.dx;
      final double area = object.normalizedBox.width * object.normalizedBox.height;
      return area >= 0.025 && centerX > 0.28 && centerX < 0.72;
    });

    final double pathShift = hasObstacle
        ? _recommendedPathShift(objects)
        : 0.0;

    final ArRouteAnchor anchor = ArRouteAnchor.fromRoute(
      distanceMeters: distanceMeters,
      relativeBearing: relativeBearing + pathShift * 18.0,
      instruction: instruction,
      hasRoute: hasRoute,
      scanConfidence: _scanConfidence,
      anchored: _scanState == ArScanState.anchorLocked,
    );

    final String status = _buildStatusLabel(
      hasRoute: hasRoute,
      hasObstacle: hasObstacle,
      stable: stable,
      gpsGood: gpsGood,
    );

    final String warning = _buildWarningLabel(
      hasRoute: hasRoute,
      hasObstacle: hasObstacle,
      stable: stable,
      gpsGood: gpsGood,
    );

    final ArSceneSnapshot next = ArSceneSnapshot(
      environmentMode: _mode,
      scanState: _scanState,
      scanConfidence: _scanConfidence,
      anchorConfidence: _anchorConfidence,
      anchor: anchor,
      objects: List<AiSceneObject>.unmodifiable(objects),
      hasObstacle: hasObstacle,
      pathShift: pathShift,
      statusLabel: status,
      warningLabel: warning,
      updatedAt: now,
    );

    if (_shouldNotify(next)) {
      sceneN.value = next;
    }
  }

  List<AiSceneObject> _mergeDetections(
    List<AiSceneObject> detectedObjects, {
    required double motionScore,
    required bool hasRoute,
  }) {
    final List<AiSceneObject> objects = <AiSceneObject>[];
    objects.addAll(detectedObjects.where((AiSceneObject object) => object.isUsable));

    // Lightweight heuristic obstacle simulation for camera-only mode.
    // This keeps the UI useful before a real detector is connected.
    if (hasRoute && motionScore.isFinite && motionScore > 3.4 && _ticks % 7 == 0) {
      objects.add(
        AiSceneObject(
          type: AiSceneObjectType.obstacle,
          label: 'Possible obstacle',
          confidence: 0.42,
          normalizedBox: Rect.fromCenter(
            center: Offset(0.50 + math.sin(_ticks * 0.7) * 0.12, 0.56),
            width: 0.20,
            height: 0.18,
          ),
        ),
      );
    }

    return objects;
  }

  double _recommendedPathShift(List<AiSceneObject> objects) {
    final Iterable<AiSceneObject> obstacles =
        objects.where((AiSceneObject object) => object.isObstacle);
    if (obstacles.isEmpty) return 0.0;

    double weighted = 0.0;
    double total = 0.0;

    for (final AiSceneObject object in obstacles) {
      final double centerX = object.normalizedBox.center.dx;
      final double weight = object.confidence.clamp(0.0, 1.0);
      weighted += (centerX < 0.5 ? 1.0 : -1.0) * weight;
      total += weight;
    }

    if (total <= 0.0) return 0.0;
    return (weighted / total).clamp(-1.0, 1.0);
  }

  String _buildStatusLabel({
    required bool hasRoute,
    required bool hasObstacle,
    required bool stable,
    required bool gpsGood,
  }) {
    if (_scanState == ArScanState.trackingLost) {
      return 'Tracking lost · re-scan';
    }
    if (!stable) return 'Hold steady to lock anchor';
    if (!gpsGood) return 'GPS weak · anchor estimating';
    if (!hasRoute) return 'Scan ready · plan route';
    if (hasObstacle) return 'Object-aware path active';
    if (_scanState == ArScanState.anchorLocked) return 'Anchor locked';
    if (_scanState == ArScanState.surfaceDetected) return 'Surface detected';
    return 'Scanning environment';
  }

  String _buildWarningLabel({
    required bool hasRoute,
    required bool hasObstacle,
    required bool stable,
    required bool gpsGood,
  }) {
    if (!stable) return 'Phone motion is high';
    if (!gpsGood) return 'GPS accuracy is weak';
    if (hasObstacle) return 'Obstacle ahead · path adjusted';
    return '';
  }

  bool _shouldNotify(ArSceneSnapshot next) {
    final ArSceneSnapshot current = sceneN.value;

    if (current.environmentMode != next.environmentMode) return true;
    if (current.scanState != next.scanState) return true;
    if (current.hasObstacle != next.hasObstacle) return true;
    if (current.warningLabel != next.warningLabel) return true;
    if ((current.scanConfidence - next.scanConfidence).abs() >= 0.025) {
      return true;
    }
    if ((current.anchorConfidence - next.anchorConfidence).abs() >= 0.025) {
      return true;
    }

    final ArRouteAnchor? a = current.anchor;
    final ArRouteAnchor? b = next.anchor;
    if (a == null || b == null) return a != b;

    if ((a.relativeBearing - b.relativeBearing).abs() >= 4.0) return true;
    if ((a.distanceMeters - b.distanceMeters).abs() >= 3.0) return true;
    if (a.anchored != b.anchored) return true;
    if (a.objectType != b.objectType) return true;

    return false;
  }

  void dispose() {
    stop();
    sceneN.dispose();
  }
}
