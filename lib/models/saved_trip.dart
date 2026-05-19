import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'trip_data.dart';

/// One saved route point stored inside saved_trips.route_points jsonb.
///
/// Expected Supabase JSON format:
/// {
///   "lat": 11.5564,
///   "lng": 104.9282,
///   "spd": 12.5
/// }
class SavedRoutePoint {
  const SavedRoutePoint({
    required this.lat,
    required this.lng,
    required this.speedMph,
    this.altitudeFt = 0.0,
    this.timestamp,
    this.accuracyMeters = 0.0,
  });

  final double lat;
  final double lng;
  final double speedMph;
  final double altitudeFt;
  final DateTime? timestamp;
  final double accuracyMeters;

  bool get isValid {
    return lat.isFinite &&
        lng.isFinite &&
        lat.abs() <= 90.0 &&
        lng.abs() <= 180.0;
  }

  LatLng get position => LatLng(lat, lng);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      // Coordinates can be negative. Do not use non-negative sanitizers here.
      'lat': _safeFinite(lat),
      'lng': _safeFinite(lng),
      'spd': _safeNonNegative(speedMph),
      if (altitudeFt.isFinite && altitudeFt != 0.0) 'altFt': altitudeFt,
      if (timestamp != null) 'time': timestamp!.millisecondsSinceEpoch,
      if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
      if (accuracyMeters.isFinite && accuracyMeters > 0.0)
        'acc': accuracyMeters,
    };
  }

  TripPoint toTripPoint() {
    return TripPoint(
      position: position,
      speedMph: _safeNonNegative(speedMph),
      altitudeFt: _safeFinite(altitudeFt),
      timestamp: timestamp ?? DateTime.now(),
      accuracyMeters: _safeNonNegative(accuracyMeters),
    );
  }

  static SavedRoutePoint? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    final double lat = _toDouble(raw['lat'] ?? raw['latitude']);
    final double lng = _toDouble(raw['lng'] ?? raw['lon'] ?? raw['longitude']);
    final double speed = _toDouble(
      raw['spd'] ?? raw['speedMph'] ?? raw['speed'] ?? raw['speed_mph'],
    );
    final double altitude = _toDouble(
      raw['altFt'] ?? raw['altitudeFt'] ?? raw['alt'] ?? raw['altitude_ft'],
    );
    final DateTime? timestamp = _tryRouteDateTime(
      raw['time'] ?? raw['timestamp'] ?? raw['ts'],
    );
    final double accuracy = _toDouble(
      raw['acc'] ??
          raw['accuracyMeters'] ??
          raw['accuracy'] ??
          raw['accuracy_m'],
    );

    final SavedRoutePoint point = SavedRoutePoint(
      lat: lat,
      lng: lng,
      speedMph: _safeNonNegative(speed),
      altitudeFt: _safeFinite(altitude),
      timestamp: timestamp,
      accuracyMeters: _safeNonNegative(accuracy),
    );

    return point.isValid ? point : null;
  }
}

/// Model representing a trip stored in Supabase cloud storage.
class SavedTrip {
  SavedTrip({
    required this.id,
    required this.date,
    required this.distanceMiles,
    required this.maxSpeedMph,
    required this.avgSpeedMph,
    required this.totalTime,
    required this.altitudeGainFt,
    this.routePoints = const <SavedRoutePoint>[],
  });

  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;
  final List<SavedRoutePoint> routePoints;

  /// Pre-calculated formatters to avoid repeated work during history scrolling.
  late final String formattedDate =
      DateFormat('MMM d, yyyy · h:mm a').format(date);

  late final String formattedDuration = _calculateFormattedDuration();

  int get pointCount => routePoints.length;

  bool get hasRoute => routePoints.length >= 2;

  List<TripPoint> get tripPoints {
    if (routePoints.isEmpty) return const <TripPoint>[];

    return routePoints
        .where((SavedRoutePoint point) => point.isValid)
        .map((SavedRoutePoint point) => point.toTripPoint())
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'date': date.millisecondsSinceEpoch,
      'dateIso': date.toUtc().toIso8601String(),
      'distanceMiles': _safeNonNegative(distanceMiles),
      'maxSpeedMph': _safeNonNegative(maxSpeedMph),
      'avgSpeedMph': _safeNonNegative(avgSpeedMph),
      'totalTimeSeconds': totalTime.inSeconds < 0 ? 0 : totalTime.inSeconds,
      'altitudeGainFt': _safeNonNegative(altitudeGainFt),
      'route_points': routePoints
          .where((SavedRoutePoint point) => point.isValid)
          .map((SavedRoutePoint point) => point.toJson())
          .toList(growable: false),
    };
  }

  static SavedTrip? tryFromJson(Map<String, dynamic> json) {
    final String id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      debugPrint('SavedTrip.tryFromJson: missing id, skipping.');
      return null;
    }

    final int? rawDate = _tryDateMillis(json['date'] ?? json['dateIso']);
    if (rawDate == null || rawDate <= 0) {
      debugPrint('SavedTrip.tryFromJson: missing or zero date, skipping.');
      return null;
    }

    return SavedTrip(
      id: id,
      date: DateTime.fromMillisecondsSinceEpoch(rawDate),
      distanceMiles: _safeNonNegative(_toDouble(json['distanceMiles'])),
      maxSpeedMph: _safeNonNegative(_toDouble(json['maxSpeedMph'])),
      avgSpeedMph: _safeNonNegative(_toDouble(json['avgSpeedMph'])),
      totalTime: Duration(
        seconds: _toInt(json['totalTimeSeconds']).clamp(0, 1 << 31).toInt(),
      ),
      altitudeGainFt: _safeNonNegative(_toDouble(json['altitudeGainFt'])),
      routePoints: _parseRoutePoints(json['route_points']),
    );
  }

  factory SavedTrip.fromSummary(TripSummary summary) {
    final List<SavedRoutePoint> points = summary.points
        .map((TripPoint point) {
          return SavedRoutePoint(
            lat: point.position.latitude,
            lng: point.position.longitude,
            speedMph: point.speedMph,
            altitudeFt: point.altitudeFt,
            timestamp: point.timestamp,
            accuracyMeters: point.accuracyMeters,
          );
        })
        .where((SavedRoutePoint point) => point.isValid)
        .toList(growable: false);

    return SavedTrip(
      id: summary.id,
      date: summary.date,
      distanceMiles: _safeNonNegative(summary.distanceMiles),
      maxSpeedMph: _safeNonNegative(summary.maxSpeedMph),
      avgSpeedMph: _safeNonNegative(summary.avgSpeedMph),
      totalTime:
          summary.totalTime.isNegative ? Duration.zero : summary.totalTime,
      altitudeGainFt: _safeNonNegative(summary.altitudeGainFt),
      routePoints: points,
    );
  }

  String _calculateFormattedDuration() {
    final Duration safe = totalTime.isNegative ? Duration.zero : totalTime;

    final int h = safe.inHours;
    final int m = safe.inMinutes.remainder(60);
    final int s = safe.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STATIC SUPABASE METHODS
  // ───────────────────────────────────────────────────────────────────────────

  static Future<bool> saveTrip(SavedTrip trip) async {
    try {
      await Supabase.instance.client
          .from('saved_trips')
          .upsert(trip.toJson(), onConflict: 'id');

      return true;
    } catch (error, stackTrace) {
      debugPrint('Supabase Save Error: $error\n$stackTrace');
      return false;
    }
  }

  static Future<List<SavedTrip>> loadAllTrips() async {
    try {
      final List<dynamic> data = await Supabase.instance.client
          .from('saved_trips')
          .select()
          .order('date', ascending: false);

      final List<SavedTrip> trips = <SavedTrip>[];

      for (final Object? row in data) {
        try {
          if (row is! Map) continue;

          final SavedTrip? trip = SavedTrip.tryFromJson(
            Map<String, dynamic>.from(row),
          );

          if (trip != null) trips.add(trip);
        } catch (error, stackTrace) {
          debugPrint(
            'Skipped corrupted saved_trip record: $error\n$stackTrace',
          );
        }
      }

      return trips;
    } catch (error, stackTrace) {
      debugPrint('Supabase Load Error: $error\n$stackTrace');
      return <SavedTrip>[];
    }
  }

  static Future<SavedTrip?> loadTrip(String id) async {
    final String safeId = id.trim();
    if (safeId.isEmpty) return null;

    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('saved_trips')
          .select()
          .eq('id', safeId)
          .maybeSingle();

      if (row == null) return null;

      return SavedTrip.tryFromJson(row);
    } catch (error, stackTrace) {
      debugPrint('Supabase Load Trip Error: $error\n$stackTrace');
      return null;
    }
  }

  static Future<bool> deleteTrip(String id) async {
    final String safeId = id.trim();
    if (safeId.isEmpty) return false;

    try {
      await Supabase.instance.client
          .from('saved_trips')
          .delete()
          .eq('id', safeId);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Supabase Delete Error: $error\n$stackTrace');
      return false;
    }
  }

  static List<SavedRoutePoint> _parseRoutePoints(Object? raw) {
    if (raw is! List) return const <SavedRoutePoint>[];

    final List<SavedRoutePoint> points = <SavedRoutePoint>[];

    for (final Object? item in raw) {
      final SavedRoutePoint? point = SavedRoutePoint.tryFromJson(item);
      if (point != null) points.add(point);
    }

    return List<SavedRoutePoint>.unmodifiable(points);
  }

  static int? _tryDateMillis(Object? raw) {
    if (raw is num) return raw.toInt();

    if (raw is String) {
      final String trimmed = raw.trim();

      final int? asInt = int.tryParse(trimmed);
      if (asInt != null) return asInt;

      final DateTime? parsed = DateTime.tryParse(trimmed);
      return parsed?.millisecondsSinceEpoch;
    }

    return null;
  }

  static int _toInt(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }
}

DateTime? _tryRouteDateTime(Object? raw) {
  int? millis;

  if (raw is num) {
    millis = raw.toInt();
  } else if (raw is String) {
    final String trimmed = raw.trim();
    millis = int.tryParse(trimmed);
    if (millis == null) {
      final DateTime? parsed = DateTime.tryParse(trimmed);
      millis = parsed?.millisecondsSinceEpoch;
    }
  }

  if (millis == null || millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

double _toDouble(Object? raw) {
  if (raw is num) {
    final double value = raw.toDouble();
    return value.isFinite ? value : 0.0;
  }

  if (raw is String) {
    final double? value = double.tryParse(raw.trim());
    return value != null && value.isFinite ? value : 0.0;
  }

  return 0.0;
}

double _safeFinite(double value) {
  return value.isFinite ? value : 0.0;
}

double _safeNonNegative(double value) {
  if (!value.isFinite) return 0.0;
  return value < 0.0 ? 0.0 : value;
}
