import 'package:latlong2/latlong.dart';

/// Represents a single GPS data point captured during a trip.
class TripPoint {
  final LatLng position;
  final double speedMph;
  final double altitudeFt;
  final DateTime timestamp;
  final double accuracyMeters;

  const TripPoint({
    required this.position,
    required this.speedMph,
    required this.altitudeFt,
    required this.timestamp,
    required this.accuracyMeters,
  });

  Map<String, dynamic> toJson() => {
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': speedMph,
        'alt': altitudeFt,
        'time': timestamp.millisecondsSinceEpoch,
        'acc': accuracyMeters,
      };

  factory TripPoint.fromJson(Map<String, dynamic> json) {
    return TripPoint(
      position: LatLng(
        (json['lat'] as num?)?.toDouble() ?? 0.0,
        (json['lng'] as num?)?.toDouble() ?? 0.0,
      ),
      speedMph: (json['speed'] as num?)?.toDouble() ?? 0.0,
      altitudeFt: (json['alt'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['time'] as num?)?.toInt() ?? 0,
      ),
      accuracyMeters: (json['acc'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Represents the completed statistics and path of a recorded journey.
class TripSummary {
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

  // PERFORMANCE: Cached formatters.
  // These run only once per trip, preventing lag during list scrolling.
  late final String formattedTotalTime = _formatDuration(totalTime);
  late final String formattedStoppedTime = _formatDuration(stoppedTime);
  late final String formattedMovingTime = _formatDuration(movingTime);

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
    required this.points,
  });

  static String _formatDuration(Duration d) {
    if (d.isNegative) return "0s";
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    if (m > 0) {
      return '${m}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  // --- Serialization ---

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'totalSec': totalTime.inSeconds,
        'stopSec': stoppedTime.inSeconds,
        'movSec': movingTime.inSeconds,
        'maxSpd': maxSpeedMph,
        'avgSpd': avgSpeedMph,
        'altGain': altitudeGainFt,
        'maxAlt': maxAltitudeFt,
        'minAlt': minAltitudeFt,
        'dist': distanceMiles,
        'pts': points.map((p) => p.toJson()).toList(),
      };

  // BUG FIX: Uses num type-casting for safe JSON decoding from Supabase/Cloud sources.
  factory TripSummary.fromJson(Map<String, dynamic> json) {
    // Optimized list parsing
    final ptsRaw = json['pts'] as List? ?? [];
    final parsedPoints = ptsRaw
        .map((p) => TripPoint.fromJson(p as Map<String, dynamic>))
        .toList(growable: false);

    return TripSummary(
      id: json['id']?.toString() ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(
        (json['date'] as num?)?.toInt() ?? 0,
      ),
      totalTime: Duration(
        seconds: (json['totalSec'] as num?)?.toInt() ?? 0,
      ),
      stoppedTime: Duration(
        seconds: (json['stopSec'] as num?)?.toInt() ?? 0,
      ),
      movingTime: Duration(
        seconds: (json['movSec'] as num?)?.toInt() ?? 0,
      ),
      maxSpeedMph: (json['maxSpd'] as num?)?.toDouble() ?? 0.0,
      avgSpeedMph: (json['avgSpd'] as num?)?.toDouble() ?? 0.0,
      altitudeGainFt: (json['altGain'] as num?)?.toDouble() ?? 0.0,
      maxAltitudeFt: (json['maxAlt'] as num?)?.toDouble() ?? 0.0,
      minAltitudeFt: (json['minAlt'] as num?)?.toDouble() ?? 0.0,
      distanceMiles: (json['dist'] as num?)?.toDouble() ?? 0.0,
      points: parsedPoints,
    );
  }
}
