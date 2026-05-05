import 'dart:convert';
import 'package:flutter/foundation.dart'; // Required for debugPrint
import 'package:http/http.dart' as http;
import '../models/weather_data.dart';
import 'settings_service.dart';

class WeatherService {
  // Singleton Pattern
  WeatherService._internal();
  static final WeatherService instance = WeatherService._internal();
  factory WeatherService() => instance;

  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  // Cache logic
  WeatherData? _cache;
  DateTime? _lastFetch;
  static const _cacheDuration = Duration(minutes: 10);

  Future<WeatherData?> fetchWeather(double lat, double lon) async {
    // 1. Check Cache: Prevent redundant API calls
    if (_cache != null && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _cacheDuration) {
        return _cache;
      }
    }

    try {
      // 2. Sync Units: Get preferred unit from Settings
      final bool isMetric = SettingsService.instance.useKmh;
      final String tempUnit = isMetric ? 'celsius' : 'fahrenheit';
      final String windUnit = isMetric ? 'kmh' : 'mph';

      // BUG FIX: Added 'apparent_temperature' to the URL request
      // Otherwise, the field in the model would always be 0.0
      final url = Uri.parse(
        '$_baseUrl'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,time'
        '&hourly=temperature_2m,precipitation_probability'
        '&temperature_unit=$tempUnit'
        '&wind_speed_unit=$windUnit'
        '&timezone=auto&forecast_days=2',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>?;
      final hourly = data['hourly'] as Map<String, dynamic>?;

      if (current == null || hourly == null) return null;

      // 3. Robust Index Finding
      final String currentIsoTime = current['time'];
      final List<dynamic> hourlyTimes = hourly['time'] ?? [];
      final int baseIdx = hourlyTimes.indexOf(currentIsoTime);
      final int startIdx = baseIdx != -1 ? baseIdx : DateTime.now().hour;

      final rawTemps = hourly['temperature_2m'] as List? ?? [];
      final rawPrecip = hourly['precipitation_probability'] as List? ?? [];

      // Helper to safely extract numbers
      double asDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;
      int asInt(dynamic value) => (value as num?)?.toInt() ?? 0;

      double getForecastTemp(int offset) {
        final idx = startIdx + offset;
        return idx < rawTemps.length
            ? asDouble(rawTemps[idx])
            : asDouble(current['temperature_2m']);
      }

      // 4. Construct Data
      // BUG FIX: Assign to a variable first so we can update the cache
      final weather = WeatherData(
        temperature: asDouble(current['temperature_2m']),
        feelsLike: asDouble(current['apparent_temperature']),
        condition: _wmoCodeToText(asInt(current['weather_code'])),
        windSpeed: asDouble(current['wind_speed_10m']),
        humidity: asInt(current['relative_humidity_2m']),
        precipProbabilityPct:
            startIdx < rawPrecip.length ? asInt(rawPrecip[startIdx]) : 0,
        forecastLater: getForecastTemp(3),
        forecastEvening: getForecastTemp(6),
        forecastNight: getForecastTemp(9),
      );

      // 5. Update Cache: Now this code will actually run!
      _cache = weather;
      _lastFetch = DateTime.now();

      return weather;
    } catch (e) {
      debugPrint('Weather Fetch Error: $e');
      return null;
    }
  }

  /// Maps WMO Codes to human text using Dart 3 Switch Expression
  String _wmoCodeToText(int code) {
    return switch (code) {
      0 => 'Clear Sky',
      1 || 2 || 3 => 'Partly Cloudy',
      45 || 48 => 'Foggy',
      51 || 53 || 55 => 'Drizzle',
      61 || 63 || 65 => 'Rainy',
      66 || 67 => 'Freezing Rain',
      71 || 73 || 75 => 'Snowy',
      77 => 'Snow Grains',
      80 || 81 || 82 => 'Rain Showers',
      85 || 86 => 'Snow Showers',
      95 || 96 || 99 => 'Thunderstorm',
      _ => 'Cloudy',
    };
  }
}
