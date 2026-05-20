import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/mapbox_route_models.dart';

class MapboxDirectionsException implements Exception {
  const MapboxDirectionsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MapboxDirectionsService {
  const MapboxDirectionsService({
    required this.accessToken,
    this.timeout = const Duration(seconds: 15),
  });

  final String accessToken;
  final Duration timeout;

  Future<PlannedRoute> planRoute({
    required LatLng start,
    required LatLng destination,
    required DirectionsProfile profile,
  }) async {
    if (accessToken.trim().isEmpty) {
      throw const MapboxDirectionsException('Mapbox token is missing.');
    }

    if (!isValidLatLng(start)) {
      throw const MapboxDirectionsException('Start position is invalid.');
    }

    if (!isValidLatLng(destination)) {
      throw const MapboxDirectionsException('Destination coordinate is invalid.');
    }

    final Uri uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/\${profile.apiProfile}/'
      '\${start.longitude},\${start.latitude};'
      '\${destination.longitude},\${destination.latitude}',
    ).replace(
      queryParameters: <String, String>{
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
        'access_token': accessToken.trim(),
      },
    );

    try {
      final http.Response response = await http.get(uri).timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'MapboxDirectionsService status \${response.statusCode}: '
          '\${_shortBody(response.body)}',
        );
        throw MapboxDirectionsException(
          'Route planning failed (\${response.statusCode}).',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MapboxDirectionsException(
          'Route planning response was invalid.',
        );
      }

      final List<dynamic> routes =
          decoded['routes'] as List<dynamic>? ?? <dynamic>[];
      if (routes.isEmpty || routes.first is! Map) {
        throw const MapboxDirectionsException('No route found.');
      }

      final Map<String, dynamic> route =
          Map<String, dynamic>.from(routes.first as Map);

      final Map<String, dynamic> geometry = route['geometry'] is Map
          ? Map<String, dynamic>.from(route['geometry'] as Map)
          : <String, dynamic>{};

      final List<dynamic> coordinates =
          geometry['coordinates'] as List<dynamic>? ?? <dynamic>[];

      final List<LatLng> points = <LatLng>[];

      for (final Object? coordinate in coordinates) {
        if (coordinate is! List || coordinate.length < 2) continue;

        final double? lng = _asDoubleOrNull(coordinate[0]);
        final double? lat = _asDoubleOrNull(coordinate[1]);
        if (lat == null || lng == null) continue;

        final LatLng point = LatLng(lat, lng);
        if (isValidLatLng(point)) points.add(point);
      }

      if (points.length < 2) {
        throw const MapboxDirectionsException('Route has no usable geometry.');
      }

      return PlannedRoute(
        points: List<LatLng>.unmodifiable(points),
        distanceMeters: _asDouble(route['distance']),
        durationSeconds: _asDouble(route['duration']),
        profile: profile,
      );
    } on TimeoutException {
      throw const MapboxDirectionsException('Route planning timed out.');
    } on MapboxDirectionsException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('MapboxDirectionsService failed: \$error\n\$stackTrace');
      throw const MapboxDirectionsException('Route planning failed.');
    }
  }

  static double _asDouble(Object? value) {
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

  static String _shortBody(String value) {
    final String trimmed = value.trim();
    if (trimmed.length <= 300) return trimmed;
    return '\${trimmed.substring(0, 300)}...';
  }
}
