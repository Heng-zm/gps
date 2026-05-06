import 'package:flutter/material.dart';

/// Immutable weather data model.
/// Values are always in the user's preferred unit system
/// (metric or imperial) as returned by [WeatherService].
class WeatherData {
  final double temperature;
  final double feelsLike;
  final String condition;
  final double windSpeed;
  final int humidity;
  final double forecastLater;
  final double forecastEvening;
  final double forecastNight;
  final int precipProbabilityPct;

  const WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.condition,
    required this.windSpeed,
    required this.humidity,
    required this.forecastLater,
    required this.forecastEvening,
    required this.forecastNight,
    this.precipProbabilityPct = 0,
  });

  // ── Derived helpers ───────────────────────────────────────────────────────

  /// Lowercase condition for pattern matching — computed once.
  String get _c => condition.toLowerCase();

  // ── Icon ──────────────────────────────────────────────────────────────────

  /// Returns an emoji icon that best represents the current condition.
  String get icon {
    if (_c.contains('thunder')) return '⛈️';
    if (_c.contains('snow') ||
        _c.contains('ice') ||
        _c.contains('blizzard') ||
        _c.contains('sleet')) return '❄️';
    if (_c.contains('freezing')) return '🌨️';
    if (_c.contains('shower')) return '🌦️';
    if (_c.contains('rain')) return '🌧️';
    if (_c.contains('drizzle')) return '🌦️';
    if (_c.contains('fog') || _c.contains('mist') || _c.contains('haze'))
      return '🌫️';
    if (_c.contains('overcast')) return '☁️';
    if (_c.contains('partly') || _c.contains('few')) return '⛅';
    if (_c.contains('cloudy')) return '☁️';
    if (_c.contains('clear') || _c.contains('sunny')) return '☀️';
    return '🌤️';
  }

  // ── Accent color ──────────────────────────────────────────────────────────

  /// UI accent color tuned to the gold palette.
  /// Severe conditions use warning/cool tones; calm/clear uses gold.
  Color get accentColor {
    if (_c.contains('thunder')) return const Color(0xFFE8412A); // red-alert
    if (_c.contains('snow') ||
        _c.contains('blizzard') ||
        _c.contains('sleet') ||
        _c.contains('ice')) return const Color(0xFFADDEFF); // icy blue
    if (_c.contains('freezing')) return const Color(0xFFADDEFF);
    if (_c.contains('rain') || _c.contains('shower') || _c.contains('drizzle'))
      return const Color(0xFF4A9EFF); // rain blue
    if (_c.contains('fog') ||
        _c.contains('mist') ||
        _c.contains('haze') ||
        _c.contains('overcast')) return const Color(0xFF8899AA); // grey
    if (_c.contains('clear') || _c.contains('sunny'))
      return const Color(0xFFEDD068); // gold-bright
    if (_c.contains('partly') || _c.contains('few'))
      return const Color(0xFFD4A843); // gold-mid
    return const Color(0xFFD4A843); // gold-mid default
  }

  // ── Precipitation ─────────────────────────────────────────────────────────

  /// True when rain probability is meaningful (> 20 %).
  bool get hasPrecipRisk => precipProbabilityPct > 20;

  /// Short human label for precipitation probability.
  String get precipLabel {
    if (precipProbabilityPct == 0) return 'No rain';
    if (precipProbabilityPct <= 20) return 'Unlikely';
    if (precipProbabilityPct <= 50) return 'Possible';
    if (precipProbabilityPct <= 80) return 'Likely';
    return 'Certain';
  }

  // ── Wind ─────────────────────────────────────────────────────────────────

  /// Beaufort-inspired wind description (works for both km/h and mph
  /// since thresholds are chosen to be sensible in both systems).
  String get windDescription {
    if (windSpeed < 1) return 'Calm';
    if (windSpeed < 10) return 'Light Breeze';
    if (windSpeed < 25) return 'Moderate';
    if (windSpeed < 40) return 'Fresh Wind';
    if (windSpeed < 60) return 'Strong Wind';
    return 'High Winds';
  }

  /// Wind icon
  String get windIcon {
    if (windSpeed < 1) return '🍃';
    if (windSpeed < 10) return '🌬️';
    if (windSpeed < 40) return '💨';
    return '🌪️';
  }

  // ── Temperature ───────────────────────────────────────────────────────────

  /// Formatted temperature string, e.g. "23°"
  String get tempDisplay => '${temperature.round()}°';

  /// Formatted feels-like string, e.g. "Feels 21°"
  String get feelsLikeDisplay => 'Feels ${feelsLike.round()}°';

  /// True when the temperature delta between now and later is notable (≥ 3°).
  bool get tempChanging => (forecastLater - temperature).abs() >= 3;

  /// Direction of temperature change: +1 warming, -1 cooling, 0 stable.
  int get tempTrend {
    final delta = forecastLater - temperature;
    if (delta > 1.5) return 1;
    if (delta < -1.5) return -1;
    return 0;
  }

  /// Human summary of the temperature trend.
  String get tempTrendLabel {
    return switch (tempTrend) {
      1 => 'Warming up',
      -1 => 'Cooling down',
      _ => 'Staying steady',
    };
  }

  // ── Severity ──────────────────────────────────────────────────────────────

  /// Severity level: 0 = fine, 1 = caution, 2 = warning.
  int get severity {
    if (_c.contains('thunder') || _c.contains('blizzard')) return 2;
    if (_c.contains('snow') ||
        _c.contains('freezing') ||
        _c.contains('sleet') ||
        _c.contains('heavy')) return 1;
    if (hasPrecipRisk) return 1;
    return 0;
  }

  /// True if driving conditions may be affected.
  bool get isDrivingCaution => severity > 0;

  /// Short advisory string for the dashboard.
  String get drivingAdvisory {
    if (_c.contains('thunder')) return 'Seek shelter — storm risk';
    if (_c.contains('blizzard')) return 'Avoid driving — blizzard';
    if (_c.contains('snow') || _c.contains('sleet'))
      return 'Slippery roads possible';
    if (_c.contains('freezing')) return 'Black ice risk';
    if (_c.contains('fog') || _c.contains('mist')) return 'Reduced visibility';
    if (hasPrecipRisk && precipProbabilityPct > 50)
      return 'Wet roads — drive carefully';
    if (windSpeed >= 60) return 'High crosswind alert';
    return 'Conditions look fine';
  }

  // ── Equality & debugging ──────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeatherData &&
          other.temperature == temperature &&
          other.feelsLike == feelsLike &&
          other.condition == condition &&
          other.windSpeed == windSpeed &&
          other.humidity == humidity &&
          other.precipProbabilityPct == precipProbabilityPct &&
          other.forecastLater == forecastLater &&
          other.forecastEvening == forecastEvening &&
          other.forecastNight == forecastNight;

  @override
  int get hashCode => Object.hash(
        temperature,
        feelsLike,
        condition,
        windSpeed,
        humidity,
        precipProbabilityPct,
        forecastLater,
        forecastEvening,
        forecastNight,
      );

  @override
  String toString() => 'WeatherData('
      'condition: $condition, '
      'temp: ${temperature.toStringAsFixed(1)}°, '
      'feelsLike: ${feelsLike.toStringAsFixed(1)}°, '
      'wind: ${windSpeed.toStringAsFixed(1)}, '
      'humidity: $humidity%, '
      'precip: $precipProbabilityPct%)';

  /// Creates a copy with selected fields overridden.
  WeatherData copyWith({
    double? temperature,
    double? feelsLike,
    String? condition,
    double? windSpeed,
    int? humidity,
    double? forecastLater,
    double? forecastEvening,
    double? forecastNight,
    int? precipProbabilityPct,
  }) {
    return WeatherData(
      temperature: temperature ?? this.temperature,
      feelsLike: feelsLike ?? this.feelsLike,
      condition: condition ?? this.condition,
      windSpeed: windSpeed ?? this.windSpeed,
      humidity: humidity ?? this.humidity,
      forecastLater: forecastLater ?? this.forecastLater,
      forecastEvening: forecastEvening ?? this.forecastEvening,
      forecastNight: forecastNight ?? this.forecastNight,
      precipProbabilityPct: precipProbabilityPct ?? this.precipProbabilityPct,
    );
  }
}
