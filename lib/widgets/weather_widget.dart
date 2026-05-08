import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/weather_data.dart';
import '../services/settings_service.dart';

// Helper: convert °F (raw API value) to °C for display.
double _toCelsius(double f) => (f - 32) * 5 / 9;

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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141414).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(settings),
          const SizedBox(height: 24),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CupertinoActivityIndicator(
                    color: Color(0xFFD4A843), radius: 14),
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

  Widget _buildHeader(SettingsService settings) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(
                color: Colors.white60, fontSize: 13, letterSpacing: 0.2),
            children: [
              TextSpan(text: 'Live weather '),
              TextSpan(
                text: 'at your location',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(
            settings.useKmh ? 'METRIC' : 'IMPERIAL',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback? onRetry;
  const _ErrorState({this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Colors.white24, size: 24),
            const SizedBox(width: 12),
            const Text('Weather Link Offline',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
            color: const Color(0xFFD4A843).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            onPressed: onRetry,
            child: const Text('RETRY',
                style: TextStyle(
                    color: Color(0xFFEDD068),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
          ),
        ]
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
    // FIX: Convert all °F values from the API to °C before display.
    final int tempC = _toCelsius(weather.temperature).toInt();
    final int feelsC = _toCelsius(weather.feelsLike).toInt();
    final int laterC = _toCelsius(weather.forecastLater).toInt();
    final int eveningC = _toCelsius(weather.forecastEvening).toInt();
    final int nightC = _toCelsius(weather.forecastNight).toInt();

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CURRENTLY',
                      style: TextStyle(
                          color: Colors.white30,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('$tempC°',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 72,
                              fontWeight: FontWeight.w200,
                              height: 1.1)),
                      const SizedBox(width: 10),
                      Text('Feels $feelsC°',
                          style: const TextStyle(
                              color: Color(0xFF4A9EFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(weather.condition.toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFFD4A843),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF4A9EFF).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('💧 ${weather.humidity}%',
                            style: const TextStyle(
                                color: Color(0xFF4A9EFF),
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.cloud_outlined, color: Colors.white, size: 80),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Divider(color: Colors.white10, height: 1),
        ),
        Row(
          children: [
            _DetailChip(
                icon: Icons.subdirectory_arrow_right,
                label: 'WIND SPEED',
                value: '${weather.windSpeed.toInt()} ${settings.speedUnit}'),
            const SizedBox(width: 20),
            _DetailChip(
                icon: Icons.water_drop_outlined,
                label: 'HUMIDITY',
                value: '${weather.humidity}%'),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ForecastCol(
                label: 'Later', icon: Icons.wb_cloudy_outlined, tempC: laterC),
            _ForecastCol(
                label: 'Evening',
                icon: Icons.location_city_outlined,
                tempC: eveningC),
            _ForecastCol(
                label: 'Night',
                icon: Icons.nightlight_round_outlined,
                tempC: nightC),
          ],
        ),
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _DetailChip(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8)),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ForecastCol extends StatelessWidget {
  final String label;
  final IconData icon;
  // FIX: renamed from `temp` (raw °F) to `tempC` (converted °C int).
  final int tempC;
  const _ForecastCol(
      {required this.label, required this.icon, required this.tempC});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 12),
        Text('$tempC°',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}
