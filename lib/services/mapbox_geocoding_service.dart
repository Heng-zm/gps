import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/mapbox_route_models.dart';
import '../utils/app_logger.dart';

class MapboxGeocodingException implements Exception {
  const MapboxGeocodingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MapboxGeocodingService {
  const MapboxGeocodingService({
    required this.accessToken,
    this.timeout = const Duration(seconds: 12),
  });

  final String accessToken;
  final Duration timeout;

  Future<List<MapboxPlaceResult>> searchPlaces({
    required String query,
    LatLng? proximity,
    int limit = 8,
  }) async {
    final String trimmed = query.trim();

    if (trimmed.length < 2) {
      return const <MapboxPlaceResult>[];
    }

    if (accessToken.isEmpty) {
      throw const MapboxGeocodingException('Mapbox token is missing.');
    }

    final LatLng? coordinate = tryParseLatLng(trimmed);
    if (coordinate != null) {
      return <MapboxPlaceResult>[
        MapboxPlaceResult(
          name: 'Pinned coordinate',
          address:
              '${coordinate.latitude.toStringAsFixed(5)}, ${coordinate.longitude.toStringAsFixed(5)}',
          position: coordinate,
        ),
      ];
    }

    final Map<String, String> params = <String, String>{
      'access_token': accessToken,
      'limit': limit.clamp(1, 10).toString(),
      'types':
          'country,region,postcode,district,place,locality,neighborhood,address,poi',
      'language': 'en',
      'autocomplete': 'true',
      'fuzzyMatch': 'true',
    };

    if (proximity != null && isValidLatLng(proximity)) {
      params['proximity'] = '${proximity.longitude},${proximity.latitude}';
    }

    final Uri uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/'
      '${Uri.encodeComponent(trimmed)}.json',
    ).replace(queryParameters: params);

    try {
      final http.Response response = await http.get(uri).timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.err(
          'MAPBOX',
          'Geocoding API returned ${response.statusCode}',
          data: response.body,
        );
        throw MapboxGeocodingException(
          'Location search failed (${response.statusCode}).',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MapboxGeocodingException(
          'Location search response was invalid.',
        );
      }

      final List<dynamic> features =
          decoded['features'] as List<dynamic>? ?? <dynamic>[];

      final List<MapboxPlaceResult> results = <MapboxPlaceResult>[];
      final Set<String> seen = <String>{};

      for (final dynamic item in features) {
        if (item is! Map<String, dynamic>) continue;

        final String name =
            (item['text'] ?? item['place_name'] ?? '').toString().trim();
        final String address = (item['place_name'] ?? '').toString().trim();
        final List<dynamic> center = item['center'] as List<dynamic>? ?? [];

        if (name.isEmpty || center.length < 2) continue;

        final double? lng = (center[0] as num?)?.toDouble();
        final double? lat = (center[1] as num?)?.toDouble();

        if (lat == null || lng == null) continue;

        final LatLng position = LatLng(lat, lng);
        if (!isValidLatLng(position)) continue;

        final String key =
            '${name.toLowerCase()}|${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
        if (!seen.add(key)) continue;

        results.add(
          MapboxPlaceResult(
            name: name,
            address: address,
            position: position,
          ),
        );
      }

      return List<MapboxPlaceResult>.unmodifiable(results);
    } on TimeoutException {
      throw const MapboxGeocodingException('Location search timed out.');
    } on MapboxGeocodingException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.err(
        'MAPBOX',
        'Geocoding search failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const MapboxGeocodingException('Location search failed.');
    }
  }
}
