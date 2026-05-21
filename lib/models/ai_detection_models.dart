import 'dart:ui';

enum AiDetectedType {
  person,
  car,
  motorcycle,
  bicycle,
  bus,
  truck,
  trafficLight,
  stopSign,
  chair,
  obstacle,
  floor,
  road,
  wall,
  unknown,
}

extension AiDetectedTypeX on AiDetectedType {
  String get label {
    switch (this) {
      case AiDetectedType.person:
        return 'Person';
      case AiDetectedType.car:
        return 'Car';
      case AiDetectedType.motorcycle:
        return 'Motorcycle';
      case AiDetectedType.bicycle:
        return 'Bicycle';
      case AiDetectedType.bus:
        return 'Bus';
      case AiDetectedType.truck:
        return 'Truck';
      case AiDetectedType.trafficLight:
        return 'Traffic light';
      case AiDetectedType.stopSign:
        return 'Stop sign';
      case AiDetectedType.chair:
        return 'Chair';
      case AiDetectedType.obstacle:
        return 'Obstacle';
      case AiDetectedType.floor:
        return 'Floor';
      case AiDetectedType.road:
        return 'Road';
      case AiDetectedType.wall:
        return 'Wall';
      case AiDetectedType.unknown:
        return 'Object';
    }
  }

  bool get isObstacle {
    switch (this) {
      case AiDetectedType.person:
      case AiDetectedType.car:
      case AiDetectedType.motorcycle:
      case AiDetectedType.bicycle:
      case AiDetectedType.bus:
      case AiDetectedType.truck:
      case AiDetectedType.chair:
      case AiDetectedType.obstacle:
        return true;
      case AiDetectedType.trafficLight:
      case AiDetectedType.stopSign:
      case AiDetectedType.floor:
      case AiDetectedType.road:
      case AiDetectedType.wall:
      case AiDetectedType.unknown:
        return false;
    }
  }

  bool get isRoadSign {
    switch (this) {
      case AiDetectedType.trafficLight:
      case AiDetectedType.stopSign:
        return true;
      default:
        return false;
    }
  }

  bool get isSceneSurface {
    switch (this) {
      case AiDetectedType.floor:
      case AiDetectedType.road:
      case AiDetectedType.wall:
        return true;
      default:
        return false;
    }
  }
}

class AiDetection {
  const AiDetection({
    required this.type,
    required this.label,
    required this.confidence,
    required this.box,
  });

  final AiDetectedType type;
  final String label;
  final double confidence;
  final Rect box;

  bool get isUsable {
    return confidence.isFinite &&
        confidence >= 0.35 &&
        box.width > 0.02 &&
        box.height > 0.02;
  }

  bool get isObstacle => type.isObstacle;
  bool get isRoadSign => type.isRoadSign;
  bool get isSceneSurface => type.isSceneSurface;

  double get area => box.width * box.height;
  Offset get center => box.center;
}

class AiDetectionResult {
  const AiDetectionResult({
    required this.detections,
    required this.timestamp,
    required this.modelReady,
  });

  final List<AiDetection> detections;
  final DateTime timestamp;
  final bool modelReady;

  AiDetection? get primary {
    if (detections.isEmpty) return null;

    final List<AiDetection> sorted = List<AiDetection>.from(detections)
      ..sort((AiDetection a, AiDetection b) {
        final double aScore = a.confidence + (a.isObstacle ? 0.18 : 0.0);
        final double bScore = b.confidence + (b.isObstacle ? 0.18 : 0.0);
        return bScore.compareTo(aScore);
      });

    return sorted.first;
  }

  List<AiDetection> get obstacles {
    return detections
        .where((AiDetection detection) => detection.isObstacle)
        .toList(growable: false);
  }

  List<AiDetection> get roadSigns {
    return detections
        .where((AiDetection detection) => detection.isRoadSign)
        .toList(growable: false);
  }

  List<AiDetection> get sceneSurfaces {
    return detections
        .where((AiDetection detection) => detection.isSceneSurface)
        .toList(growable: false);
  }

  static AiDetectionResult empty({bool modelReady = false}) {
    return AiDetectionResult(
      detections: const <AiDetection>[],
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      modelReady: modelReady,
    );
  }
}

AiDetectedType aiDetectedTypeFromCocoLabel(String rawLabel) {
  final String label = rawLabel.trim().toLowerCase().replaceAll('_', ' ');

  switch (label) {
    case 'person':
      return AiDetectedType.person;
    case 'car':
      return AiDetectedType.car;
    case 'motorcycle':
    case 'motorbike':
      return AiDetectedType.motorcycle;
    case 'bicycle':
    case 'bike':
      return AiDetectedType.bicycle;
    case 'bus':
      return AiDetectedType.bus;
    case 'truck':
      return AiDetectedType.truck;
    case 'traffic light':
    case 'trafficlight':
      return AiDetectedType.trafficLight;
    case 'stop sign':
    case 'stopsign':
      return AiDetectedType.stopSign;
    case 'chair':
      return AiDetectedType.chair;
    case 'floor':
      return AiDetectedType.floor;
    case 'road':
    case 'street':
    case 'sidewalk':
      return AiDetectedType.road;
    case 'wall':
      return AiDetectedType.wall;
    default:
      return AiDetectedType.unknown;
  }
}
