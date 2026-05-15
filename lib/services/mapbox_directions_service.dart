import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/mapbox_route_models.dart';
import '../utils/app_logger.dart';

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
    if (accessToken.isEmpty) {
      throw const MapboxDirectionsException('Mapbox token is missing.');
    }

    if (!isValidLatLng(start)) {
      throw const MapboxDirectionsException('Start position is invalid.');
    }

    if (!isValidLatLng(destination)) {
      throw const MapboxDirectionsException('Destination coordinate is invalid.');
    }

    final Uri uri = Uri.parse(
      'https://api.mapbox.com/directions/v5/${profile.apiProfile}/'
      '${start.longitude},${start.latitude};'
      '${destination.longitude},${destination.latitude}',
    ).replace(
      queryParameters: <String, String>{
        'alternatives': 'false',
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'false',
        'access_token': accessToken,
      },
    );

    try {
      final http.Response response = await http.get(uri).timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.err(
          'MAPBOX',
          'Directions API returned ${response.statusCode}',
          data: response.body,
        );
        throw MapboxDirectionsException(
          'Route planning failed (${response.statusCode}).',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const MapboxDirectionsException(
          'Route planning response was invalid.',
        );
      }

      final List<dynamic> routes = decoded['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty || routes.first is! Map<String, dynamic>) {
        throw const MapboxDirectionsException('No route found.');
      }

      final Map<String, dynamic> route = routes.first as Map<String, dynamic>;
      final Map<String, dynamic>? geometry =
          route['geometry'] as Map<String, dynamic>?;
      final List<dynamic> coordinates =
          geometry?['coordinates'] as List<dynamic>? ?? <dynamic>[];

      final List<LatLng> points = <LatLng>[];

      for (final dynamic coordinate in coordinates) {
        if (coordinate is! List || coordinate.length < 2) continue;

        final double? lng = (coordinate[0] as num?)?.toDouble();
        final double? lat = (coordinate[1] as num?)?.toDouble();

        if (lat == null || lng == null) continue;

        final LatLng point = LatLng(lat, lng);
        if (isValidLatLng(point)) points.add(point);
      }

      if (points.length < 2) {
        throw const MapboxDirectionsException('Route has no usable geometry.');
      }

      return PlannedRoute(
        points: List<LatLng>.unmodifiable(points),
        distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0.0,
        durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0.0,
        profile: profile,
      );
    } on TimeoutException {
      throw const MapboxDirectionsException('Route request timed out.');
    } on MapboxDirectionsException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.err(
        'MAPBOX',
        'Directions planning failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw const MapboxDirectionsException('Route planning failed.');
    }
  }
}
