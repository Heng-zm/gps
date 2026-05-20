import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Dependency-free v1 object tracking service for AR camera.
///
/// What it does now:
/// - tap-to-lock screen point
/// - lightweight optical-flow-style drift prediction
/// - object box growth simulation based on user speed + motion
/// - relative speed/risk estimate
///
/// TFLite hook:
/// Later, replace [lockAtScreenPoint] with detector output from a
/// YOLO/MobileNet/SSD model and feed detections into [updateFromDetection].
class AiObjectTrackingService {
  AiObjectTrackingService();

  final ValueNotifier<AiTrackedObject?> trackedObjectN =
      ValueNotifier<AiTrackedObject?>(null);

  DateTime? _lastTimestamp;
  double _boxScale = 1.0;
  double _relativeSpeedKmh = 0.0;
  int _stableTicks = 0;

  bool get hasLock => trackedObjectN.value != null;

  void lockAtScreenPoint(
    Offset point,
    Size screen, {
    required double userSpeedKmh,
    required DateTime timestamp,
  }) {
    final Offset normalized = _normalize(point, screen);
    _lastTimestamp = timestamp;
    _boxScale = 1.0;
    _relativeSpeedKmh = math.max(0.0, userSpeedKmh * 0.35);
    _stableTicks = 0;

    trackedObjectN.value = AiTrackedObject(
      id: 'tap-lock',
      label: 'Locked object',
      normalizedCenter: normalized,
      normalizedSize: const Size(0.28, 0.22),
      estimatedSpeedKmh: _relativeSpeedKmh,
      confidence: 0.72,
      risk: AiObjectRisk.low,
      trend: AiObjectTrend.tracking,
      updatedAt: timestamp,
    );
  }

  /// TFLite-ready hook for future real object detection.
  void updateFromDetection({
    required Rect normalizedBox,
    required String label,
    required double confidence,
    required double userSpeedKmh,
    required DateTime timestamp,
  }) {
    final Offset center = normalizedBox.center;
    final AiTrackedObject? current = trackedObjectN.value;
    final double previousArea = current == null
        ? normalizedBox.width * normalizedBox.height
        : current.normalizedSize.width * current.normalizedSize.height;
    final double nextArea = normalizedBox.width * normalizedBox.height;
    final double areaDelta = nextArea - previousArea;

    _relativeSpeedKmh = _estimateRelativeSpeed(
      userSpeedKmh: userSpeedKmh,
      areaDelta: areaDelta,
      motionScore: 0.0,
    );

    final AiObjectTrend trend = _trendFor(areaDelta, _relativeSpeedKmh);
    final AiObjectRisk risk = _riskFor(
      speedKmh: _relativeSpeedKmh,
      confidence: confidence,
      trend: trend,
    );
    _lastTimestamp = timestamp;
    trackedObjectN.value = AiTrackedObject(
      id: 'detected-$label',
      label: label,
      normalizedCenter: center,
      normalizedSize: normalizedBox.size,
      estimatedSpeedKmh: _relativeSpeedKmh,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      risk: risk,
      trend: trend,
      updatedAt: timestamp,
    );
  }

  void updateTelemetry({
    required double userSpeedKmh,
    required double gpsAccuracyMeters,
    required double motionScore,
    required DateTime timestamp,
  }) {
    final AiTrackedObject? current = trackedObjectN.value;
    if (current == null) return;

    final DateTime last = _lastTimestamp ?? current.updatedAt;
    final double dt = math.max(
      0.12,
      timestamp.difference(last).inMilliseconds / 1000.0,
    );

    final double accuracyPenalty = gpsAccuracyMeters.isFinite
        ? (gpsAccuracyMeters / 80.0).clamp(0.0, 0.25).toDouble()
        : 0.16;
    final double motionPenalty =
        (motionScore / 10.0).clamp(0.0, 0.28).toDouble();

    _stableTicks = motionScore < 2.0 ? _stableTicks + 1 : 0;

    final double centerDrift = (userSpeedKmh / 3600.0) * dt * 0.012;
    final double grow = (userSpeedKmh / 140.0) * dt * 0.018;
    final double shake = motionPenalty * 0.004;

    final Offset center = Offset(
      (current.normalizedCenter.dx +
              math.sin(timestamp.millisecondsSinceEpoch / 430.0) * shake)
          .clamp(0.12, 0.88)
          .toDouble(),
      (current.normalizedCenter.dy +
              centerDrift +
              math.cos(timestamp.millisecondsSinceEpoch / 510.0) * shake)
          .clamp(0.16, 0.86)
          .toDouble(),
    );

    final double oldArea =
        current.normalizedSize.width * current.normalizedSize.height;
    _boxScale = (_boxScale + grow).clamp(0.82, 1.42).toDouble();
    final Size size = Size(
      (0.28 * _boxScale).clamp(0.18, 0.46).toDouble(),
      (0.22 * _boxScale).clamp(0.14, 0.38).toDouble(),
    );
    final double newArea = size.width * size.height;
    final double areaDelta = newArea - oldArea;

    _relativeSpeedKmh = _smooth(
      _relativeSpeedKmh,
      _estimateRelativeSpeed(
        userSpeedKmh: userSpeedKmh,
        areaDelta: areaDelta,
        motionScore: motionScore,
      ),
      0.22,
    );

    final double confidence = (current.confidence +
            0.004 -
            accuracyPenalty * 0.05 -
            motionPenalty * 0.08)
        .clamp(0.36, 0.92)
        .toDouble();
    final AiObjectTrend trend = _trendFor(areaDelta, _relativeSpeedKmh);
    final AiObjectRisk risk = _riskFor(
      speedKmh: _relativeSpeedKmh,
      confidence: confidence,
      trend: trend,
    );
    _lastTimestamp = timestamp;
    trackedObjectN.value = current.copyWith(
      normalizedCenter: center,
      normalizedSize: size,
      estimatedSpeedKmh: _relativeSpeedKmh,
      confidence: confidence,
      risk: risk,
      trend: trend,
      updatedAt: timestamp,
    );
  }

  void clearLock() {
    _lastTimestamp = null;
    _boxScale = 1.0;
    _relativeSpeedKmh = 0.0;
    _stableTicks = 0;
    trackedObjectN.value = null;
  }

  void dispose() {
    trackedObjectN.dispose();
  }

  Offset _normalize(Offset point, Size screen) {
    return Offset(
      (point.dx / math.max(1.0, screen.width)).clamp(0.0, 1.0).toDouble(),
      (point.dy / math.max(1.0, screen.height)).clamp(0.0, 1.0).toDouble(),
    );
  }

  double _estimateRelativeSpeed({
    required double userSpeedKmh,
    required double areaDelta,
    required double motionScore,
  }) {
    final double closingBoost = areaDelta > 0 ? areaDelta * 420.0 : 0.0;
    final double motionNoise = (motionScore / 12.0).clamp(0.0, 0.18).toDouble();
    final double base = userSpeedKmh * (0.28 + motionNoise);
    return (base + closingBoost).clamp(0.0, 160.0).toDouble();
  }

  AiObjectTrend _trendFor(double areaDelta, double speedKmh) {
    if (areaDelta > 0.0025 || speedKmh >= 35.0) return AiObjectTrend.closing;
    if (areaDelta < -0.0025) return AiObjectTrend.movingAway;
    if (_stableTicks > 6) return AiObjectTrend.stable;
    return AiObjectTrend.tracking;
  }

  AiObjectRisk _riskFor({
    required double speedKmh,
    required double confidence,
    required AiObjectTrend trend,
  }) {
    if (confidence < 0.42) return AiObjectRisk.unknown;
    if (trend == AiObjectTrend.closing && speedKmh >= 45.0)
      return AiObjectRisk.high;
    if (trend == AiObjectTrend.closing || speedKmh >= 28.0)
      return AiObjectRisk.medium;
    return AiObjectRisk.low;
  }

  double _smooth(double oldValue, double newValue, double alpha) {
    return oldValue * (1.0 - alpha) + newValue * alpha;
  }
}

enum AiObjectRisk { low, medium, high, unknown }

extension AiObjectRiskX on AiObjectRisk {
  Color get color {
    switch (this) {
      case AiObjectRisk.low:
        return const Color(0xFF32D74B);
      case AiObjectRisk.medium:
        return const Color(0xFFFFD54F);
      case AiObjectRisk.high:
        return const Color(0xFFFF3B30);
      case AiObjectRisk.unknown:
        return Colors.white54;
    }
  }

  IconData get icon {
    switch (this) {
      case AiObjectRisk.low:
        return CupertinoIcons.checkmark_shield_fill;
      case AiObjectRisk.medium:
        return CupertinoIcons.exclamationmark_triangle_fill;
      case AiObjectRisk.high:
        return CupertinoIcons.exclamationmark_octagon_fill;
      case AiObjectRisk.unknown:
        return CupertinoIcons.question_circle_fill;
    }
  }

  String get title {
    switch (this) {
      case AiObjectRisk.low:
        return 'Object locked';
      case AiObjectRisk.medium:
        return 'Object ahead · caution';
      case AiObjectRisk.high:
        return 'Closing fast · slow down';
      case AiObjectRisk.unknown:
        return 'Tracking confidence low';
    }
  }
}

enum AiObjectTrend { tracking, closing, movingAway, stable }

class AiTrackedObject {
  const AiTrackedObject({
    required this.id,
    required this.label,
    required this.normalizedCenter,
    required this.normalizedSize,
    required this.estimatedSpeedKmh,
    required this.confidence,
    required this.risk,
    required this.trend,
    required this.updatedAt,
  });

  final String id;
  final String label;
  final Offset normalizedCenter;
  final Size normalizedSize;
  final double estimatedSpeedKmh;
  final double confidence;
  final AiObjectRisk risk;
  final AiObjectTrend trend;
  final DateTime updatedAt;

  String get speedLabel {
    if (confidence < 0.45) return 'Tracking...';
    return '~$estimatedSpeedKmh km/h';
  }

  String get advice {
    switch (trend) {
      case AiObjectTrend.closing:
        return 'Object appears closer · keep distance';
      case AiObjectTrend.movingAway:
        return 'Object moving away';
      case AiObjectTrend.stable:
        return 'Stable lock · speed estimate improving';
      case AiObjectTrend.tracking:
        return 'Optical-flow lock active · $confidencePercent% confidence';
    }
  }

  int get confidencePercent => (confidence * 100).round().clamp(0, 100).toInt();

  Rect screenBoxFor(Size screen) {
    final double width = (normalizedSize.width * screen.width)
        .clamp(74.0, screen.width * 0.72)
        .toDouble();
    final double height = (normalizedSize.height * screen.height)
        .clamp(62.0, screen.height * 0.46)
        .toDouble();
    final double centerX = normalizedCenter.dx * screen.width;
    final double centerY = normalizedCenter.dy * screen.height;

    final double left = (centerX - width / 2)
        .clamp(10.0, math.max(10.0, screen.width - width - 10.0))
        .toDouble();
    final double top = (centerY - height / 2)
        .clamp(84.0, math.max(84.0, screen.height - height - 118.0))
        .toDouble();

    return Rect.fromLTWH(left, top, width, height);
  }

  AiTrackedObject copyWith({
    String? id,
    String? label,
    Offset? normalizedCenter,
    Size? normalizedSize,
    double? estimatedSpeedKmh,
    double? confidence,
    AiObjectRisk? risk,
    AiObjectTrend? trend,
    DateTime? updatedAt,
  }) {
    return AiTrackedObject(
      id: id ?? this.id,
      label: label ?? this.label,
      normalizedCenter: normalizedCenter ?? this.normalizedCenter,
      normalizedSize: normalizedSize ?? this.normalizedSize,
      estimatedSpeedKmh: estimatedSpeedKmh ?? this.estimatedSpeedKmh,
      confidence: confidence ?? this.confidence,
      risk: risk ?? this.risk,
      trend: trend ?? this.trend,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
