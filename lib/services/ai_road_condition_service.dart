import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// AI Road Condition Detector v1.
///
/// Uses accelerometer magnitude, short-term variance, spike strength, and speed
/// to classify road smoothness. No ML dependency is required, but the output can
/// later be replaced with a TensorFlow Lite model.
class AiRoadConditionService {
  AiRoadConditionService();

  final ValueNotifier<AiRoadConditionSnapshot> roadConditionN =
      ValueNotifier<AiRoadConditionSnapshot>(AiRoadConditionSnapshot.initial());

  DateTime? _lastAt;
  double _emaMotion = 0.0;
  double _emaVariance = 0.0;
  double _lastMotion = 0.0;
  double _maxSpike = 0.0;

  void updateAccelerometer({
    required double x,
    required double y,
    required double z,
    required double userSpeedKmh,
    required DateTime timestamp,
  }) {
    final DateTime? previousAt = _lastAt;
    if (previousAt != null &&
        timestamp.difference(previousAt) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastAt = timestamp;

    final double magnitude = math.sqrt(x * x + y * y + z * z);
    final double motion = (magnitude - 9.80665).abs();
    final double delta = (motion - _lastMotion).abs();
    _lastMotion = motion;

    _emaMotion = _emaMotion == 0.0 ? motion : _emaMotion * 0.78 + motion * 0.22;
    _emaVariance = _emaVariance == 0.0
        ? delta
        : _emaVariance * 0.82 + delta * 0.18;
    _maxSpike = math.max(_maxSpike * 0.92, motion);

    final AiRoadCondition condition = _classify(
      speedKmh: userSpeedKmh,
      motion: _emaMotion,
      variance: _emaVariance,
      spike: _maxSpike,
    );

    final int roughness = _roughnessScore(
      motion: _emaMotion,
      variance: _emaVariance,
      spike: _maxSpike,
      speedKmh: userSpeedKmh,
      condition: condition,
    );

    final AiRoadConditionSnapshot next = AiRoadConditionSnapshot(
      condition: condition,
      roughnessScore: roughness,
      motionScore: _emaMotion,
      varianceScore: _emaVariance,
      spikeScore: _maxSpike,
      speedKmh: userSpeedKmh.isFinite ? userSpeedKmh : 0.0,
      updatedAt: timestamp,
    );

    final AiRoadConditionSnapshot old = roadConditionN.value;
    if (old.condition != next.condition ||
        (old.roughnessScore - next.roughnessScore).abs() >= 4) {
      roadConditionN.value = next;
    }
  }

  void reset() {
    _lastAt = null;
    _emaMotion = 0.0;
    _emaVariance = 0.0;
    _lastMotion = 0.0;
    _maxSpike = 0.0;
    roadConditionN.value = AiRoadConditionSnapshot.initial();
  }

  void dispose() {
    roadConditionN.dispose();
  }

  AiRoadCondition _classify({
    required double speedKmh,
    required double motion,
    required double variance,
    required double spike,
  }) {
    if (speedKmh < 4.0 && motion < 3.4) return AiRoadCondition.stopped;
    if (spike >= 9.5 && speedKmh >= 8.0) return AiRoadCondition.possiblePothole;
    if (motion >= 5.8 || variance >= 4.4) return AiRoadCondition.veryBumpy;
    if (motion >= 3.3 || variance >= 2.3) return AiRoadCondition.bumpy;
    if (motion <= 1.15 && variance <= 0.9) return AiRoadCondition.smooth;
    return AiRoadCondition.normal;
  }

  int _roughnessScore({
    required double motion,
    required double variance,
    required double spike,
    required double speedKmh,
    required AiRoadCondition condition,
  }) {
    double score = 8.0;
    score += (motion / 8.0).clamp(0.0, 1.0) * 38.0;
    score += (variance / 5.5).clamp(0.0, 1.0) * 30.0;
    score += (spike / 11.0).clamp(0.0, 1.0) * 20.0;
    score += (speedKmh / 80.0).clamp(0.0, 1.0) * 8.0;

    switch (condition) {
      case AiRoadCondition.possiblePothole:
        score = math.max(score, 86.0);
        break;
      case AiRoadCondition.veryBumpy:
        score = math.max(score, 68.0);
        break;
      case AiRoadCondition.bumpy:
        score = math.max(score, 42.0);
        break;
      case AiRoadCondition.smooth:
        score = math.min(score, 26.0);
        break;
      case AiRoadCondition.normal:
      case AiRoadCondition.stopped:
        break;
    }

    return score.round().clamp(0, 100).toInt();
  }
}

enum AiRoadCondition {
  stopped,
  smooth,
  normal,
  bumpy,
  veryBumpy,
  possiblePothole,
}

extension AiRoadConditionX on AiRoadCondition {
  String get label {
    switch (this) {
      case AiRoadCondition.stopped:
        return 'Stopped';
      case AiRoadCondition.smooth:
        return 'Smooth road';
      case AiRoadCondition.normal:
        return 'Normal road';
      case AiRoadCondition.bumpy:
        return 'Bumpy road';
      case AiRoadCondition.veryBumpy:
        return 'Very bumpy';
      case AiRoadCondition.possiblePothole:
        return 'Possible pothole';
    }
  }

  String get advice {
    switch (this) {
      case AiRoadCondition.stopped:
        return 'Vehicle appears stopped';
      case AiRoadCondition.smooth:
        return 'Road feels stable';
      case AiRoadCondition.normal:
        return 'Road condition normal';
      case AiRoadCondition.bumpy:
        return 'Reduce speed on rough road';
      case AiRoadCondition.veryBumpy:
        return 'Hold steady · road is rough';
      case AiRoadCondition.possiblePothole:
        return 'Impact detected · check road ahead';
    }
  }

  Color get color {
    switch (this) {
      case AiRoadCondition.stopped:
        return Colors.white54;
      case AiRoadCondition.smooth:
        return const Color(0xFF32D74B);
      case AiRoadCondition.normal:
        return const Color(0xFF4A9EFF);
      case AiRoadCondition.bumpy:
        return const Color(0xFFFFD54F);
      case AiRoadCondition.veryBumpy:
        return const Color(0xFFFF9F0A);
      case AiRoadCondition.possiblePothole:
        return const Color(0xFFFF3B30);
    }
  }

  IconData get icon {
    switch (this) {
      case AiRoadCondition.stopped:
        return CupertinoIcons.pause_circle_fill;
      case AiRoadCondition.smooth:
        return CupertinoIcons.checkmark_shield_fill;
      case AiRoadCondition.normal:
        return CupertinoIcons.waveform_path;
      case AiRoadCondition.bumpy:
        return CupertinoIcons.exclamationmark_triangle_fill;
      case AiRoadCondition.veryBumpy:
        return CupertinoIcons.exclamationmark_octagon_fill;
      case AiRoadCondition.possiblePothole:
        return CupertinoIcons.bolt_horizontal_circle_fill;
    }
  }
}

class AiRoadConditionSnapshot {
  const AiRoadConditionSnapshot({
    required this.condition,
    required this.roughnessScore,
    required this.motionScore,
    required this.varianceScore,
    required this.spikeScore,
    required this.speedKmh,
    required this.updatedAt,
  });

  final AiRoadCondition condition;
  final int roughnessScore;
  final double motionScore;
  final double varianceScore;
  final double spikeScore;
  final double speedKmh;
  final DateTime updatedAt;

  static AiRoadConditionSnapshot initial() {
    return AiRoadConditionSnapshot(
      condition: AiRoadCondition.normal,
      roughnessScore: 12,
      motionScore: 0.0,
      varianceScore: 0.0,
      spikeScore: 0.0,
      speedKmh: 0.0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get isRisky =>
      condition == AiRoadCondition.bumpy ||
      condition == AiRoadCondition.veryBumpy ||
      condition == AiRoadCondition.possiblePothole;

  String get scoreLabel => '$roughnessScore%';
}
