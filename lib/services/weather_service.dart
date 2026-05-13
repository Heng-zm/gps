import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/weather_data.dart';
import 'settings_service.dart';

/// WeatherService — OpenWeatherMap current weather + 5-day / 3-hour forecast.
///
/// Optimized version:
/// - persistent HTTP client
/// - cache by unit + nearby location
/// - in-flight request de-duplication
/// - retry once for temporary failures
/// - safer JSON parsing
/// - better forecast parsing
/// - keeps returning cached weather when network fails
class WeatherService {
  WeatherService._internal();

  static final WeatherService instance = WeatherService._internal();

  factory WeatherService() => instance;

  // ── API config ────────────────────────────────────────────────────────────
  //
  // Recommended for production:
  // Move this API key to a secure config file, .env, or remote config.
  static const String _apiKey = '8e8b91972447e6527d3ff5da24cc63d1';

  static const String _authority = 'api.openweathermap.org';
  static const String _currentPath = '/data/2.5/weather';
  static const String _forecastPath = '/data/2.5/forecast';

  static const Duration _requestTimeout = Duration(seconds: 8);
  static const Duration _retryDelay = Duration(milliseconds: 450);

  // ── Cache ─────────────────────────────────────────────────────────────────
  static const Duration _cacheDuration = Duration(minutes: 10);

  /// Around 1 km. Prevents refetching when the user barely moved.
  static const double _locationEpsilon = 0.01;

  WeatherData? _cache;
  DateTime? _lastFetch;
  bool? _cachedIsMetric;
  double? _cachedLat;
  double? _cachedLon;

  Future<WeatherData?>? _inFlightRequest;
  http.Client? _client;

  http.Client get _httpClient {
    _client ??= http.Client();
    return _client!;
  }

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
      if (identical(_inFlightRequest, request)) {
        _inFlightRequest = null;
      }
    }
  }

  /// Returns cached weather immediately without doing network work.
  WeatherData? get cachedWeather => _cache;

  /// Clear cache manually, for example when unit settings change.
  void invalidateCache() {
    _cache = null;
    _lastFetch = null;
    _cachedIsMetric = null;
    _cachedLat = null;
    _cachedLon = null;
    _inFlightRequest = null;
  }

  /// Safe to call on app shutdown.
  void dispose() {
    _client?.close();
    _client = null;
    _inFlightRequest = null;
  }

  // ── Internal fetch ─────────────────────────────────────────────────────────

  Future<WeatherData?> _fetchWeatherInternal({
    required double lat,
    required double lon,
    required bool isMetric,
  }) async {
    final String units = isMetric ? 'metric' : 'imperial';

    final Uri currentUrl = Uri.https(_authority, _currentPath, <String, String>{
      'lat': lat.toStringAsFixed(4),
      'lon': lon.toStringAsFixed(4),
      'appid': _apiKey,
      'units': units,
    });

    final Uri forecastUrl =
        Uri.https(_authority, _forecastPath, <String, String>{
      'lat': lat.toStringAsFixed(4),
      'lon': lon.toStringAsFixed(4),
      'appid': _apiKey,
      'units': units,
      'cnt': '8',
    });

    try {
      final List<http.Response?> responses = await Future.wait<http.Response?>([
        _safeGetWithRetry(currentUrl),
        _safeGetWithRetry(forecastUrl),
      ]);

      final http.Response? currentRes = responses[0];
      final http.Response? forecastRes = responses[1];

      if (currentRes == null) {
        debugPrint('[WeatherService] Current weather request returned null');
        return _cache;
      }

      if (!_isSuccess(currentRes.statusCode)) {
        debugPrint(
          '[WeatherService] Current weather failed: '
          '${currentRes.statusCode} - ${_safeShortBody(currentRes.body)}',
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

  Future<http.Response?> _safeGetWithRetry(Uri uri) async {
    final http.Response? first = await _safeGet(uri);

    if (first == null) {
      await Future<void>.delayed(_retryDelay);
      return _safeGet(uri);
    }

    if (_isTemporaryStatus(first.statusCode)) {
      await Future<void>.delayed(_retryDelay);
      final http.Response? second = await _safeGet(uri);
      return second ?? first;
    }

    return first;
  }

  Future<http.Response?> _safeGet(Uri uri) async {
    try {
      return await _httpClient.get(uri).timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      debugPrint('[WeatherService] Request timeout: $uri - $e');
      return null;
    } catch (e) {
      debugPrint('[WeatherService] Request failed: $uri - $e');
      return null;
    }
  }

  Map<String, dynamic>? _readForecastJson(http.Response? forecastRes) {
    if (forecastRes == null) {
      debugPrint('[WeatherService] Forecast request returned null');
      return null;
    }

    if (!_isSuccess(forecastRes.statusCode)) {
      debugPrint(
        '[WeatherService] Forecast failed: '
        '${forecastRes.statusCode} - ${_safeShortBody(forecastRes.body)}',
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
    final double feelsLike = _asDouble(
      main['feels_like'],
      fallback: temperature,
    );
    final double windSpeed = _asDouble(wind['speed']);
    final int humidity = _asInt(main['humidity']).clamp(0, 100);
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
      return _ForecastValues.fallback(fallbackTemperature);
    }

    final List<dynamic> list = _asList(forecastJson['list']);
    if (list.isEmpty) {
      return _ForecastValues.fallback(fallbackTemperature);
    }

    double later = fallbackTemperature;
    double evening = fallbackTemperature;
    double night = fallbackTemperature;
    int maxPopPct = 0;

    for (int i = 0; i < math.min(list.length, 8); i++) {
      final Map<String, dynamic> item = _asMap(list[i]);
      final Map<String, dynamic> itemMain = _asMap(item['main']);

      final double temp = _asDouble(
        itemMain['temp'],
        fallback: fallbackTemperature,
      );

      final int pop = (_asDouble(item['pop']) * 100).clamp(0.0, 100.0).round();
      if (pop > maxPopPct) maxPopPct = pop;

      if (i == 1) later = temp;
      if (i == 3) evening = temp;
      if (i == 5 || i == list.length - 1) night = temp;
    }

    // Keep useful values even when API returned fewer than expected items.
    if (list.length == 1) {
      later = _forecastTempAt(list, 0, fallbackTemperature);
      evening = later;
      night = later;
    } else if (list.length == 2) {
      evening = _forecastTempAt(list, 1, fallbackTemperature);
      night = evening;
    } else if (list.length <= 4) {
      night = _forecastTempAt(list, list.length - 1, fallbackTemperature);
    }

    return _ForecastValues(
      precipProbabilityPct: maxPopPct,
      forecastLater: later,
      forecastEvening: evening,
      forecastNight: night,
    );
  }

  double _forecastTempAt(
    List<dynamic> list,
    int index,
    double fallbackTemperature,
  ) {
    if (index < 0 || index >= list.length) return fallbackTemperature;

    final Map<String, dynamic> item = _asMap(list[index]);
    return _asDouble(
      _asMap(item['main'])['temp'],
      fallback: fallbackTemperature,
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

  bool _isSuccess(int statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  bool _isTemporaryStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 409 ||
        statusCode == 425 ||
        statusCode == 429 ||
        (statusCode >= 500 && statusCode <= 599);
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
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : fallback;
    }

    if (value is String) {
      final double? parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed : fallback;
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

  // ── OWM weather ID -> human condition ──────────────────────────────────────
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

  factory _ForecastValues.fallback(double temperature) {
    return _ForecastValues(
      precipProbabilityPct: 0,
      forecastLater: temperature,
      forecastEvening: temperature,
      forecastNight: temperature,
    );
  }

  final int precipProbabilityPct;
  final double forecastLater;
  final double forecastEvening;
  final double forecastNight;
}
