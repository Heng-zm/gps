import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/mapbox_route_models.dart';

class MapboxGeocodingException implements Exception {
  const MapboxGeocodingException(
    this.message, {
    this.statusCode,
  });

  final String message;
  final int? statusCode;

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

    if (accessToken.trim().isEmpty) {
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
      'access_token': accessToken.trim(),
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
        final String shortBody = _shortBody(response.body);
        debugPrint(
          'MapboxGeocodingService status ${response.statusCode}: $shortBody',
        );

        throw MapboxGeocodingException(
          _friendlyStatusMessage(
            response.statusCode,
            fallback: 'Location search failed. Please try again.',
          ),
          statusCode: response.statusCode,
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

      for (final Object? item in features) {
        if (item is! Map) continue;
        final Map<String, dynamic> feature = Map<String, dynamic>.from(item);

        final String name =
            (feature['text'] ?? feature['place_name'] ?? '').toString().trim();
        final String address =
            (feature['place_name'] ?? '').toString().trim();

        final List<dynamic> center =
            feature['center'] as List<dynamic>? ?? <dynamic>[];

        if (name.isEmpty || center.length < 2) continue;

        final double? lng = _asDoubleOrNull(center[0]);
        final double? lat = _asDoubleOrNull(center[1]);
        if (lat == null || lng == null) continue;

        final LatLng position = LatLng(lat, lng);
        if (!isValidLatLng(position)) continue;

        final String key =
            '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}:$name';
        if (!seen.add(key)) continue;

        results.add(
          MapboxPlaceResult(
            name: name,
            address: address.isEmpty ? name : address,
            position: position,
          ),
        );

        if (results.length >= limit.clamp(1, 10)) break;
      }

      return List<MapboxPlaceResult>.unmodifiable(results);
    } on TimeoutException {
      throw const MapboxGeocodingException('Location search timed out.');
    } on MapboxGeocodingException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('MapboxGeocodingService failed: $error\n$stackTrace');
      throw const MapboxGeocodingException('Location search failed.');
    }
  }

  static LatLng? tryParseLatLng(String value) {
    final String normalized = value
        .replaceAll(';', ',')
        .replaceAll('|', ',')
        .replaceAll(RegExp(r'\s+'), ',');

    final List<String> parts = normalized
        .split(',')
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.length < 2) return null;

    final double? lat = double.tryParse(parts[0]);
    final double? lng = double.tryParse(parts[1]);

    if (lat == null || lng == null) return null;

    final LatLng point = LatLng(lat, lng);
    return isValidLatLng(point) ? point : null;
  }

  static double? _asDoubleOrNull(Object? value) {
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : null;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value.trim());
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }

  static String _friendlyStatusMessage(
    int statusCode, {
    required String fallback,
  }) {
    switch (statusCode) {
      case 401:
      case 403:
        return 'Mapbox token is invalid or not allowed for search.';
      case 404:
        return 'No location search endpoint was found.';
      case 422:
        return 'Search text is invalid. Try a place name or coordinates.';
      case 429:
        return 'Mapbox search limit reached. Please wait and try again.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'Mapbox search server is busy. Please try again soon.';
      default:
        return '$fallback ($statusCode)';
    }
  }

  static String _shortBody(String value) {
    final String trimmed = value.trim();
    if (trimmed.length <= 300) return trimmed;
    return '${trimmed.substring(0, 300)}...';
  }
}
