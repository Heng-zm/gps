import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/weather_data.dart';
import 'settings_service.dart';

/// WeatherService — powered by OpenWeatherMap One Call API 3.0
/// Docs: https://openweathermap.org/api/one-call-3
class WeatherService {
  WeatherService._internal();
  static final WeatherService instance = WeatherService._internal();
  factory WeatherService() => instance;

  // ── API config ────────────────────────────────────────────────────────────
  static const String _apiKey = '8e8b91972447e6527d3ff5da24cc63d1';
  static const String _authority = 'api.openweathermap.org';
  static const String _currentPath = '/data/2.5/weather';
  static const String _forecastPath = '/data/2.5/forecast';

  // ── Cache ─────────────────────────────────────────────────────────────────
  WeatherData? _cache;
  DateTime? _lastFetch;
  bool? _cachedIsMetric;
  double? _cachedLat;
  double? _cachedLon;

  static const _cacheDuration = Duration(minutes: 10);
  static const _locationEpsilon = 0.01; // ~1 km — skip refetch if barely moved

  // ── Public API ────────────────────────────────────────────────────────────

  Future<WeatherData?> fetchWeather(double lat, double lon) async {
    // Guard: invalid coordinates
    if (!_isValidCoord(lat, lon)) {
      debugPrint(
          '[WeatherService] Invalid coords: $lat, $lon — skipping fetch');
      return null;
    }

    final bool isMetric = SettingsService.instance.useKmh;
    final String units = isMetric ? 'metric' : 'imperial';

    // Return cache if still fresh, same unit system, and location hasn't moved much
    if (_isCacheValid(lat, lon, isMetric)) {
      debugPrint('[WeatherService] Returning cached weather');
      return _cache;
    }

    try {
      // ── Fetch current weather ─────────────────────────────────────────────
      final currentUrl = Uri.https(_authority, _currentPath, {
        'lat': lat.toStringAsFixed(4),
        'lon': lon.toStringAsFixed(4),
        'appid': _apiKey,
        'units': units,
      });

      // ── Fetch 5-day / 3-hour forecast (free tier) ─────────────────────────
      final forecastUrl = Uri.https(_authority, _forecastPath, {
        'lat': lat.toStringAsFixed(4),
        'lon': lon.toStringAsFixed(4),
        'appid': _apiKey,
        'units': units,
        'cnt': '4', // 4 × 3 h = 12 h ahead — enough for evening/night
      });

      final responses = await Future.wait([
        http.get(currentUrl).timeout(const Duration(seconds: 8)),
        http.get(forecastUrl).timeout(const Duration(seconds: 8)),
      ]);

      final currentRes = responses[0];
      final forecastRes = responses[1];

      // ── Validate responses ────────────────────────────────────────────────
      if (currentRes.statusCode != 200) {
        debugPrint('[WeatherService] Current weather failed: '
            '${currentRes.statusCode} — ${currentRes.body}');
        return null;
      }
      if (forecastRes.statusCode != 200) {
        debugPrint('[WeatherService] Forecast failed: '
            '${forecastRes.statusCode} — ${forecastRes.body}');
        // Degrade gracefully — current weather only
      }

      // ── Parse current ─────────────────────────────────────────────────────
      final Map<String, dynamic> cur =
          jsonDecode(currentRes.body) as Map<String, dynamic>;

      final main = cur['main'] as Map<String, dynamic>? ?? {};
      final wind = cur['wind'] as Map<String, dynamic>? ?? {};
      final weather =
          (cur['weather'] as List?)?.firstOrNull as Map<String, dynamic>? ?? {};

      final double temperature = _asDouble(main['temp']);
      final double feelsLike = _asDouble(main['feels_like']);
      final double windSpeed = _asDouble(wind['speed']);
      final int humidity = _asInt(main['humidity']);
      final int weatherId = _asInt(weather['id']);
      final String condition = _owmIdToCondition(weatherId);

      // ── Parse forecast ────────────────────────────────────────────────────
      double forecastLater = temperature;
      double forecastEvening = temperature;
      double forecastNight = temperature;
      int precipPct = 0;

      if (forecastRes.statusCode == 200) {
        final Map<String, dynamic> fc =
            jsonDecode(forecastRes.body) as Map<String, dynamic>;
        final List<dynamic> list = fc['list'] as List? ?? [];

        // Each item is 3 h apart: index 0=now+3h, 1=+6h, 2=+9h, 3=+12h
        if (list.isNotEmpty) {
          final item0 = list[0] as Map<String, dynamic>;
          precipPct = ((_asDouble((item0['pop'] as num?)) * 100)).round();
        }
        if (list.length > 1) {
          final item1 = list[1] as Map<String, dynamic>;
          forecastLater = _asDouble((item1['main'] as Map?)?['temp']);
        }
        if (list.length > 2) {
          final item2 = list[2] as Map<String, dynamic>;
          forecastEvening = _asDouble((item2['main'] as Map?)?['temp']);
        }
        if (list.length > 3) {
          final item3 = list[3] as Map<String, dynamic>;
          forecastNight = _asDouble((item3['main'] as Map?)?['temp']);
        }
      }

      // ── Build result ──────────────────────────────────────────────────────
      final result = WeatherData(
        temperature: temperature,
        feelsLike: feelsLike,
        condition: condition,
        windSpeed: windSpeed,
        humidity: humidity,
        precipProbabilityPct: precipPct,
        forecastLater: forecastLater,
        forecastEvening: forecastEvening,
        forecastNight: forecastNight,
      );

      // Update cache
      _cache = result;
      _lastFetch = DateTime.now();
      _cachedIsMetric = isMetric;
      _cachedLat = lat;
      _cachedLon = lon;

      debugPrint('[WeatherService] Fetched: $condition '
          '${temperature.toStringAsFixed(1)}° '
          '(${isMetric ? "°C" : "°F"})');

      return result;
    } catch (e, stack) {
      debugPrint('[WeatherService] Exception: $e');
      debugPrint(stack.toString());
      return _cache; // Return stale cache on error rather than null
    }
  }

  /// Clear cache manually (e.g. when unit settings change)
  void invalidateCache() {
    _cache = null;
    _lastFetch = null;
    _cachedIsMetric = null;
    _cachedLat = null;
    _cachedLon = null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  bool _isValidCoord(double lat, double lon) {
    return lat.isFinite &&
        lon.isFinite &&
        !(lat == 0.0 && lon == 0.0) &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180;
  }

  bool _isCacheValid(double lat, double lon, bool isMetric) {
    if (_cache == null || _lastFetch == null) return false;
    if (_cachedIsMetric != isMetric) return false;
    if (DateTime.now().difference(_lastFetch!) >= _cacheDuration) return false;
    if (_cachedLat == null || _cachedLon == null) return false;
    final movedLat = (_cachedLat! - lat).abs();
    final movedLon = (_cachedLon! - lon).abs();
    return movedLat < _locationEpsilon && movedLon < _locationEpsilon;
  }

  double _asDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  int _asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  // ── OWM weather ID → human condition ─────────────────────────────────────
  // Reference: https://openweathermap.org/weather-conditions
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
    if (id >= 700 && id < 800) return 'Foggy';
    return 'Cloudy';
  }
}
