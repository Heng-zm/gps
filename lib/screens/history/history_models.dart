part of 'history_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════

const Color _kBg = Color(0xFF000000);
const Color _kSurface = Color(0xFF111114);
const Color _kSurface2 = Color(0xFF17171B);
const Color _kBorder = Color(0xFF29292E);
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD54F);
const Color _kGreen = Color(0xFF32D74B);
const Color _kRed = Color(0xFFFF3B30);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kCyan = Color(0xFF22D3EE);
const Color _kPurple = Color(0xFF8B5CF6);
const Color _kMuted = Color(0xFF777777);

const LatLng _kFallbackCenter = LatLng(11.5564, 104.9282);
const double _kFallbackZoom = 13.0;
const double _kDefaultReplayZoom = 16.0;
const double _kMinZoom = 3.0;
const double _kMaxZoom = 19.0;
const Duration _kReplayFrame = Duration(milliseconds: 33);

// ═══════════════════════════════════════════════════════════════════════════════
// TRIP EXPORT FORMATS
// ═══════════════════════════════════════════════════════════════════════════════

enum TripExportFormat { gpx, kml, csv, json, txt }

extension TripExportFormatX on TripExportFormat {
  String get label {
    switch (this) {
      case TripExportFormat.gpx:
        return 'GPX';
      case TripExportFormat.kml:
        return 'KML';
      case TripExportFormat.csv:
        return 'CSV';
      case TripExportFormat.json:
        return 'JSON';
      case TripExportFormat.txt:
        return 'Summary TXT';
    }
  }

  String get extensionName {
    switch (this) {
      case TripExportFormat.gpx:
        return 'gpx';
      case TripExportFormat.kml:
        return 'kml';
      case TripExportFormat.csv:
        return 'csv';
      case TripExportFormat.json:
        return 'json';
      case TripExportFormat.txt:
        return 'txt';
    }
  }

  String get description {
    switch (this) {
      case TripExportFormat.gpx:
        return 'Best for GPS apps and route import.';
      case TripExportFormat.kml:
        return 'Best for Google Earth and map viewers.';
      case TripExportFormat.csv:
        return 'Best for spreadsheets and analysis.';
      case TripExportFormat.json:
        return 'Best for backup and developers.';
      case TripExportFormat.txt:
        return 'Best for sharing a clean trip summary.';
    }
  }

  IconData get icon {
    switch (this) {
      case TripExportFormat.gpx:
        return CupertinoIcons.location_fill;
      case TripExportFormat.kml:
        return CupertinoIcons.map_fill;
      case TripExportFormat.csv:
        return CupertinoIcons.table;
      case TripExportFormat.json:
        return CupertinoIcons.doc_text_fill;
      case TripExportFormat.txt:
        return CupertinoIcons.text_alignleft;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class SavedRoutePoint {
  const SavedRoutePoint({
    required this.lat,
    required this.lng,
    required this.speedMph,
  });

  final double lat;
  final double lng;
  final double speedMph;

  bool get isValid {
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lng >= -180.0 &&
        lng <= 180.0;
  }

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'spd': speedMph,
    };
  }

  factory SavedRoutePoint.fromJson(Map<String, dynamic> json) {
    final double parsedLat = _readDouble(
      json['lat'] ?? json['latitude'] ?? json['y'],
    );
    final double parsedLng = _readDouble(
      json['lng'] ?? json['lon'] ?? json['longitude'] ?? json['x'],
    );
    final double parsedSpeed = _readDouble(
      json['spd'] ?? json['speedMph'] ?? json['speed'] ?? json['speed_mph'],
    );

    return SavedRoutePoint(
      lat: parsedLat,
      lng: parsedLng,
      speedMph: parsedSpeed.isFinite && parsedSpeed > 0.0 ? parsedSpeed : 0.0,
    );
  }

  static double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
  }
}

class SavedTrip {
  SavedTrip({
    required this.id,
    required this.date,
    required this.distanceMiles,
    required this.maxSpeedMph,
    required this.avgSpeedMph,
    required this.totalTime,
    required this.altitudeGainFt,
    required List<SavedRoutePoint> route,
  }) : route = List<SavedRoutePoint>.unmodifiable(
          route.where((SavedRoutePoint point) => point.isValid),
        );

  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;
  final List<SavedRoutePoint> route;

  late final String formattedDate =
      DateFormat('MMM d, yyyy · h:mm a').format(date);
  late final String formattedDateShort = DateFormat('MMM d, yyyy').format(date);
  late final String formattedDuration = _formatDuration(totalTime);

  bool get hasRoute => route.length >= 2;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'date': date.millisecondsSinceEpoch,
      'distanceMiles': distanceMiles,
      'maxSpeedMph': maxSpeedMph,
      'avgSpeedMph': avgSpeedMph,
      'totalTimeSeconds': totalTime.inSeconds,
      'altitudeGainFt': altitudeGainFt,
      'route_points': route.map((SavedRoutePoint p) => p.toJson()).toList(),
    };
  }

  static SavedTrip? tryFromJson(Map<String, dynamic> json) {
    try {
      final String id = (json['id'] ?? '').toString().trim();
      if (id.isEmpty) return null;

      final int? rawDate = _readInt(json['date'] ?? json['created_at_ms']);
      final DateTime date = rawDate != null && rawDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(rawDate)
          : _readDateTime(json['created_at'] ?? json['inserted_at']) ??
              DateTime.now();

      return SavedTrip(
        id: id,
        date: date,
        distanceMiles: _readDouble(
          json['distanceMiles'] ?? json['distance_miles'] ?? json['distance'],
        ),
        maxSpeedMph: _readDouble(
          json['maxSpeedMph'] ?? json['max_speed_mph'] ?? json['maxSpeed'],
        ),
        avgSpeedMph: _readDouble(
          json['avgSpeedMph'] ?? json['avg_speed_mph'] ?? json['avgSpeed'],
        ),
        totalTime: Duration(
          seconds: math.max(
            0,
            _readInt(
                  json['totalTimeSeconds'] ??
                      json['total_time_seconds'] ??
                      json['durationSeconds'],
                ) ??
                0,
          ),
        ),
        altitudeGainFt: _readDouble(
          json['altitudeGainFt'] ??
              json['altitude_gain_ft'] ??
              json['altitudeGain'],
        ),
        route: _parseRoute(
            json['route_points'] ?? json['route'] ?? json['points']),
      );
    } catch (error, stackTrace) {
      debugPrint('SavedTrip.tryFromJson failed: $error\n$stackTrace');
      return null;
    }
  }

  static Future<bool> saveTrip(SavedTrip trip) async {
    try {
      await Supabase.instance.client
          .from('saved_trips')
          .upsert(trip.toJson(), onConflict: 'id');
      return true;
    } catch (error, stackTrace) {
      debugPrint('Supabase saveTrip error: $error\n$stackTrace');
      return false;
    }
  }

  static Future<({List<SavedTrip> trips, String? error})> loadAllTrips() async {
    try {
      final dynamic data = await Supabase.instance.client
          .from('saved_trips')
          .select()
          .order('date', ascending: false);

      if (data is! List) {
        return (trips: const <SavedTrip>[], error: null);
      }

      final List<SavedTrip> trips = <SavedTrip>[];
      for (final Object? row in data) {
        if (row is Map<String, dynamic>) {
          final SavedTrip? trip = SavedTrip.tryFromJson(row);
          if (trip != null) trips.add(trip);
        } else if (row is Map) {
          final SavedTrip? trip =
              SavedTrip.tryFromJson(Map<String, dynamic>.from(row));
          if (trip != null) trips.add(trip);
        }
      }

      return (trips: List<SavedTrip>.unmodifiable(trips), error: null);
    } catch (error, stackTrace) {
      debugPrint('Supabase loadAllTrips error: $error\n$stackTrace');
      return (
        trips: const <SavedTrip>[],
        error: 'Could not load trips. Check your connection.',
      );
    }
  }

  static Future<bool> deleteTrip(String id) async {
    if (id.trim().isEmpty) return false;

    try {
      await Supabase.instance.client.from('saved_trips').delete().eq('id', id);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Supabase deleteTrip error: $error\n$stackTrace');
      return false;
    }
  }

  static List<SavedRoutePoint> _parseRoute(Object? value) {
    if (value is! List) return const <SavedRoutePoint>[];

    final List<SavedRoutePoint> points = <SavedRoutePoint>[];
    for (final Object? item in value) {
      SavedRoutePoint? point;

      if (item is Map<String, dynamic>) {
        point = SavedRoutePoint.fromJson(item);
      } else if (item is Map) {
        point = SavedRoutePoint.fromJson(Map<String, dynamic>.from(item));
      }

      if (point != null && point.isValid) {
        if (points.isEmpty ||
            points.last.lat != point.lat ||
            points.last.lng != point.lng) {
          points.add(point);
        }
      }
    }

    return List<SavedRoutePoint>.unmodifiable(points);
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double _readDouble(Object? value) {
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

  static DateTime? _readDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _formatDuration(Duration duration) {
    final int seconds = math.max(0, duration.inSeconds);
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;

    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    if (minutes > 0) return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
    return '${secs}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
