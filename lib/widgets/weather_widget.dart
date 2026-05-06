import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accent.withValues(alpha: 0.1),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RichText(
                text: const TextSpan(
                  style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                  children: [
                    TextSpan(text: 'Live weather '),
                    TextSpan(
                      text: 'at your location',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!isLoading && weather != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    settings.useKmh ? 'METRIC' : 'IMPERIAL',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: CupertinoActivityIndicator(
                    color: Color(0xFF4ECDC4), radius: 12),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Icon(CupertinoIcons.cloud_moon_bolt,
              color: Color(0xFF555555), size: 20),
          const SizedBox(width: 12),
          const Text('Weather system offline',
              style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          if (onRetry != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              onPressed: onRetry,
              child: const Text('RETRY',
                  style: TextStyle(
                      color: Color(0xFF4ECDC4),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
            ),
        ],
      ),
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CURRENTLY',
                    style: TextStyle(
                        color: Color(0xFF555555),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5)),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${weather.temperature.toInt()}°',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            fontWeight: FontWeight.w200,
                            height: 1)),
                    const SizedBox(width: 8),
                    Text(
                      'Feels ${weather.feelsLike.toInt()}°',
                      style: TextStyle(
                          color: weather.accentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(weather.condition.toUpperCase(),
                        style: const TextStyle(
                            color: Color(0xFFAAAAAA),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    if (weather.hasPrecipRisk) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF4A9EFF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '💧 ${weather.precipProbabilityPct}%',
                          style: const TextStyle(
                              color: Color(0xFF4A9EFF),
                              fontSize: 10,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(weather.icon, style: const TextStyle(fontSize: 64)),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(color: Color(0xFF222222), height: 1, thickness: 1),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _InfoChip(
                icon: '💨',
                label: 'WIND SPEED',
                value: '${weather.windSpeed.toInt()} ${settings.speedUnit}'),
            _InfoChip(
                icon: '💧', label: 'HUMIDITY', value: '${weather.humidity}%'),
          ],
        ),
        const SizedBox(height: 24),
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
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
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
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFF444444),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text('${temp.toInt()}°',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
