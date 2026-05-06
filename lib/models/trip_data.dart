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

  factory TripPoint.fromJson(Map<String, dynamic> json) => TripPoint(
        position: LatLng(
          (json['lat'] as num? ?? 0.0).toDouble(),
          (json['lng'] as num? ?? 0.0).toDouble(),
        ),
        speedMph: (json['speed'] as num? ?? 0.0).toDouble(),
        altitudeFt: (json['alt'] as num? ?? 0.0).toDouble(),
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['time'] as int? ?? 0),
        accuracyMeters: (json['acc'] as num? ?? 0.0).toDouble(),
      );
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

  const TripSummary({
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

  // --- Formatting Getters ---

  String get formattedTotalTime => _formatDuration(totalTime);
  String get formattedStoppedTime => _formatDuration(stoppedTime);
  String get formattedMovingTime => _formatDuration(movingTime);

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

  /// FIX: Added missing factory to allow HistoryScreen to load saved data
  factory TripSummary.fromJson(Map<String, dynamic> json) {
    var ptsList = (json['pts'] as List? ?? []);

    return TripSummary(
      id: json['id'] as String? ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int? ?? 0),
      totalTime: Duration(seconds: json['totalSec'] as int? ?? 0),
      stoppedTime: Duration(seconds: json['stopSec'] as int? ?? 0),
      movingTime: Duration(seconds: json['movSec'] as int? ?? 0),
      maxSpeedMph: (json['maxSpd'] as num? ?? 0.0).toDouble(),
      avgSpeedMph: (json['avgSpd'] as num? ?? 0.0).toDouble(),
      altitudeGainFt: (json['altGain'] as num? ?? 0.0).toDouble(),
      maxAltitudeFt: (json['maxAlt'] as num? ?? 0.0).toDouble(),
      minAltitudeFt: (json['minAlt'] as num? ?? 0.0).toDouble(),
      distanceMiles: (json['dist'] as num? ?? 0.0).toDouble(),
      points: ptsList
          .map((p) => TripPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}
