import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/weather_data.dart';
import '../services/settings_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WEATHER WIDGET
// Bug fixes + performance improvements
// ─────────────────────────────────────────────────────────────────────────────

const Color _kGold = Color(0xFFD4A843);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kSurface = Color(0xFF141414);
const Color _kBorder = Color(0x14FFFFFF);

class WeatherWidget extends StatelessWidget {
  const WeatherWidget({
    super.key,
    this.weather,
    this.isLoading = false,
    this.onRetry,
  });

  final WeatherData? weather;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact =
            constraints.maxHeight < 220.0 || constraints.maxWidth < 280.0;

        return Container(
          padding: EdgeInsets.all(compact ? 12.0 : 24.0),
          decoration: BoxDecoration(
            color: _kSurface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(compact ? 20.0 : 28.0),
            border: Border.all(
              color: _kBorder,
              width: 1,
            ),
          ),
          child: ClipRect(
            child: _WeatherBody(
              weather: weather,
              isLoading: isLoading,
              onRetry: onRetry,
              settings: settings,
              compact: compact,
            ),
          ),
        );
      },
    );
  }
}

class _WeatherBody extends StatelessWidget {
  const _WeatherBody({
    required this.weather,
    required this.isLoading,
    required this.onRetry,
    required this.settings,
    required this.compact,
  });

  final WeatherData? weather;
  final bool isLoading;
  final VoidCallback? onRetry;
  final SettingsService settings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactWeatherBody(
        weather: weather,
        isLoading: isLoading,
        onRetry: onRetry,
        settings: settings,
      );
    }

    return _FullWeatherBody(
      weather: weather,
      isLoading: isLoading,
      onRetry: onRetry,
      settings: settings,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPACT BODY
// ─────────────────────────────────────────────────────────────────────────────

class _CompactWeatherBody extends StatelessWidget {
  const _CompactWeatherBody({
    required this.weather,
    required this.isLoading,
    required this.onRetry,
    required this.settings,
  });

  final WeatherData? weather;
  final bool isLoading;
  final VoidCallback? onRetry;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    if (isLoading && weather == null) {
      return const Center(
        child: CupertinoActivityIndicator(
          color: _kGold,
          radius: 12,
        ),
      );
    }

    if (weather == null) {
      return _CompactErrorState(onRetry: onRetry);
    }

    final WeatherData data = weather!;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 230,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _WeatherIcon(condition: data.condition, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.condition.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  data.temperature.round().toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    fontWeight: FontWeight.w300,
                    height: 0.9,
                    fontFeatures: <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 5),
                  child: Text(
                    settings.useKmh ? '°C' : '°F',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _MiniInfo(
                  icon: CupertinoIcons.thermometer,
                  text:
                      'Feels ${data.feelsLike.round()}${settings.useKmh ? "°C" : "°F"}',
                ),
                const SizedBox(width: 12),
                _MiniInfo(
                  icon: CupertinoIcons.drop_fill,
                  text: '${data.humidity}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactErrorState extends StatelessWidget {
  const _CompactErrorState({
    required this.onRetry,
  });

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.white30,
              size: 32,
            ),
            const SizedBox(height: 8),
            const Text(
              'Weather Offline',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: _kGold.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Text(
                    'RETRY',
                    style: TextStyle(
                      color: _kGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FULL BODY
// ─────────────────────────────────────────────────────────────────────────────

class _FullWeatherBody extends StatelessWidget {
  const _FullWeatherBody({
    required this.weather,
    required this.isLoading,
    required this.onRetry,
    required this.settings,
  });

  final WeatherData? weather;
  final bool isLoading;
  final VoidCallback? onRetry;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(settings: settings),
          const SizedBox(height: 24),
          if (isLoading && weather == null)
            const _FullLoadingState()
          else if (weather == null)
            _FullErrorState(onRetry: onRetry)
          else
            _WeatherContent(
              weather: weather!,
              settings: settings,
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.settings,
  });

  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        const Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
              children: <InlineSpan>[
                TextSpan(text: 'Live weather '),
                TextSpan(
                  text: 'at your location',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
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

class _FullLoadingState extends StatelessWidget {
  const _FullLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: CupertinoActivityIndicator(
          color: _kGold,
          radius: 14,
        ),
      ),
    );
  }
}

class _FullErrorState extends StatelessWidget {
  const _FullErrorState({
    required this.onRetry,
  });

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.cloud_off_rounded,
                color: Colors.white24,
                size: 24,
              ),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Weather Link Offline',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 16),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
              color: _kGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              onPressed: onRetry,
              child: const Text(
                'RETRY',
                style: TextStyle(
                  color: Color(0xFFEDD068),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEATHER CONTENT
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({
    required this.weather,
    required this.settings,
  });

  final WeatherData weather;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final String tempUnit = settings.useKmh ? '°C' : '°F';
    final String windUnit = settings.useKmh ? 'km/h' : 'mph';

    final double windValue =
        settings.useKmh ? weather.windSpeed * 3.6 : weather.windSpeed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'CURRENTLY',
                    style: TextStyle(
                      color: Colors.white30,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          '${weather.temperature.round()}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w200,
                            height: 1.1,
                            fontFeatures: <ui.FontFeature>[
                              ui.FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          tempUnit,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Feels ${weather.feelsLike.round()}°',
                          style: const TextStyle(
                            color: _kBlue,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        weather.condition.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kGold,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      _HumidityBadge(humidity: weather.humidity),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _WeatherIcon(
              condition: weather.condition,
              size: 72,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Divider(color: Colors.white10, height: 1),
        ),
        Row(
          children: <Widget>[
            _DetailChip(
              icon: Icons.air_rounded,
              label: 'WIND SPEED',
              value: '${windValue.round()} $windUnit',
            ),
            const SizedBox(width: 20),
            _DetailChip(
              icon: Icons.water_drop_outlined,
              label: 'HUMIDITY',
              value: '${weather.humidity}%',
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _ForecastCol(
              label: 'Later',
              icon: Icons.wb_cloudy_outlined,
              temp: weather.forecastLater,
              unit: tempUnit,
            ),
            _ForecastCol(
              label: 'Evening',
              icon: Icons.location_city_outlined,
              temp: weather.forecastEvening,
              unit: tempUnit,
            ),
            _ForecastCol(
              label: 'Night',
              icon: Icons.nightlight_round_outlined,
              temp: weather.forecastNight,
              unit: tempUnit,
            ),
          ],
        ),
      ],
    );
  }
}

class _HumidityBadge extends StatelessWidget {
  const _HumidityBadge({
    required this.humidity,
  });

  final int humidity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '💧 $humidity%',
        style: const TextStyle(
          color: _kBlue,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            color: Colors.white54,
            size: 14,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            color: Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastCol extends StatelessWidget {
  const _ForecastCol({
    required this.label,
    required this.icon,
    required this.temp,
    required this.unit,
  });

  final String label;
  final IconData icon;
  final double temp;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Icon(
              icon,
              color: Colors.white70,
              size: 24,
            ),
            const SizedBox(height: 12),
            Text(
              '${temp.round()}$unit',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherIcon extends StatelessWidget {
  const _WeatherIcon({
    required this.condition,
    required this.size,
  });

  final String condition;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String normalized = condition.toLowerCase();

    IconData icon = Icons.cloud_outlined;
    Color color = Colors.white;

    if (normalized.contains('clear')) {
      icon = Icons.wb_sunny_rounded;
      color = const Color(0xFFFFD60A);
    } else if (normalized.contains('few') || normalized.contains('partly')) {
      icon = Icons.wb_cloudy_rounded;
      color = const Color(0xFFFFD60A);
    } else if (normalized.contains('rain') ||
        normalized.contains('drizzle') ||
        normalized.contains('shower')) {
      icon = Icons.water_drop_rounded;
      color = _kBlue;
    } else if (normalized.contains('thunder')) {
      icon = Icons.thunderstorm_rounded;
      color = const Color(0xFFFFCC00);
    } else if (normalized.contains('snow')) {
      icon = Icons.ac_unit_rounded;
      color = Colors.white;
    } else if (normalized.contains('fog') ||
        normalized.contains('mist') ||
        normalized.contains('haze') ||
        normalized.contains('smoke')) {
      icon = Icons.cloud_rounded;
      color = Colors.white60;
    } else if (normalized.contains('overcast') ||
        normalized.contains('cloud')) {
      icon = Icons.cloud_rounded;
      color = Colors.white70;
    }

    return Icon(
      icon,
      color: color,
      size: size,
    );
  }
}
