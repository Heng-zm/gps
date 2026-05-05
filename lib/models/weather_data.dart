import 'package:flutter/material.dart';

class WeatherData {
  // We rename these to be unit-agnostic.
  // The value (double) remains the same, but the UI labels it based on Settings.
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

  /// Logic-based icon selector
  String get icon {
    final c = condition.toLowerCase();
    return switch (c) {
      _ when c.contains('clear') || c.contains('sunny') => '☀️',
      _ when c.contains('partly') => '⛅',
      _ when c.contains('cloudy') => '☁️',
      _ when c.contains('fog') || c.contains('mist') => '🌫️',
      _ when c.contains('thunder') => '⛈️',
      _ when c.contains('snow') || c.contains('ice') => '❄️',
      _ when c.contains('drizzle') => '🌦️',
      _ when c.contains('rain') || c.contains('shower') => '🌧️',
      _ => '🌤️',
    };
  }

  // Update the accentColor getter to include braces:
  Color get accentColor {
    final c = condition.toLowerCase();
    if (c.contains('snow')) {
      return const Color(0xFFADDEFF);
    }
    if (c.contains('rain') || c.contains('thunder')) {
      return const Color(0xFF4A9EFF);
    }
    if (c.contains('sunny') || c.contains('clear')) {
      return const Color(0xFFFFD166);
    }
    return const Color(0xFF4ECDC4);
  }

  /// Rain probability logic
  bool get hasPrecipRisk => precipProbabilityPct > 20;

  /// Human-readable wind description
  String get windDescription {
    if (windSpeed < 1) return 'Calm';
    if (windSpeed < 10) return 'Light Breeze';
    if (windSpeed < 25) return 'Moderate';
    return 'High Winds';
  }
}
