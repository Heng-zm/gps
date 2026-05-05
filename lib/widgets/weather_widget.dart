import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // Added for iOS-style indicator
import '../models/weather_data.dart';
import '../services/settings_service.dart';

class WeatherWidget extends StatelessWidget {
  final WeatherData? weather;
  final bool isLoading;
  final VoidCallback? onRetry;

  const WeatherWidget({
    super.key,
    this.weather,
    this.isLoading = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    // Use the model's accent color or default teal
    final Color accent = weather?.accentColor ?? const Color(0xFF4ECDC4);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius:
            BorderRadius.circular(20), // Slightly rounder for modern look
        border: Border.all(
          color: accent.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RichText(
                text: const TextSpan(
                  style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                  children: [
                    TextSpan(text: 'Live weather '),
                    TextSpan(
                      text: 'at your location',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!isLoading && weather != null)
                Text(
                  settings.useKmh ? 'Metric' : 'Imperial',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CupertinoActivityIndicator(color: Color(0xFF4ECDC4)),
              ),
            )
          else if (weather == null)
            _ErrorState(onRetry: onRetry)
          else
            _WeatherContent(weather: weather!, settings: settings),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  const _ErrorState({this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.cloud_off, color: Color(0xFF444444), size: 16),
        const SizedBox(width: 8),
        const Text('Weather unavailable',
            style: TextStyle(color: Color(0xFF666666), fontSize: 13)),
        const Spacer(),
        if (onRetry != null)
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Retry',
                  style: TextStyle(
                      color: Color(0xFF4ECDC4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

class _WeatherContent extends StatelessWidget {
  final WeatherData weather;
  final SettingsService settings;
  const _WeatherContent({required this.weather, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CURRENTLY',
                    style: TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${weather.temperature.toInt()}°',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w200)),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, left: 4),
                      child: Text(
                        'Feels ${weather.feelsLike.toInt()}°',
                        style: TextStyle(
                            color: weather.accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(weather.condition,
                        style: const TextStyle(
                            color: Color(0xFFBBBBBB), fontSize: 14)),
                    if (weather.hasPrecipRisk) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A9EFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '💧 ${weather.precipProbabilityPct}%',
                          style: const TextStyle(
                              color: Color(0xFF4A9EFF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(weather.icon, style: const TextStyle(fontSize: 56)),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(color: Color(0xFF2A2A2A), height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            _InfoChip(
                icon: '💨',
                label: 'WIND',
                value: '${weather.windSpeed.toInt()} ${settings.speedUnit}'),
            const SizedBox(width: 32),
            _InfoChip(
                icon: '💧', label: 'HUMIDITY', value: '${weather.humidity}%'),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ForecastItem(
                label: 'Later', temp: weather.forecastLater, icon: '🌤️'),
            _ForecastItem(
                label: 'Evening', temp: weather.forecastEvening, icon: '🌆'),
            _ForecastItem(
                label: 'Night', temp: weather.forecastNight, icon: '🌙'),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String icon, label, value;
  const _InfoChip(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}

class _ForecastItem extends StatelessWidget {
  final String label, icon;
  final double temp;
  const _ForecastItem(
      {required this.label, required this.temp, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF666666), fontSize: 10)),
          const SizedBox(height: 6),
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text('${temp.toInt()}°',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
