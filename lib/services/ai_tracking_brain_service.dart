import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'ai_object_tracking_service.dart';
import 'ai_road_condition_service.dart';

/// Central AI Tracking Brain for live tracking / AR Guard.
///
/// It combines GPS, object risk, road condition, battery and motion data into
/// one clear live recommendation.
class AiTrackingBrainService {
  const AiTrackingBrainService();

  AiTrackingBrainResult evaluate({
    required double speedKmh,
    required double gpsAccuracyMeters,
    required int? batteryPercent,
    required bool isCharging,
    required double motionScore,
    required bool hasRoute,
    AiTrackedObject? object,
    AiRoadConditionSnapshot? road,
  }) {
    final List<_BrainCandidate> candidates = <_BrainCandidate>[];

    if (object != null) {
      final AiTrackingRiskLevel level = _riskFromScore(object.riskScore);
      candidates.add(
        _BrainCandidate(
          priority: object.riskScore + (object.trend == AiObjectTrend.closing ? 18 : 0),
          level: level,
          icon: object.risk.icon,
          color: object.risk.color,
          title: object.riskScore >= 76
              ? 'Object danger · slow down'
              : object.riskScore >= 42
                  ? 'Object ahead · caution'
                  : 'Object locked · ${object.riskLabel}',
          subtitle: '${object.speedLabel} · ${object.riskLabel}',
          shouldVibrate: object.riskScore >= 76,
          shouldSpeak: object.riskScore >= 82,
        ),
      );
    }

    if (road != null && road.isRisky) {
      candidates.add(
        _BrainCandidate(
          priority: road.roughnessScore + 8,
          level: _riskFromScore(road.roughnessScore),
          icon: road.condition.icon,
          color: road.condition.color,
          title: 'AI Road: ${road.condition.label}',
          subtitle: '${road.condition.advice} · Roughness ${road.scoreLabel}',
          shouldVibrate: road.roughnessScore >= 82,
          shouldSpeak: road.roughnessScore >= 88,
        ),
      );
    }

    if (gpsAccuracyMeters.isFinite && gpsAccuracyMeters >= 38.0) {
      final int score = (gpsAccuracyMeters / 70.0 * 100).round().clamp(45, 92);
      candidates.add(
        _BrainCandidate(
          priority: score,
          level: _riskFromScore(score),
          icon: CupertinoIcons.location_slash_fill,
          color: const Color(0xFFFFD54F),
          title: 'GPS weak · route may be noisy',
          subtitle: 'Accuracy ${gpsAccuracyMeters.round()}m · move near open sky',
          shouldVibrate: false,
          shouldSpeak: false,
        ),
      );
    }

    if (batteryPercent != null && batteryPercent <= 18 && !isCharging) {
      candidates.add(
        _BrainCandidate(
          priority: 62,
          level: AiTrackingRiskLevel.warning,
          icon: CupertinoIcons.battery_25,
          color: const Color(0xFFFFD54F),
          title: 'Battery low · use Battery mode',
          subtitle: '$batteryPercent% remaining · reduce camera/GPS load',
          shouldVibrate: false,
          shouldSpeak: false,
        ),
      );
    }

    if (motionScore >= 5.0) {
      candidates.add(
        _BrainCandidate(
          priority: 58,
          level: AiTrackingRiskLevel.warning,
          icon: CupertinoIcons.hand_raised_fill,
          color: const Color(0xFFFFD54F),
          title: 'Phone shaking · AI confidence lower',
          subtitle: 'Hold steady for object speed and AR accuracy',
          shouldVibrate: false,
          shouldSpeak: false,
        ),
      );
    }

    if (candidates.isEmpty) {
      final String routeText = hasRoute ? 'Route guidance active' : 'Tap object to lock speed';
      return AiTrackingBrainResult(
        level: AiTrackingRiskLevel.safe,
        title: 'AI Guard active',
        subtitle: road == null
            ? routeText
            : '${road.condition.label} · $routeText',
        icon: CupertinoIcons.shield_lefthalf_fill,
        color: const Color(0xFF32D74B),
        score: 18,
        shouldVibrate: false,
        shouldSpeak: false,
        updatedAt: DateTime.now(),
      );
    }

    candidates.sort((_BrainCandidate a, _BrainCandidate b) {
      return b.priority.compareTo(a.priority);
    });

    final _BrainCandidate top = candidates.first;
    return AiTrackingBrainResult(
      level: top.level,
      title: top.title,
      subtitle: top.subtitle,
      icon: top.icon,
      color: top.color,
      score: top.priority.clamp(0, 100).toInt(),
      shouldVibrate: top.shouldVibrate,
      shouldSpeak: top.shouldSpeak,
      updatedAt: DateTime.now(),
    );
  }

  AiTrackingRiskLevel _riskFromScore(int score) {
    if (score >= 76) return AiTrackingRiskLevel.danger;
    if (score >= 42) return AiTrackingRiskLevel.warning;
    if (score >= 24) return AiTrackingRiskLevel.caution;
    return AiTrackingRiskLevel.safe;
  }
}

enum AiTrackingRiskLevel { safe, caution, warning, danger }

class AiTrackingBrainResult {
  const AiTrackingBrainResult({
    required this.level,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.score,
    required this.shouldVibrate,
    required this.shouldSpeak,
    required this.updatedAt,
  });

  final AiTrackingRiskLevel level;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int score;
  final bool shouldVibrate;
  final bool shouldSpeak;
  final DateTime updatedAt;

  static AiTrackingBrainResult idle() {
    return AiTrackingBrainResult(
      level: AiTrackingRiskLevel.safe,
      title: 'AI Guard active',
      subtitle: 'Object risk · road condition · GPS safety',
      icon: CupertinoIcons.shield_lefthalf_fill,
      color: const Color(0xFF32D74B),
      score: 0,
      shouldVibrate: false,
      shouldSpeak: false,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool materiallyDiffers(AiTrackingBrainResult other) {
    return title != other.title ||
        subtitle != other.subtitle ||
        level != other.level ||
        (score - other.score).abs() >= 4;
  }
}

class _BrainCandidate {
  const _BrainCandidate({
    required this.priority,
    required this.level,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.shouldVibrate,
    required this.shouldSpeak,
  });

  final int priority;
  final AiTrackingRiskLevel level;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool shouldVibrate;
  final bool shouldSpeak;
}
