import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/weather_data.dart';
import '../services/settings_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WEATHER WIDGET — Optimized Liquid Gold Edition
// Fixed Flutter Web EllipsisFragment hit-test crash
// ═══════════════════════════════════════════════════════════════════════════════

// ── Palette ──────────────────────────────────────────────────────────────────
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFEDD068);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kSurface = Color(0xFF141414);
const Color _kSurfaceDeep = Color(0xFF0D0D0D);
const Color _kBorder = Color(0x18FFFFFF);

// ── Layout tokens ────────────────────────────────────────────────────────────
const double _kCompactWidth = 280.0;
const double _kCompactHeight = 220.0;

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
        final bool compact = constraints.maxHeight < _kCompactHeight ||
            constraints.maxWidth < _kCompactWidth;

        final double padding = compact ? 12.0 : 24.0;
        final double radius = compact ? 20.0 : 28.0;

        return RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: _kBorder,
                width: 1,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: <Widget>[
                  const Positioned.fill(
                    child: _WeatherBackgroundGlow(),
                  ),
                  Padding(
                    padding: EdgeInsets.all(padding),
                    child: _WeatherBody(
                      weather: weather,
                      isLoading: isLoading,
                      onRetry: onRetry,
                      settings: settings,
                      compact: compact,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAFE TEXT
// Prevents Flutter Web text hit-test crash:
// Assertion failed: fragment is! EllipsisFragment
// ═══════════════════════════════════════════════════════════════════════════════

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign,
    this.softWrap = false,
    this.overflow = TextOverflow.clip,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        softWrap: softWrap,
        style: style,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND
// ═══════════════════════════════════════════════════════════════════════════════

class _WeatherBackgroundGlow extends StatelessWidget {
  const _WeatherBackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.1,
          colors: <Color>[
            _kGold.withValues(alpha: 0.13),
            _kSurface,
            _kSurfaceDeep,
          ],
          stops: const <double>[0.0, 0.48, 1.0],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BODY SWITCHER
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT BODY
// ═══════════════════════════════════════════════════════════════════════════════

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
      return const _CompactLoadingState();
    }

    if (weather == null) {
      return _CompactErrorState(onRetry: onRetry);
    }

    final WeatherData data = weather!;
    final String tempUnit = _temperatureUnit(settings);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 236,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _WeatherIcon(
                  condition: data.condition,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SafeText(
                    data.condition.toUpperCase(),
                    maxLines: 1,
                    style: const TextStyle(
                      color: _kGoldSoft,
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
                    tempUnit,
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
                Expanded(
                  child: _MiniInfo(
                    icon: CupertinoIcons.thermometer,
                    text: 'Feels ${data.feelsLike.round()}$tempUnit',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniInfo(
                    icon: CupertinoIcons.drop_fill,
                    text: '${data.humidity}%',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactLoadingState extends StatelessWidget {
  const _CompactLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CupertinoActivityIndicator(
        color: _kGold,
        radius: 12,
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
            const _SafeText(
              'Weather Offline',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 10),
              _RetryButton(
                onPressed: onRetry!,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FULL BODY
// ═══════════════════════════════════════════════════════════════════════════════

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
    final Widget content;

    if (isLoading && weather == null) {
      content = const _FullLoadingState();
    } else if (weather == null) {
      content = _FullErrorState(onRetry: onRetry);
    } else {
      content = _WeatherContent(
        weather: weather!,
        settings: settings,
        refreshing: isLoading,
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Header(settings: settings),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: content,
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
            overflow: TextOverflow.clip,
            softWrap: false,
          ),
        ),
        const SizedBox(width: 12),
        _UnitBadge(
          label: settings.useKmh ? 'METRIC' : 'IMPERIAL',
        ),
      ],
    );
  }
}

class _UnitBadge extends StatelessWidget {
  const _UnitBadge({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: _SafeText(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

class _FullLoadingState extends StatelessWidget {
  const _FullLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey<String>('weather-loading'),
      height: 180,
      child: Center(
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
    return SizedBox(
      key: const ValueKey<String>('weather-error'),
      height: 170,
      child: Center(
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
                  child: _SafeText(
                    'Weather Link Offline',
                    maxLines: 1,
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
              _RetryButton(
                onPressed: onRetry!,
                compact: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEATHER CONTENT
// ═══════════════════════════════════════════════════════════════════════════════

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({
    required this.weather,
    required this.settings,
    required this.refreshing,
  });

  final WeatherData weather;
  final SettingsService settings;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final String tempUnit = _temperatureUnit(settings);
    final String windUnit = _windUnit(settings);
    final double windValue = _displayWindSpeed(
      weather.windSpeed,
      settings,
    );

    return Opacity(
      key: const ValueKey<String>('weather-content'),
      opacity: refreshing ? 0.72 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: _TemperatureBlock(
                  weather: weather,
                  tempUnit: tempUnit,
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
            child: Divider(
              color: Colors.white10,
              height: 1,
            ),
          ),
          Row(
            children: <Widget>[
              _DetailChip(
                icon: Icons.air_rounded,
                label: 'WIND SPEED',
                value: '${windValue.round()} $windUnit',
              ),
              const SizedBox(width: 18),
              _DetailChip(
                icon: Icons.water_drop_outlined,
                label: 'HUMIDITY',
                value: '${weather.humidity}%',
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
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
      ),
    );
  }
}

class _TemperatureBlock extends StatelessWidget {
  const _TemperatureBlock({
    required this.weather,
    required this.tempUnit,
  });

  final WeatherData weather;
  final String tempUnit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SafeText(
          'CURRENTLY',
          maxLines: 1,
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
              _SafeText(
                'Feels ${weather.feelsLike.round()}°',
                maxLines: 1,
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: _SafeText(
                weather.condition.toUpperCase(),
                maxLines: 1,
                style: const TextStyle(
                  color: _kGoldSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            _HumidityBadge(humidity: weather.humidity),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMALL COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════════

class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.onPressed,
    required this.compact,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 24,
        vertical: compact ? 7 : 0,
      ),
      minSize: compact ? 0 : 36,
      color: _kGold.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(compact ? 99 : 12),
      onPressed: onPressed,
      child: const _SafeText(
        'RETRY',
        maxLines: 1,
        style: TextStyle(
          color: _kGoldSoft,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _kBlue.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: _SafeText(
          '💧 $humidity%',
          maxLines: 1,
          style: const TextStyle(
            color: _kBlue,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          icon,
          color: Colors.white54,
          size: 14,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: _SafeText(
            text,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    _SafeText(
                      label,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _SafeText(
                      value,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
            _SafeText(
              label.toUpperCase(),
              maxLines: 1,
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
            _SafeText(
              '${temp.round()}$unit',
              maxLines: 1,
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

// ═══════════════════════════════════════════════════════════════════════════════
// WEATHER ICON
// ═══════════════════════════════════════════════════════════════════════════════

class _WeatherIcon extends StatelessWidget {
  const _WeatherIcon({
    required this.condition,
    required this.size,
  });

  final String condition;
  final double size;

  @override
  Widget build(BuildContext context) {
    final _WeatherIconData data = _resolveWeatherIcon(condition);

    return Icon(
      data.icon,
      color: data.color,
      size: size,
    );
  }
}

class _WeatherIconData {
  const _WeatherIconData({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;
}

_WeatherIconData _resolveWeatherIcon(String condition) {
  final String value = condition.trim().toLowerCase();

  if (value.contains('clear') || value.contains('sun')) {
    return const _WeatherIconData(
      icon: Icons.wb_sunny_rounded,
      color: Color(0xFFFFD60A),
    );
  }

  if (value.contains('few') ||
      value.contains('partly') ||
      value.contains('scattered')) {
    return const _WeatherIconData(
      icon: Icons.wb_cloudy_rounded,
      color: Color(0xFFFFD60A),
    );
  }

  if (value.contains('rain') ||
      value.contains('drizzle') ||
      value.contains('shower')) {
    return const _WeatherIconData(
      icon: Icons.water_drop_rounded,
      color: _kBlue,
    );
  }

  if (value.contains('thunder') || value.contains('storm')) {
    return const _WeatherIconData(
      icon: Icons.thunderstorm_rounded,
      color: Color(0xFFFFCC00),
    );
  }

  if (value.contains('snow') || value.contains('sleet')) {
    return const _WeatherIconData(
      icon: Icons.ac_unit_rounded,
      color: Colors.white,
    );
  }

  if (value.contains('fog') ||
      value.contains('mist') ||
      value.contains('haze') ||
      value.contains('smoke') ||
      value.contains('dust')) {
    return const _WeatherIconData(
      icon: Icons.cloud_rounded,
      color: Colors.white60,
    );
  }

  if (value.contains('overcast') || value.contains('cloud')) {
    return const _WeatherIconData(
      icon: Icons.cloud_rounded,
      color: Colors.white70,
    );
  }

  return const _WeatherIconData(
    icon: Icons.cloud_outlined,
    color: Colors.white70,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNIT HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

String _temperatureUnit(SettingsService settings) {
  return settings.useKmh ? '°C' : '°F';
}

String _windUnit(SettingsService settings) {
  return settings.useKmh ? 'km/h' : 'mph';
}

/// Assumption:
/// weather.windSpeed is stored internally as metres/second.
/// Metric display converts m/s → km/h.
/// Imperial display converts m/s → mph.
double _displayWindSpeed(
  double windSpeedMetersPerSecond,
  SettingsService settings,
) {
  if (settings.useKmh) {
    return windSpeedMetersPerSecond * 3.6;
  }

  return windSpeedMetersPerSecond * 2.2369362921;
}
