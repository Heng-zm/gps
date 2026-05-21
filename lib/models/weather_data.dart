import 'package:flutter/material.dart';

/// Immutable weather data model.
/// Values are always in the user's preferred unit system
/// (metric or imperial) as returned by WeatherService.
class WeatherData {
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

  final double temperature;
  final double feelsLike;
  final String condition;
  final double windSpeed;
  final int humidity;
  final double forecastLater;
  final double forecastEvening;
  final double forecastNight;
  final int precipProbabilityPct;

  String get _c => condition.toLowerCase();

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
    if (_c.contains('fog') || _c.contains('mist') || _c.contains('haze')) {
      return '🌫️';
    }
    if (_c.contains('overcast')) return '☁️';
    if (_c.contains('partly') || _c.contains('few')) return '⛅';
    if (_c.contains('cloudy')) return '☁️';
    if (_c.contains('clear') || _c.contains('sunny')) return '☀️';
    return '🌤️';
  }

  Color get accentColor {
    if (_c.contains('thunder')) return const Color(0xFFE8412A);
    if (_c.contains('snow') ||
        _c.contains('blizzard') ||
        _c.contains('sleet') ||
        _c.contains('ice') ||
        _c.contains('freezing')) {
      return const Color(0xFFADDEFF);
    }
    if (_c.contains('rain') ||
        _c.contains('shower') ||
        _c.contains('drizzle')) {
      return const Color(0xFF4A9EFF);
    }
    if (_c.contains('fog') ||
        _c.contains('mist') ||
        _c.contains('haze') ||
        _c.contains('overcast')) {
      return const Color(0xFF8899AA);
    }
    if (_c.contains('clear') || _c.contains('sunny')) {
      return const Color(0xFFEDD068);
    }
    if (_c.contains('partly') || _c.contains('few')) {
      return const Color(0xFFD4A843);
    }
    return const Color(0xFFD4A843);
  }

  int get safeHumidity => humidity.clamp(0, 100).toInt();

  int get safePrecipProbabilityPct =>
      precipProbabilityPct.clamp(0, 100).toInt();

  bool get hasPrecipRisk => safePrecipProbabilityPct > 20;

  String get precipLabel {
    final int precip = safePrecipProbabilityPct;
    if (precip == 0) return 'No rain';
    if (precip <= 20) return 'Unlikely';
    if (precip <= 50) return 'Possible';
    if (precip <= 80) return 'Likely';
    return 'Certain';
  }

  String get windDescription {
    final double wind = _safeNonNegative(windSpeed);
    if (wind < 1) return 'Calm';
    if (wind < 10) return 'Light Breeze';
    if (wind < 25) return 'Moderate';
    if (wind < 40) return 'Fresh Wind';
    if (wind < 60) return 'Strong Wind';
    return 'High Winds';
  }

  String get windIcon {
    final double wind = _safeNonNegative(windSpeed);
    if (wind < 1) return '🍃';
    if (wind < 10) return '🌬️';
    if (wind < 40) return '💨';
    return '🌪️';
  }

  String get tempDisplay => '${_safeFinite(temperature).round()}°';

  String get feelsLikeDisplay => 'Feels ${_safeFinite(feelsLike).round()}°';

  bool get tempChanging => (forecastLater - temperature).abs() >= 3;

  int get tempTrend {
    final double delta = _safeFinite(forecastLater) - _safeFinite(temperature);
    if (delta > 1.5) return 1;
    if (delta < -1.5) return -1;
    return 0;
  }

  String get tempTrendLabel {
    return switch (tempTrend) {
      1 => 'Warming up',
      -1 => 'Cooling down',
      _ => 'Staying steady',
    };
  }

  int get severity {
    if (_c.contains('thunder') || _c.contains('blizzard')) return 2;
    if (_c.contains('snow') ||
        _c.contains('freezing') ||
        _c.contains('sleet') ||
        _c.contains('heavy')) return 1;
    if (hasPrecipRisk) return 1;
    return 0;
  }

  bool get isDrivingCaution => severity > 0;

  String get drivingAdvisory {
    if (_c.contains('thunder')) return 'Seek shelter — storm risk';
    if (_c.contains('blizzard')) return 'Avoid driving — blizzard';
    if (_c.contains('snow') || _c.contains('sleet')) {
      return 'Slippery roads possible';
    }
    if (_c.contains('freezing')) return 'Black ice risk';
    if (_c.contains('fog') || _c.contains('mist')) return 'Reduced visibility';
    if (hasPrecipRisk && safePrecipProbabilityPct > 50) {
      return 'Wet roads — drive carefully';
    }
    if (_safeNonNegative(windSpeed) >= 60) return 'High crosswind alert';
    return 'Conditions look fine';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'temperature': _safeFinite(temperature),
      'feelsLike': _safeFinite(feelsLike),
      'condition': condition,
      'windSpeed': _safeNonNegative(windSpeed),
      'humidity': safeHumidity,
      'forecastLater': _safeFinite(forecastLater),
      'forecastEvening': _safeFinite(forecastEvening),
      'forecastNight': _safeFinite(forecastNight),
      'precipProbabilityPct': safePrecipProbabilityPct,
    };
  }

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      temperature: _readDouble(json['temperature'] ?? json['temp']),
      feelsLike: _readDouble(json['feelsLike'] ?? json['feels_like']),
      condition: json['condition']?.toString() ?? 'Unknown',
      windSpeed: _safeNonNegative(
        _readDouble(json['windSpeed'] ?? json['wind_speed']),
      ),
      humidity: _readInt(json['humidity']).clamp(0, 100).toInt(),
      forecastLater: _readDouble(json['forecastLater']),
      forecastEvening: _readDouble(json['forecastEvening']),
      forecastNight: _readDouble(json['forecastNight']),
      precipProbabilityPct:
          _readInt(json['precipProbabilityPct'] ?? json['precip'])
              .clamp(0, 100)
              .toInt(),
    );
  }

  static WeatherData? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return WeatherData.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

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
      'temp: ${_safeFinite(temperature).toStringAsFixed(1)}°, '
      'feelsLike: ${_safeFinite(feelsLike).toStringAsFixed(1)}°, '
      'wind: ${_safeFinite(windSpeed).toStringAsFixed(1)}, '
      'humidity: $safeHumidity%, '
      'precip: $safePrecipProbabilityPct%)';
}

double _readDouble(Object? value) {
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

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

double _safeFinite(double value) => value.isFinite ? value : 0.0;

double _safeNonNegative(double value) {
  if (!value.isFinite) return 0.0;
  return value < 0.0 ? 0.0 : value;
}

extension WeatherDataUxX on WeatherData {
  bool get isSevere => severity >= 2;

  bool get isWetRoadRisk =>
      _c.contains('rain') ||
      _c.contains('shower') ||
      _c.contains('drizzle') ||
      safePrecipProbabilityPct > 50;

  bool get isLowVisibilityRisk =>
      _c.contains('fog') || _c.contains('mist') || _c.contains('haze');

  String get compactSummary => '$icon $tempDisplay · $condition';

  String get drivingBadge {
    if (isSevere) return 'Alert';
    if (isDrivingCaution) return 'Caution';
    return 'Clear';
  }

  String get routePlanningHint {
    if (isSevere) return drivingAdvisory;
    if (isWetRoadRisk) return 'Add extra braking distance';
    if (isLowVisibilityRisk) return 'Use lights and reduce speed';
    if (_safeNonNegative(windSpeed) >= 40) return 'Watch for crosswinds';
    return 'Good for route tracking';
  }
}
