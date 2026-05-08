import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Model representing a trip stored in Supabase cloud storage.
class SavedTrip {
  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;

  // PERFORMANCE: Pre-calculate formatters so they don't run during list scrolling.
  late final String formattedDate =
      DateFormat('MMM d, yyyy · h:mm a').format(date);
  late final String formattedDuration = _calculateFormattedDuration();

  SavedTrip({
    required this.id,
    required this.date,
    required this.distanceMiles,
    required this.maxSpeedMph,
    required this.avgSpeedMph,
    required this.totalTime,
    required this.altitudeGainFt,
  });

  /// Converts model to JSON for Supabase insertion.
  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'distanceMiles': distanceMiles,
        'maxSpeedMph': maxSpeedMph,
        'avgSpeedMph': avgSpeedMph,
        'totalTimeSeconds': totalTime.inSeconds,
        'altitudeGainFt': altitudeGainFt,
      };

  /// Creates a model from Supabase JSON response.
  /// Uses [num] to handle potential int/double type mismatches from the database.
  /// FIX: Returns null instead of a silently broken object when 'date' is
  /// missing or zero (which previously produced a Jan 1 1970 trip).
  static SavedTrip? tryFromJson(Map<String, dynamic> json) {
    final rawDate = (json['date'] as num?)?.toInt();
    if (rawDate == null || rawDate == 0) {
      debugPrint('SavedTrip.tryFromJson: missing or zero date, skipping.');
      return null;
    }
    return SavedTrip(
      id: json['id']?.toString() ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(rawDate),
      distanceMiles: (json['distanceMiles'] as num?)?.toDouble() ?? 0.0,
      maxSpeedMph: (json['maxSpeedMph'] as num?)?.toDouble() ?? 0.0,
      avgSpeedMph: (json['avgSpeedMph'] as num?)?.toDouble() ?? 0.0,
      totalTime:
          Duration(seconds: (json['totalTimeSeconds'] as num?)?.toInt() ?? 0),
      altitudeGainFt: (json['altitudeGainFt'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// FIX: Shows seconds when duration is under 1 minute so a 45-second trip
  /// no longer displays as '0m'.
  String _calculateFormattedDuration() {
    final h = totalTime.inHours;
    final m = totalTime.inMinutes.remainder(60);
    final s = totalTime.inSeconds.remainder(60);
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    if (m > 0) {
      return '${m}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  // ─── STATIC SUPABASE METHODS ───

  /// FIX: Uses upsert instead of insert so saving the same trip ID twice
  /// updates the existing record rather than throwing a duplicate-key error.
  static Future<bool> saveTrip(SavedTrip trip) async {
    try {
      await Supabase.instance.client
          .from('saved_trips')
          .upsert(trip.toJson(), onConflict: 'id');
      return true;
    } catch (e) {
      debugPrint('Supabase Save Error: $e');
      return false;
    }
  }

  /// Fetches all trips from Supabase ordered by date (newest first).
  /// FIX: Uses tryFromJson so records with missing/zero dates are skipped
  /// cleanly instead of producing silent Jan-1-1970 entries in the list.
  static Future<List<SavedTrip>> loadAllTrips() async {
    try {
      final data = await Supabase.instance.client
          .from('saved_trips')
          .select()
          .order('date', ascending: false);

      final List<SavedTrip> trips = [];
      for (final row in data) {
        try {
          final trip = SavedTrip.tryFromJson(row);
          if (trip != null) trips.add(trip);
        } catch (e) {
          debugPrint('Skipped corrupted record: $e');
        }
      }
      return trips;
    } catch (e) {
      debugPrint('Supabase Load Error: $e');
      return [];
    }
  }

  /// Deletes a specific trip from Supabase by its ID.
  static Future<bool> deleteTrip(String id) async {
    try {
      await Supabase.instance.client.from('saved_trips').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Supabase Delete Error: $e');
      return false;
    }
  }
}
