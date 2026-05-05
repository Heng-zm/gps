import 'package:latlong2/latlong.dart';

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
            (json['lat'] as num).toDouble(), (json['lng'] as num).toDouble()),
        speedMph: (json['speed'] as num).toDouble(),
        altitudeFt: (json['alt'] as num).toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
        accuracyMeters: (json['acc'] as num).toDouble(),
      );
}

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

  String get formattedTotalTime => _formatDuration(totalTime);
  String get formattedStoppedTime => _formatDuration(stoppedTime);

  static String _formatDuration(Duration d) {
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
}
