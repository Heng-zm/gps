import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/weather_data.dart';
import 'settings_service.dart';

/// WeatherService — OpenWeatherMap current weather + 5-day / 3-hour forecast.
///
/// Uses:
/// - Current weather: /data/2.5/weather
/// - Forecast: /data/2.5/forecast
class WeatherService {
  WeatherService._internal();

  static final WeatherService instance = WeatherService._internal();

  factory WeatherService() => instance;

  // ── API config ────────────────────────────────────────────────────────────
  //
  // Recommended:
  // Move this API key to a secure config file, .env, or remote config.
  static const String _apiKey = '8e8b91972447e6527d3ff5da24cc63d1';

  static const String _authority = 'api.openweathermap.org';
  static const String _currentPath = '/data/2.5/weather';
  static const String _forecastPath = '/data/2.5/forecast';

  static const Duration _requestTimeout = Duration(seconds: 8);

  // ── Cache ─────────────────────────────────────────────────────────────────
  WeatherData? _cache;
  DateTime? _lastFetch;
  bool? _cachedIsMetric;
  double? _cachedLat;
  double? _cachedLon;

  Future<WeatherData?>? _inFlightRequest;

  static const Duration _cacheDuration = Duration(minutes: 10);

  // Around 1 km. Prevents refetching when the user barely moved.
  static const double _locationEpsilon = 0.01;

  // ── Public API ────────────────────────────────────────────────────────────

  Future<WeatherData?> fetchWeather(double lat, double lon) async {
    if (!_isValidCoord(lat, lon)) {
      debugPrint('[WeatherService] Invalid coords: $lat, $lon');
      return _cache;
    }

    final bool isMetric = SettingsService.instance.useKmh;

    if (_isCacheValid(lat, lon, isMetric)) {
      debugPrint('[WeatherService] Returning cached weather');
      return _cache;
    }

    final Future<WeatherData?>? existingRequest = _inFlightRequest;
    if (existingRequest != null) {
      debugPrint('[WeatherService] Returning in-flight weather request');
      return existingRequest;
    }

    final Future<WeatherData?> request = _fetchWeatherInternal(
      lat: lat,
      lon: lon,
      isMetric: isMetric,
    );

    _inFlightRequest = request;

    try {
      return await request;
    } finally {
      _inFlightRequest = null;
    }
  }

  /// Clear cache manually, for example when unit settings change.
  void invalidateCache() {
    _cache = null;
    _lastFetch = null;
    _cachedIsMetric = null;
    _cachedLat = null;
    _cachedLon = null;
    _inFlightRequest = null;
  }

  // ── Internal fetch ─────────────────────────────────────────────────────────

  Future<WeatherData?> _fetchWeatherInternal({
    required double lat,
    required double lon,
    required bool isMetric,
  }) async {
    final String units = isMetric ? 'metric' : 'imperial';

    final Uri currentUrl = Uri.https(_authority, _currentPath, {
      'lat': lat.toStringAsFixed(4),
      'lon': lon.toStringAsFixed(4),
      'appid': _apiKey,
      'units': units,
    });

    final Uri forecastUrl = Uri.https(_authority, _forecastPath, {
      'lat': lat.toStringAsFixed(4),
      'lon': lon.toStringAsFixed(4),
      'appid': _apiKey,
      'units': units,
      'cnt': '4',
    });

    try {
      final List<http.Response?> responses = await Future.wait<http.Response?>([
        _safeGet(currentUrl),
        _safeGet(forecastUrl),
      ]);

      final http.Response? currentRes = responses[0];
      final http.Response? forecastRes = responses[1];

      if (currentRes == null) {
        debugPrint('[WeatherService] Current weather request returned null');
        return _cache;
      }

      if (currentRes.statusCode != 200) {
        debugPrint(
          '[WeatherService] Current weather failed: '
          '${currentRes.statusCode} — ${_safeShortBody(currentRes.body)}',
        );
        return _cache;
      }

      final Map<String, dynamic>? currentJson = _decodeObject(currentRes.body);
      if (currentJson == null) {
        debugPrint('[WeatherService] Invalid current weather JSON');
        return _cache;
      }

      final WeatherData result = _buildWeatherData(
        currentJson: currentJson,
        forecastJson: _readForecastJson(forecastRes),
      );

      _updateCache(
        result: result,
        lat: lat,
        lon: lon,
        isMetric: isMetric,
      );

      debugPrint(
        '[WeatherService] Fetched: '
        '${result.condition} ${result.temperature.toStringAsFixed(1)}°'
        '${isMetric ? "C" : "F"}',
      );

      return result;
    } on TimeoutException catch (e, st) {
      debugPrint('[WeatherService] Timeout: $e\n$st');
      return _cache;
    } catch (e, st) {
      debugPrint('[WeatherService] Exception: $e\n$st');
      return _cache;
    }
  }

  Future<http.Response?> _safeGet(Uri uri) async {
    try {
      return await http.get(uri).timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      debugPrint('[WeatherService] Request timeout: $uri — $e');
      return null;
    } catch (e) {
      debugPrint('[WeatherService] Request failed: $uri — $e');
      return null;
    }
  }

  Map<String, dynamic>? _readForecastJson(http.Response? forecastRes) {
    if (forecastRes == null) {
      debugPrint('[WeatherService] Forecast request returned null');
      return null;
    }

    if (forecastRes.statusCode != 200) {
      debugPrint(
        '[WeatherService] Forecast failed: '
        '${forecastRes.statusCode} — ${_safeShortBody(forecastRes.body)}',
      );
      return null;
    }

    return _decodeObject(forecastRes.body);
  }

  WeatherData _buildWeatherData({
    required Map<String, dynamic> currentJson,
    required Map<String, dynamic>? forecastJson,
  }) {
    final Map<String, dynamic> main = _asMap(currentJson['main']);
    final Map<String, dynamic> wind = _asMap(currentJson['wind']);

    final List<dynamic> weatherList = _asList(currentJson['weather']);
    final Map<String, dynamic> weather = weatherList.isNotEmpty
        ? _asMap(weatherList.first)
        : const <String, dynamic>{};

    final double temperature = _asDouble(main['temp']);
    final double feelsLike = _asDouble(main['feels_like']);
    final double windSpeed = _asDouble(wind['speed']);
    final int humidity = _asInt(main['humidity']);
    final int weatherId = _asInt(weather['id']);

    final String condition = _owmIdToCondition(weatherId);

    final _ForecastValues forecast = _parseForecast(
      forecastJson: forecastJson,
      fallbackTemperature: temperature,
    );

    return WeatherData(
      temperature: temperature,
      feelsLike: feelsLike,
      condition: condition,
      windSpeed: windSpeed,
      humidity: humidity,
      precipProbabilityPct: forecast.precipProbabilityPct,
      forecastLater: forecast.forecastLater,
      forecastEvening: forecast.forecastEvening,
      forecastNight: forecast.forecastNight,
    );
  }

  _ForecastValues _parseForecast({
    required Map<String, dynamic>? forecastJson,
    required double fallbackTemperature,
  }) {
    if (forecastJson == null) {
      return _ForecastValues(
        precipProbabilityPct: 0,
        forecastLater: fallbackTemperature,
        forecastEvening: fallbackTemperature,
        forecastNight: fallbackTemperature,
      );
    }

    final List<dynamic> list = _asList(forecastJson['list']);

    double forecastLater = fallbackTemperature;
    double forecastEvening = fallbackTemperature;
    double forecastNight = fallbackTemperature;
    int precipProbabilityPct = 0;

    if (list.isNotEmpty) {
      final Map<String, dynamic> item0 = _asMap(list[0]);
      precipProbabilityPct =
          (_asDouble(item0['pop']) * 100).clamp(0.0, 100.0).round();
    }

    if (list.length > 1) {
      final Map<String, dynamic> item1 = _asMap(list[1]);
      forecastLater = _asDouble(
        _asMap(item1['main'])['temp'],
        fallback: fallbackTemperature,
      );
    }

    if (list.length > 2) {
      final Map<String, dynamic> item2 = _asMap(list[2]);
      forecastEvening = _asDouble(
        _asMap(item2['main'])['temp'],
        fallback: fallbackTemperature,
      );
    }

    if (list.length > 3) {
      final Map<String, dynamic> item3 = _asMap(list[3]);
      forecastNight = _asDouble(
        _asMap(item3['main'])['temp'],
        fallback: fallbackTemperature,
      );
    }

    return _ForecastValues(
      precipProbabilityPct: precipProbabilityPct,
      forecastLater: forecastLater,
      forecastEvening: forecastEvening,
      forecastNight: forecastNight,
    );
  }

  void _updateCache({
    required WeatherData result,
    required double lat,
    required double lon,
    required bool isMetric,
  }) {
    _cache = result;
    _lastFetch = DateTime.now();
    _cachedIsMetric = isMetric;
    _cachedLat = lat;
    _cachedLon = lon;
  }

  // ── Cache helpers ─────────────────────────────────────────────────────────

  bool _isCacheValid(double lat, double lon, bool isMetric) {
    final WeatherData? cached = _cache;
    final DateTime? lastFetch = _lastFetch;
    final double? cachedLat = _cachedLat;
    final double? cachedLon = _cachedLon;

    if (cached == null) return false;
    if (lastFetch == null) return false;
    if (_cachedIsMetric != isMetric) return false;
    if (cachedLat == null || cachedLon == null) return false;

    final Duration age = DateTime.now().difference(lastFetch);
    if (age >= _cacheDuration) return false;

    final double movedLat = (cachedLat - lat).abs();
    final double movedLon = (cachedLon - lon).abs();

    return movedLat < _locationEpsilon && movedLon < _locationEpsilon;
  }

  // ── Validation helpers ────────────────────────────────────────────────────

  bool _isValidCoord(double lat, double lon) {
    return lat.isFinite &&
        lon.isFinite &&
        !(lat == 0.0 && lon == 0.0) &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lon >= -180.0 &&
        lon <= 180.0;
  }

  // ── JSON helpers ──────────────────────────────────────────────────────────

  Map<String, dynamic>? _decodeObject(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return decoded.map(
          (dynamic key, dynamic value) => MapEntry(key.toString(), value),
        );
      }

      return null;
    } catch (e) {
      debugPrint('[WeatherService] JSON decode failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;

    if (value is Map) {
      return value.map(
        (dynamic key, dynamic mapValue) => MapEntry(key.toString(), mapValue),
      );
    }

    return const <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  double _asDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();

    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();

    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }

    return fallback;
  }

  String _safeShortBody(String body) {
    const int maxLength = 250;
    if (body.length <= maxLength) return body;
    return '${body.substring(0, maxLength)}...';
  }

  // ── OWM weather ID → human condition ──────────────────────────────────────
  //
  // Reference:
  // 2xx Thunderstorm
  // 3xx Drizzle
  // 5xx Rain
  // 6xx Snow
  // 7xx Atmosphere
  // 800 Clear
  // 80x Clouds
  String _owmIdToCondition(int id) {
    if (id == 800) return 'Clear Sky';

    if (id == 801) return 'Few Clouds';
    if (id == 802) return 'Partly Cloudy';
    if (id == 803 || id == 804) return 'Overcast';

    if (id >= 200 && id < 300) return 'Thunderstorm';
    if (id >= 300 && id < 400) return 'Drizzle';

    if (id >= 500 && id < 504) return 'Rainy';
    if (id == 511) return 'Freezing Rain';
    if (id >= 520 && id < 532) return 'Rain Showers';

    if (id >= 600 && id < 700) return 'Snowy';

    if (id == 701) return 'Misty';
    if (id == 711) return 'Smoky';
    if (id == 721) return 'Hazy';
    if (id == 731 || id == 751 || id == 761) return 'Dusty';
    if (id == 741) return 'Foggy';
    if (id == 762) return 'Volcanic Ash';
    if (id == 771) return 'Squalls';
    if (id == 781) return 'Tornado';

    return 'Cloudy';
  }
}

class _ForecastValues {
  const _ForecastValues({
    required this.precipProbabilityPct,
    required this.forecastLater,
    required this.forecastEvening,
    required this.forecastNight,
  });

  final int precipProbabilityPct;
  final double forecastLater;
  final double forecastEvening;
  final double forecastNight;
}
