import 'dart:math' as math;
import 'dart:ui';

import 'ai_detection_models.dart';

enum ArEnvironmentMode {
  street,
  markerless,
}

extension ArEnvironmentModeX on ArEnvironmentMode {
  String get label {
    switch (this) {
      case ArEnvironmentMode.street:
        return 'Street AR';
      case ArEnvironmentMode.markerless:
        return 'Markerless';
    }
  }

  ArEnvironmentMode get next {
    switch (this) {
      case ArEnvironmentMode.street:
        return ArEnvironmentMode.markerless;
      case ArEnvironmentMode.markerless:
        return ArEnvironmentMode.street;
    }
  }
}

enum ArScanState {
  idle,
  scanning,
  surfaceDetected,
  anchorLocked,
  trackingLost,
}

extension ArScanStateX on ArScanState {
  String get label {
    switch (this) {
      case ArScanState.idle:
        return 'Ready to scan';
      case ArScanState.scanning:
        return 'Scanning';
      case ArScanState.surfaceDetected:
        return 'Surface detected';
      case ArScanState.anchorLocked:
        return 'Anchor locked';
      case ArScanState.trackingLost:
        return 'Tracking lost';
    }
  }

  bool get hasAnchor {
    return this == ArScanState.surfaceDetected ||
        this == ArScanState.anchorLocked;
  }
}

enum ArGuidanceObjectType {
  forwardArrow,
  leftChevron,
  rightChevron,
  destinationFlag,
  obstacleWarning,
}

enum AiSceneObjectType {
  trafficLight,
  stopSign,
  unknown,
  person,
  car,
  bicycle,
  motorcycle,
  obstacle,
  road,
  floor,
  wall,
  sign,
}

class AiSceneObject {
  const AiSceneObject({
    required this.type,
    required this.normalizedBox,
    required this.confidence,
    required this.label,
  });

  final AiSceneObjectType type;
  final Rect normalizedBox;
  final double confidence;
  final String label;

  bool get isObstacle {
    return type == AiSceneObjectType.person ||
        type == AiSceneObjectType.car ||
        type == AiSceneObjectType.bicycle ||
        type == AiSceneObjectType.motorcycle ||
        type == AiSceneObjectType.obstacle;
  }

  bool get isUsable {
    return confidence.isFinite &&
        confidence >= 0.35 &&
        normalizedBox.width > 0.02 &&
        normalizedBox.height > 0.02;
  }
}

class ArRouteAnchor {
  const ArRouteAnchor({
    required this.id,
    required this.distanceMeters,
    required this.relativeBearing,
    required this.instruction,
    required this.screenPosition,
    required this.confidence,
    required this.anchored,
    required this.objectType,
  });

  final String id;
  final double distanceMeters;
  final double relativeBearing;
  final String instruction;
  final Offset screenPosition;
  final double confidence;
  final bool anchored;
  final ArGuidanceObjectType objectType;

  ArRouteAnchor copyWith({
    String? id,
    double? distanceMeters,
    double? relativeBearing,
    String? instruction,
    Offset? screenPosition,
    double? confidence,
    bool? anchored,
    ArGuidanceObjectType? objectType,
  }) {
    return ArRouteAnchor(
      id: id ?? this.id,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      relativeBearing: relativeBearing ?? this.relativeBearing,
      instruction: instruction ?? this.instruction,
      screenPosition: screenPosition ?? this.screenPosition,
      confidence: confidence ?? this.confidence,
      anchored: anchored ?? this.anchored,
      objectType: objectType ?? this.objectType,
    );
  }

  static ArRouteAnchor fromRoute({
    required double distanceMeters,
    required double relativeBearing,
    required String instruction,
    required bool hasRoute,
    required double scanConfidence,
    required bool anchored,
  }) {
    final double clampedBearing =
        relativeBearing.isFinite ? relativeBearing.clamp(-130.0, 130.0) : 0.0;
    final double x = 0.5 + (clampedBearing / 220.0);
    final double y = 0.54 - (distanceMeters.clamp(0.0, 120.0) / 900.0);

    return ArRouteAnchor(
      id: 'route-anchor-${distanceMeters.round()}-${clampedBearing.round()}',
      distanceMeters: distanceMeters.isFinite ? distanceMeters : 0.0,
      relativeBearing: clampedBearing,
      instruction: instruction.trim().isEmpty ? 'Follow route' : instruction,
      screenPosition: Offset(x.clamp(0.18, 0.82), y.clamp(0.30, 0.70)),
      confidence: hasRoute
          ? (0.56 + scanConfidence * 0.34).clamp(0.0, 1.0)
          : (scanConfidence * 0.45).clamp(0.0, 1.0),
      anchored: anchored,
      objectType: _objectTypeForBearing(clampedBearing, hasRoute),
    );
  }

  static ArGuidanceObjectType _objectTypeForBearing(
    double bearing,
    bool hasRoute,
  ) {
    if (!hasRoute) return ArGuidanceObjectType.forwardArrow;
    if (bearing.abs() <= 24) return ArGuidanceObjectType.forwardArrow;
    return bearing > 0
        ? ArGuidanceObjectType.rightChevron
        : ArGuidanceObjectType.leftChevron;
  }
}

class ArSceneSnapshot {
  const ArSceneSnapshot({
    required this.environmentMode,
    required this.scanState,
    required this.scanConfidence,
    required this.anchorConfidence,
    required this.anchor,
    required this.objects,
    required this.hasObstacle,
    required this.pathShift,
    required this.statusLabel,
    required this.warningLabel,
    required this.updatedAt,
  });

  final ArEnvironmentMode environmentMode;
  final ArScanState scanState;
  final double scanConfidence;
  final double anchorConfidence;
  final ArRouteAnchor? anchor;
  final List<AiSceneObject> objects;
  final bool hasObstacle;
  final double pathShift;
  final String statusLabel;
  final String warningLabel;
  final DateTime updatedAt;

  bool get anchorLocked => scanState == ArScanState.anchorLocked;
  bool get trackingLost => scanState == ArScanState.trackingLost;
  bool get shouldShowWarning => warningLabel.trim().isNotEmpty;

  ArSceneSnapshot copyWith({
    ArEnvironmentMode? environmentMode,
    ArScanState? scanState,
    double? scanConfidence,
    double? anchorConfidence,
    ArRouteAnchor? anchor,
    List<AiSceneObject>? objects,
    bool? hasObstacle,
    double? pathShift,
    String? statusLabel,
    String? warningLabel,
    DateTime? updatedAt,
  }) {
    return ArSceneSnapshot(
      environmentMode: environmentMode ?? this.environmentMode,
      scanState: scanState ?? this.scanState,
      scanConfidence: scanConfidence ?? this.scanConfidence,
      anchorConfidence: anchorConfidence ?? this.anchorConfidence,
      anchor: anchor ?? this.anchor,
      objects: objects ?? this.objects,
      hasObstacle: hasObstacle ?? this.hasObstacle,
      pathShift: pathShift ?? this.pathShift,
      statusLabel: statusLabel ?? this.statusLabel,
      warningLabel: warningLabel ?? this.warningLabel,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static ArSceneSnapshot idle({ArEnvironmentMode mode = ArEnvironmentMode.street}) {
    return ArSceneSnapshot(
      environmentMode: mode,
      scanState: ArScanState.idle,
      scanConfidence: 0.0,
      anchorConfidence: 0.0,
      anchor: null,
      objects: const <AiSceneObject>[],
      hasObstacle: false,
      pathShift: 0.0,
      statusLabel: 'AR ready',
      warningLabel: '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

double arEase(double value) {
  return CurvesEase.easeOutCubic(value.clamp(0.0, 1.0));
}

class CurvesEase {
  const CurvesEase._();

  static double easeOutCubic(double t) {
    final double p = t - 1.0;
    return p * p * p + 1.0;
  }

  static double pulse(DateTime time, {double speed = 1200}) {
    final double phase = (time.millisecondsSinceEpoch % speed) / speed;
    return 0.5 + math.sin(phase * math.pi * 2) * 0.5;
  }
}


extension AiSceneObjectFromDetectionX on AiDetection {
  AiSceneObject toSceneObject() {
    return AiSceneObject(
      type: _sceneTypeForDetection(type),
      normalizedBox: box,
      confidence: confidence,
      label: label,
    );
  }

  AiSceneObjectType _sceneTypeForDetection(AiDetectedType type) {
    switch (type) {
      case AiDetectedType.person:
        return AiSceneObjectType.person;
      case AiDetectedType.car:
      case AiDetectedType.bus:
      case AiDetectedType.truck:
        return AiSceneObjectType.car;
      case AiDetectedType.motorcycle:
        return AiSceneObjectType.motorcycle;
      case AiDetectedType.bicycle:
        return AiSceneObjectType.bicycle;
      case AiDetectedType.chair:
      case AiDetectedType.obstacle:
        return AiSceneObjectType.obstacle;
      case AiDetectedType.trafficLight:
      case AiDetectedType.stopSign:
              return AiSceneObjectType.sign;
      case AiDetectedType.floor:
        return AiSceneObjectType.floor;
      case AiDetectedType.road:
        return AiSceneObjectType.road;
      case AiDetectedType.wall:
        return AiSceneObjectType.wall;
      case AiDetectedType.unknown:
        return AiSceneObjectType.unknown;
    }
  }
}
