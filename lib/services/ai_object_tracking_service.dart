import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Lightweight AI object tracking + risk scoring service for AR camera.
///
/// v1 is dependency-free and compile-safe:
/// - tap-to-lock object box
/// - optical-flow-style box growth estimate
/// - relative speed estimate
/// - risk score 0..100
///
/// Future TFLite hook:
/// feed YOLO/MobileNet/SSD detections into [updateFromDetection].
class AiObjectTrackingService {
  AiObjectTrackingService();

  final ValueNotifier<AiTrackedObject?> trackedObjectN =
      ValueNotifier<AiTrackedObject?>(null);

  DateTime? _lastTimestamp;
  double _boxScale = 1.0;
  double _relativeSpeedKmh = 0.0;
  int _stableTicks = 0;
  double _lastArea = 0.0;

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
    _lastArea = 0.28 * 0.22;

    final int score = _riskScoreFor(
      userSpeedKmh: userSpeedKmh,
      relativeSpeedKmh: _relativeSpeedKmh,
      boxArea: _lastArea,
      areaDelta: 0.0,
      confidence: 0.72,
      motionScore: 0.0,
      gpsAccuracyMeters: 12.0,
      trend: AiObjectTrend.tracking,
    );

    trackedObjectN.value = AiTrackedObject(
      id: 'tap-lock',
      label: 'Locked object',
      normalizedCenter: normalized,
      normalizedSize: const Size(0.28, 0.22),
      estimatedSpeedKmh: _relativeSpeedKmh,
      confidence: 0.72,
      riskScore: score,
      risk: _objectRiskFromScore(score),
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
    double gpsAccuracyMeters = 12.0,
    double motionScore = 0.0,
  }) {
    final AiTrackedObject? current = trackedObjectN.value;
    final double previousArea = current == null
        ? normalizedBox.width * normalizedBox.height
        : current.normalizedSize.width * current.normalizedSize.height;
    final double nextArea = normalizedBox.width * normalizedBox.height;
    final double areaDelta = nextArea - previousArea;

    _relativeSpeedKmh = _estimateRelativeSpeed(
      userSpeedKmh: userSpeedKmh,
      areaDelta: areaDelta,
      motionScore: motionScore,
    );

    final AiObjectTrend trend = _trendFor(areaDelta, _relativeSpeedKmh);
    final int score = _riskScoreFor(
      userSpeedKmh: userSpeedKmh,
      relativeSpeedKmh: _relativeSpeedKmh,
      boxArea: nextArea,
      areaDelta: areaDelta,
      confidence: confidence,
      motionScore: motionScore,
      gpsAccuracyMeters: gpsAccuracyMeters,
      trend: trend,
    );

    _lastArea = nextArea;
    _lastTimestamp = timestamp;
    trackedObjectN.value = AiTrackedObject(
      id: 'detected-$label',
      label: label.trim().isEmpty ? 'Object' : label.trim(),
      normalizedCenter: normalizedBox.center,
      normalizedSize: normalizedBox.size,
      estimatedSpeedKmh: _relativeSpeedKmh,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      riskScore: score,
      risk: _objectRiskFromScore(score),
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
        .clamp(0.36, 0.94)
        .toDouble();
    final AiObjectTrend trend = _trendFor(areaDelta, _relativeSpeedKmh);
    final int score = _riskScoreFor(
      userSpeedKmh: userSpeedKmh,
      relativeSpeedKmh: _relativeSpeedKmh,
      boxArea: newArea,
      areaDelta: areaDelta,
      confidence: confidence,
      motionScore: motionScore,
      gpsAccuracyMeters: gpsAccuracyMeters,
      trend: trend,
    );

    _lastArea = newArea;
    _lastTimestamp = timestamp;
    trackedObjectN.value = current.copyWith(
      normalizedCenter: center,
      normalizedSize: size,
      estimatedSpeedKmh: _relativeSpeedKmh,
      confidence: confidence,
      riskScore: score,
      risk: _objectRiskFromScore(score),
      trend: trend,
      updatedAt: timestamp,
    );
  }

  void clearLock() {
    _lastTimestamp = null;
    _boxScale = 1.0;
    _relativeSpeedKmh = 0.0;
    _stableTicks = 0;
    _lastArea = 0.0;
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
    if (areaDelta > 0.0025 || speedKmh >= 35.0) {
      return AiObjectTrend.closing;
    }
    if (areaDelta < -0.0025) return AiObjectTrend.movingAway;
    if (_stableTicks > 6) return AiObjectTrend.stable;
    return AiObjectTrend.tracking;
  }

  int _riskScoreFor({
    required double userSpeedKmh,
    required double relativeSpeedKmh,
    required double boxArea,
    required double areaDelta,
    required double confidence,
    required double motionScore,
    required double gpsAccuracyMeters,
    required AiObjectTrend trend,
  }) {
    double score = 8.0;

    score += (userSpeedKmh / 90.0).clamp(0.0, 1.0) * 22.0;
    score += (relativeSpeedKmh / 80.0).clamp(0.0, 1.0) * 26.0;
    score += (boxArea / 0.18).clamp(0.0, 1.0) * 18.0;
    if (areaDelta > 0) score += (areaDelta / 0.012).clamp(0.0, 1.0) * 18.0;
    score += (motionScore / 8.0).clamp(0.0, 1.0) * 8.0;
    score += (gpsAccuracyMeters / 60.0).clamp(0.0, 1.0) * 6.0;

    if (trend == AiObjectTrend.closing) score += 14.0;
    if (trend == AiObjectTrend.movingAway) score -= 12.0;
    if (trend == AiObjectTrend.stable) score -= 6.0;
    if (confidence < 0.48) score += 8.0;
    if (confidence > 0.80) score -= 4.0;

    return score.round().clamp(0, 100).toInt();
  }

  double _smooth(double oldValue, double newValue, double alpha) {
    return oldValue * (1.0 - alpha) + newValue * alpha;
  }
}

enum AiObjectRisk { low, medium, high, unknown }

AiObjectRisk _objectRiskFromScore(int score) {
  final int safeScore = score.clamp(0, 100).toInt();

  if (safeScore >= 75) return AiObjectRisk.high;
  if (safeScore >= 40) return AiObjectRisk.medium;
  if (safeScore >= 0) return AiObjectRisk.low;
  return AiObjectRisk.unknown;
}

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
    required this.riskScore,
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
  final int riskScore;
  final AiObjectRisk risk;
  final AiObjectTrend trend;
  final DateTime updatedAt;

  String get speedLabel {
    if (confidence < 0.45) return 'Tracking...';
    return '~${estimatedSpeedKmh.round()} km/h';
  }

  String get riskLabel => 'Risk $riskScore%';

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
    int? riskScore,
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
      riskScore: riskScore ?? this.riskScore,
      risk: risk ?? this.risk,
      trend: trend ?? this.trend,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
