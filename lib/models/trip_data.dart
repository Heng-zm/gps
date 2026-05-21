import 'package:latlong2/latlong.dart';

/// Represents a single GPS data point captured during a trip.
///
/// Supports old and new JSON formats:
/// - speed / spd / speedMph / speed_mph
/// - alt / altFt / altitudeFt / altitude_ft
/// - time / timestamp / ts
/// - acc / accuracy / accuracyMeters / accuracy_m
class TripPoint {
  const TripPoint({
    required this.position,
    required this.speedMph,
    required this.altitudeFt,
    required this.timestamp,
    required this.accuracyMeters,
  });

  final LatLng position;
  final double speedMph;
  final double altitudeFt;
  final DateTime timestamp;
  final double accuracyMeters;

  bool get isValid => isValidLatLng(position);

  double get speedKmh => _safeNonNegative(speedMph) * 1.609344;

  double get altitudeMeters => _safeFinite(altitudeFt) / 3.28084;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      // Do NOT clamp coordinates to positive numbers. West/South coordinates
      // are valid and must remain negative.
      'lat': _safeCoordinate(position.latitude),
      'lng': _safeCoordinate(position.longitude),
      'speed': _safeNonNegative(speedMph),
      'spd': _safeNonNegative(speedMph),
      'alt': _safeFinite(altitudeFt),
      'altFt': _safeFinite(altitudeFt),
      'time': timestamp.millisecondsSinceEpoch,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'acc': _safeNonNegative(accuracyMeters),
    };
  }

  factory TripPoint.fromJson(Map<String, dynamic> json) {
    final DateTime parsedTime = _readDateTime(
      json['time'] ?? json['timestamp'] ?? json['ts'],
    );

    return TripPoint(
      position: LatLng(
        _readDouble(json['lat'] ?? json['latitude']),
        _readDouble(json['lng'] ?? json['lon'] ?? json['longitude']),
      ),
      speedMph: _safeNonNegative(
        _readDouble(
          json['speed'] ??
              json['spd'] ??
              json['speedMph'] ??
              json['speed_mph'],
        ),
      ),
      altitudeFt: _safeFinite(
        _readDouble(
          json['alt'] ??
              json['altFt'] ??
              json['altitudeFt'] ??
              json['altitude_ft'],
        ),
      ),
      timestamp: parsedTime,
      accuracyMeters: _safeNonNegative(
        _readDouble(
          json['acc'] ??
              json['accuracy'] ??
              json['accuracyMeters'] ??
              json['accuracy_m'],
        ),
      ),
    );
  }

  static TripPoint? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    try {
      final TripPoint point = TripPoint.fromJson(
        Map<String, dynamic>.from(raw),
      );

      return point.isValid ? point : null;
    } catch (_) {
      return null;
    }
  }

  TripPoint copyWith({
    LatLng? position,
    double? speedMph,
    double? altitudeFt,
    DateTime? timestamp,
    double? accuracyMeters,
  }) {
    return TripPoint(
      position: position ?? this.position,
      speedMph: speedMph ?? this.speedMph,
      altitudeFt: altitudeFt ?? this.altitudeFt,
      timestamp: timestamp ?? this.timestamp,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
    );
  }
}

/// Represents the completed statistics and path of a recorded journey.
class TripSummary {
  TripSummary({
    required this.id,
    required this.date,
    required this.totalTime,
    required this.stoppedTime,
    required this.movingTime,
    required this.maxSpeedMph,
    required this.avgSpeedMph,
    required this.altitudeGainFt,
    required this.maxAltitudeFt,
    required this.minAltitudeFt,
    required this.distanceMiles,
    required List<TripPoint> points,
  }) : points = List<TripPoint>.unmodifiable(
          points.where((TripPoint point) => point.isValid),
        );

  final String id;
  final DateTime date;
  final Duration totalTime;
  final Duration stoppedTime;
  final Duration movingTime;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final double altitudeGainFt;
  final double maxAltitudeFt;
  final double minAltitudeFt;
  final double distanceMiles;
  final List<TripPoint> points;

  /// Cached formatters. These run only once per trip instance.
  late final String formattedTotalTime = _formatDuration(totalTime);
  late final String formattedStoppedTime = _formatDuration(stoppedTime);
  late final String formattedMovingTime = _formatDuration(effectiveMovingTime);

  late final int routeQualityScore = _calculateRouteQuality(points);
  late final String routeQualityLabel = _routeQualityLabel(routeQualityScore);

  int get pointCount => points.length;

  bool get hasRoute => points.length >= 2;

  Duration get safeTotalTime => totalTime.isNegative ? Duration.zero : totalTime;

  Duration get safeStoppedTime {
    if (stoppedTime.isNegative) return Duration.zero;
    if (stoppedTime > safeTotalTime) return safeTotalTime;
    return stoppedTime;
  }

  Duration get effectiveMovingTime {
    if (!movingTime.isNegative && movingTime > Duration.zero) {
      return movingTime;
    }

    final Duration fallback = safeTotalTime - safeStoppedTime;
    return fallback.isNegative ? Duration.zero : fallback;
  }

  double get stoppedRatio {
    final int total = safeTotalTime.inSeconds;
    if (total <= 0) return 0.0;

    final int stopped = safeStoppedTime.inSeconds.clamp(0, total).toInt();
    return stopped / total;
  }

  Map<String, dynamic> toJson() {
    final List<Map<String, dynamic>> pointJson = points
        .map((TripPoint point) => point.toJson())
        .toList(growable: false);

    return <String, dynamic>{
      'id': id,
      'date': date.millisecondsSinceEpoch,
      'dateIso': date.toUtc().toIso8601String(),
      'totalSec': _safeSeconds(safeTotalTime),
      'stopSec': _safeSeconds(safeStoppedTime),
      'movSec': _safeSeconds(effectiveMovingTime),
      'maxSpd': _safeNonNegative(maxSpeedMph),
      'avgSpd': _safeNonNegative(avgSpeedMph),
      'altGain': _safeNonNegative(altitudeGainFt),
      'maxAlt': _safeFinite(maxAltitudeFt),
      'minAlt': _safeFinite(minAltitudeFt),
      'dist': _safeNonNegative(distanceMiles),
      'pts': pointJson,

      // Compatibility keys for Supabase/history code.
      'totalTimeSeconds': _safeSeconds(safeTotalTime),
      'stoppedSeconds': _safeSeconds(safeStoppedTime),
      'movingSeconds': _safeSeconds(effectiveMovingTime),
      'maxSpeedMph': _safeNonNegative(maxSpeedMph),
      'avgSpeedMph': _safeNonNegative(avgSpeedMph),
      'altitudeGainFt': _safeNonNegative(altitudeGainFt),
      'maxAltitudeFt': _safeFinite(maxAltitudeFt),
      'minAltitudeFt': _safeFinite(minAltitudeFt),
      'distanceMiles': _safeNonNegative(distanceMiles),
      'route_points': pointJson,
      'routeQuality': routeQualityScore,
    };
  }

  factory TripSummary.fromJson(Map<String, dynamic> json) {
    final List<TripPoint> parsedPoints = _parsePoints(
      json['pts'] ?? json['points'] ?? json['route_points'] ?? json['route'],
    );

    final DateTime date = _readDateTime(json['date'] ?? json['dateIso']);

    return TripSummary(
      id: json['id']?.toString() ?? '',
      date: date,
      totalTime: Duration(
        seconds: _readInt(json['totalSec'] ?? json['totalTimeSeconds']),
      ),
      stoppedTime: Duration(
        seconds: _readInt(json['stopSec'] ?? json['stoppedSeconds']),
      ),
      movingTime: Duration(
        seconds: _readInt(json['movSec'] ?? json['movingSeconds']),
      ),
      maxSpeedMph: _safeNonNegative(_readDouble(json['maxSpd'] ?? json['maxSpeedMph'])),
      avgSpeedMph: _safeNonNegative(_readDouble(json['avgSpd'] ?? json['avgSpeedMph'])),
      altitudeGainFt: _safeNonNegative(
        _readDouble(json['altGain'] ?? json['altitudeGainFt']),
      ),
      maxAltitudeFt: _safeFinite(_readDouble(json['maxAlt'] ?? json['maxAltitudeFt'])),
      minAltitudeFt: _safeFinite(_readDouble(json['minAlt'] ?? json['minAltitudeFt'])),
      distanceMiles: _safeNonNegative(_readDouble(json['dist'] ?? json['distanceMiles'])),
      points: parsedPoints,
    );
  }

  static TripSummary? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    try {
      final TripSummary summary = TripSummary.fromJson(
        Map<String, dynamic>.from(raw),
      );

      if (summary.id.isEmpty && summary.points.isEmpty) return null;
      return summary;
    } catch (_) {
      return null;
    }
  }

  static List<TripPoint> _parsePoints(Object? raw) {
    if (raw is! List) return const <TripPoint>[];

    final List<TripPoint> points = <TripPoint>[];

    for (final Object? item in raw) {
      final TripPoint? point = TripPoint.tryFromJson(item);
      if (point != null) points.add(point);
    }

    return List<TripPoint>.unmodifiable(points);
  }

  static String _formatDuration(Duration duration) {
    final Duration safe = duration.isNegative ? Duration.zero : duration;

    final int h = safe.inHours;
    final int m = safe.inMinutes.remainder(60);
    final int s = safe.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  static int _calculateRouteQuality(List<TripPoint> points) {
    if (points.length < 3) return 45;

    int score = 100;
    int weakAccuracy = 0;
    int duplicatePoints = 0;
    double accuracySum = 0.0;
    int accuracyCount = 0;

    double? lastLat;
    double? lastLng;

    for (final TripPoint point in points) {
      final double accuracy = point.accuracyMeters;

      if (accuracy.isFinite && accuracy > 0.0) {
        accuracySum += accuracy;
        accuracyCount++;
        if (accuracy > 35.0) weakAccuracy++;
      }

      final double lat = point.position.latitude;
      final double lng = point.position.longitude;
      if (lastLat != null &&
          lastLng != null &&
          (lat - lastLat).abs() < 0.0000001 &&
          (lng - lastLng).abs() < 0.0000001) {
        duplicatePoints++;
      }

      lastLat = lat;
      lastLng = lng;
    }

    final double avgAccuracy =
        accuracyCount == 0 ? 0.0 : accuracySum / accuracyCount;

    if (points.length < 10) score -= 16;
    if (points.length < 5) score -= 20;
    score -= (weakAccuracy * 4).clamp(0, 28).toInt();
    score -= (duplicatePoints * 3).clamp(0, 18).toInt();

    if (avgAccuracy > 10.0) score -= 6;
    if (avgAccuracy > 20.0) score -= 10;
    if (avgAccuracy > 35.0) score -= 14;

    return score.clamp(0, 100).toInt();
  }

  static String _routeQualityLabel(int score) {
    if (score >= 88) return 'Excellent';
    if (score >= 72) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Weak';
  }

  static int _safeSeconds(Duration duration) {
    return duration.isNegative ? 0 : duration.inSeconds;
  }
}

bool isValidLatLng(LatLng point) {
  return point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= -90.0 &&
      point.latitude <= 90.0 &&
      point.longitude >= -180.0 &&
      point.longitude <= 180.0;
}

double _readDouble(Object? value) {
  if (value is num) {
    final double parsed = value.toDouble();
    return parsed.isFinite ? parsed : 0.0;
  }

  if (value is String) {
    final double? parsed = double.tryParse(value.trim());
    return parsed != null && parsed.isFinite ? parsed : 0.0;
  }

  return 0.0;
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

DateTime _readDateTime(Object? value) {
  if (value is DateTime) return value;

  if (value is num) {
    final int millis = value.toInt();
    if (millis > 0) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
  }

  if (value is String) {
    final String trimmed = value.trim();

    final int? millis = int.tryParse(trimmed);
    if (millis != null && millis > 0) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }

    final DateTime? parsed = DateTime.tryParse(trimmed);
    if (parsed != null) return parsed;
  }

  return DateTime.now();
}

double _safeFinite(double value) {
  return value.isFinite ? value : 0.0;
}

double _safeNonNegative(double value) {
  if (!value.isFinite) return 0.0;
  return value < 0.0 ? 0.0 : value;
}

double _safeCoordinate(double value) {
  return value.isFinite ? value : 0.0;
}

extension TripPointUxX on TripPoint {
  String get coordinateLabel =>
      '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';

  String get speedMphLabel =>
      '${speedMph.toStringAsFixed(speedMph >= 10 ? 0 : 1)} mph';

  String get speedKmhLabel =>
      '${speedKmh.toStringAsFixed(speedKmh >= 10 ? 0 : 1)} km/h';

  bool get hasGoodAccuracy => accuracyMeters <= 0.0 || accuracyMeters <= 25.0;
}

extension TripSummaryUxX on TripSummary {
  bool get isEmptyTrip => !hasRoute && distanceMiles <= 0.0;

  double get distanceKm => distanceMiles * 1.609344;

  String get compactDistanceLabel {
    if (distanceMiles <= 0.0) return '0 mi';
    if (distanceMiles < 0.1) return '${(distanceMiles * 5280).round()} ft';
    return '${distanceMiles.toStringAsFixed(distanceMiles >= 10 ? 1 : 2)} mi';
  }

  String get compactDistanceMetricLabel {
    if (distanceKm <= 0.0) return '0 m';
    if (distanceKm < 1.0) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(distanceKm >= 10 ? 1 : 2)} km';
  }

  String get avgSpeedLabel =>
      '${avgSpeedMph.toStringAsFixed(avgSpeedMph >= 10 ? 0 : 1)} mph';

  String get maxSpeedLabel =>
      '${maxSpeedMph.toStringAsFixed(maxSpeedMph >= 10 ? 0 : 1)} mph';

  String get uxSubtitle {
    if (isEmptyTrip) return 'No route points recorded';
    return '$compactDistanceLabel · $formattedMovingTime moving · $routeQualityLabel route';
  }

  TripSummary sanitizedForUi({int maxPoints = 5000}) {
    final Iterable<TripPoint> validPoints =
        points.where((TripPoint point) => point.isValid);

    final List<TripPoint> limited = maxPoints <= 0
        ? validPoints.toList(growable: false)
        : validPoints.take(maxPoints).toList(growable: false);

    return TripSummary(
      id: id.trim(),
      date: date,
      totalTime: safeTotalTime,
      stoppedTime: safeStoppedTime,
      movingTime: effectiveMovingTime,
      maxSpeedMph: _safeNonNegative(maxSpeedMph),
      avgSpeedMph: _safeNonNegative(avgSpeedMph),
      altitudeGainFt: _safeNonNegative(altitudeGainFt),
      maxAltitudeFt: _safeFinite(maxAltitudeFt),
      minAltitudeFt: _safeFinite(minAltitudeFt),
      distanceMiles: _safeNonNegative(distanceMiles),
      points: List<TripPoint>.unmodifiable(limited),
    );
  }
}
