// ignore_for_file: unused_element_parameter

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/trip_data.dart';
import '../services/settings_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TRIP STATS WIDGET — Premium Optimized Version
// - Safer value formatting
// - Better responsive layout
// - Moving time + stopped ratio
// - Route quality summary
// - Chart downsampling + invalid value filtering
// - RepaintBoundary around charts for smoother scrolling
// ═══════════════════════════════════════════════════════════════════════════════

const Color _kCard = Color(0xFF111114);
const Color _kCardSoft = Color(0xFF17171B);
const Color _kBorder = Color(0x1AFFFFFF);
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD86B);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kTeal = Color(0xFF4ECDC4);
const Color _kGreen = Color(0xFF32D74B);
const Color _kRed = Color(0xFFFF453A);
const Color _kMuted = Color(0xFF777777);

const int _kMaxChartSamples = 64;

class TripStatsWidget extends StatelessWidget {
  const TripStatsWidget({
    super.key,
    required this.points,
    required this.avgSpeedMph,
    required this.maxSpeedMph,
    required this.distanceMiles,
    required this.altitudeFt,
    required this.tripTime,
    required this.stoppedTime,
  });

  final List<TripPoint> points;
  final double avgSpeedMph;
  final double maxSpeedMph;
  final double distanceMiles;
  final double altitudeFt;
  final Duration tripTime;
  final Duration stoppedTime;

  Duration get _movingTime {
    final Duration moving = tripTime - stoppedTime;
    return moving.isNegative ? Duration.zero : moving;
  }

  double get _stoppedPercent {
    final int total = math.max(0, tripTime.inSeconds);
    if (total == 0) return 0.0;

    final int stopped = stoppedTime.inSeconds.clamp(0, total).toInt();
    return stopped / total;
  }

  _RouteQuality get _routeQuality => _RouteQuality.fromPoints(points);

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;

    final String speedUnit = settings.speedUnit.toUpperCase();
    final String distUnit = settings.distanceUnit.toUpperCase();
    final String altUnit = settings.useKmh ? 'M' : 'FT';

    final double displayDistance = _safe(
      settings.toDisplayDistance(distanceMiles),
    );
    final double displayMaxSpeed = _safe(
      settings.toDisplaySpeed(maxSpeedMph),
    );
    final double displayAvgSpeed = _safe(
      settings.toDisplaySpeed(avgSpeedMph),
    );
    final double displayAltitude = _safe(
      settings.useKmh ? altitudeFt * 0.3048 : altitudeFt,
    );

    final _RouteQuality quality = _routeQuality;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.075),
            Colors.white.withValues(alpha: 0.035),
            Colors.white.withValues(alpha: 0.015),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        color: _kCard,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _kBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Header(
              pointCount: points.length,
              quality: quality,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: <Widget>[
                  _HeroGrid(
                    distance: displayDistance,
                    distanceUnit: distUnit,
                    avgSpeed: displayAvgSpeed,
                    maxSpeed: displayMaxSpeed,
                    speedUnit: speedUnit,
                    altitude: displayAltitude,
                    altUnit: altUnit,
                  ),
                  const SizedBox(height: 12),
                  _TimeStrip(
                    total: tripTime,
                    moving: _movingTime,
                    stopped: stoppedTime,
                    stoppedPercent: _stoppedPercent,
                  ),
                ],
              ),
            ),
            if (points.length > 2) ...<Widget>[
              const Divider(color: _kBorder, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _ChartSection(
                      title: 'SPEED PROFILE',
                      unit: speedUnit,
                      color: _kBlue,
                      data: points
                          .map((TripPoint point) {
                            return settings.toDisplaySpeed(point.speedMph);
                          })
                          .where((double value) => value.isFinite)
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 22),
                    _ChartSection(
                      title: 'ALTITUDE PROFILE',
                      unit: altUnit,
                      color: _kTeal,
                      data: points
                          .map((TripPoint point) {
                            return settings.useKmh
                                ? point.altitudeFt * 0.3048
                                : point.altitudeFt;
                          })
                          .where((double value) => value.isFinite)
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static double _safe(double value) {
    if (!value.isFinite) return 0.0;
    return value < 0.0 ? 0.0 : value;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.pointCount,
    required this.quality,
  });

  final int pointCount;
  final _RouteQuality quality;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: quality.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: quality.color.withValues(alpha: 0.18)),
            ),
            child: Icon(
              CupertinoIcons.chart_bar_alt_fill,
              color: quality.color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SafeText(
                  'TRIP STATS',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 2),
                _SafeText(
                  'Performance analytics',
                  maxLines: 1,
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _QualityPill(quality: quality, pointCount: pointCount),
        ],
      ),
    );
  }
}

class _QualityPill extends StatelessWidget {
  const _QualityPill({
    required this.quality,
    required this.pointCount,
  });

  final _RouteQuality quality;
  final int pointCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 128),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: quality.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: quality.color.withValues(alpha: 0.18)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              CupertinoIcons.checkmark_shield_fill,
              color: quality.color,
              size: 12,
            ),
            const SizedBox(width: 5),
            _SafeText(
              '${quality.score}% · $pointCount pts',
              maxLines: 1,
              style: TextStyle(
                color: quality.color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HERO STATS
// ═══════════════════════════════════════════════════════════════════════════════

class _HeroGrid extends StatelessWidget {
  const _HeroGrid({
    required this.distance,
    required this.distanceUnit,
    required this.avgSpeed,
    required this.maxSpeed,
    required this.speedUnit,
    required this.altitude,
    required this.altUnit,
  });

  final double distance;
  final String distanceUnit;
  final double avgSpeed;
  final double maxSpeed;
  final String speedUnit;
  final double altitude;
  final String altUnit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              flex: 2,
              child: _BigStatCard(
                title: 'DISTANCE',
                value: distance.toStringAsFixed(distance >= 10 ? 1 : 2),
                unit: distanceUnit,
                icon: CupertinoIcons.map_pin_ellipse,
                color: _kGoldSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SmallStatCard(
                title: 'ALT',
                value: altitude.round().toString(),
                unit: altUnit,
                icon: CupertinoIcons.arrow_up_right,
                color: _kTeal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _SmallStatCard(
                title: 'AVG',
                value: avgSpeed.round().toString(),
                unit: speedUnit,
                icon: CupertinoIcons.speedometer,
                color: _kBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SmallStatCard(
                title: 'MAX',
                value: maxSpeed.round().toString(),
                unit: speedUnit,
                icon: CupertinoIcons.bolt_fill,
                color: _kGold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BigStatCard extends StatelessWidget {
  const _BigStatCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _MetricSurface(
      color: color,
      child: Row(
        children: <Widget>[
          _MetricIcon(icon: icon, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: _NumberBlock(
              title: title,
              value: value,
              unit: unit,
              color: color,
              large: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallStatCard extends StatelessWidget {
  const _SmallStatCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _MetricSurface(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MetricIcon(icon: icon, color: color, size: 30),
          const SizedBox(height: 9),
          _NumberBlock(
            title: title,
            value: value,
            unit: unit,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _MetricSurface extends StatelessWidget {
  const _MetricSurface({
    required this.color,
    required this.child,
  });

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: child,
    );
  }
}

class _MetricIcon extends StatelessWidget {
  const _MetricIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

class _NumberBlock extends StatelessWidget {
  const _NumberBlock({
    required this.title,
    required this.value,
    required this.unit,
    required this.color,
    this.large = false,
  });

  final String title;
  final String value;
  final String unit;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SafeText(
          title,
          maxLines: 1,
          style: TextStyle(
            color: color.withValues(alpha: 0.80),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: large ? 32 : 25,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  fontFeatures: const <ui.FontFeature>[
                    ui.FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                unit,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  color: color,
                  fontSize: large ? 12 : 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TIME STRIP
// ═══════════════════════════════════════════════════════════════════════════════

class _TimeStrip extends StatelessWidget {
  const _TimeStrip({
    required this.total,
    required this.moving,
    required this.stopped,
    required this.stoppedPercent,
  });

  final Duration total;
  final Duration moving;
  final Duration stopped;
  final double stoppedPercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _kCardSoft.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _TimeItem(
                  label: 'TOTAL',
                  value: _formatDuration(total),
                  color: _kGoldSoft,
                ),
              ),
              Expanded(
                child: _TimeItem(
                  label: 'MOVING',
                  value: _formatDuration(moving),
                  color: _kGreen,
                ),
              ),
              Expanded(
                child: _TimeItem(
                  label: 'STOPPED',
                  value: _formatDuration(stopped),
                  color: _kRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StoppedProgress(percent: stoppedPercent),
        ],
      ),
    );
  }
}

class _TimeItem extends StatelessWidget {
  const _TimeItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _SafeText(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color.withValues(alpha: 0.82),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 5),
        _SafeText(
          value,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
      ],
    );
  }
}

class _StoppedProgress extends StatelessWidget {
  const _StoppedProgress({
    required this.percent,
  });

  final double percent;

  @override
  Widget build(BuildContext context) {
    final double safePercent = percent.clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 8,
        color: Colors.white.withValues(alpha: 0.06),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: safePercent,
          child: Container(
            decoration: BoxDecoration(
              color: _kRed.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHARTS
// ═══════════════════════════════════════════════════════════════════════════════

class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.title,
    required this.unit,
    required this.color,
    required this.data,
  });

  final String title;
  final String unit;
  final Color color;
  final List<double> data;

  @override
  Widget build(BuildContext context) {
    final List<double> sampled = _sampleData(data);

    if (sampled.length < 2) {
      return _ChartEmptyState(color: color);
    }

    final double minVal =
        sampled.fold<double>(double.infinity, (double a, double b) {
      return b < a ? b : a;
    });
    final double maxVal =
        sampled.fold<double>(double.negativeInfinity, (double a, double b) {
      return b > a ? b : a;
    });

    final double range = (maxVal - minVal).abs().clamp(1.0, double.infinity);
    final double minY = math.max(0.0, minVal - (range * 0.12));
    final double maxY = maxVal + (range * 0.12);

    final List<FlSpot> spots = List<FlSpot>.generate(
      sampled.length,
      (int index) => FlSpot(index.toDouble(), sampled[index]),
      growable: false,
    );

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _SafeText(
                title,
                maxLines: 1,
                style: TextStyle(
                  color: color.withValues(alpha: 0.78),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              _UnitPill(text: unit, color: color),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 94,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: math.max(1.0, range / 3.0),
                  getDrawingHorizontalLine: (_) {
                    return FlLine(
                      color: Colors.white.withValues(alpha: 0.045),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((LineBarSpot spot) {
                        return LineTooltipItem(
                          spot.y.toStringAsFixed(0),
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: <LineChartBarData>[
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.32,
                    preventCurveOverShooting: true,
                    color: color,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          color.withValues(alpha: 0.22),
                          color.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<double> _sampleData(List<double> source) {
    if (source.length <= _kMaxChartSamples) {
      return List<double>.unmodifiable(source);
    }

    final int step = (source.length / _kMaxChartSamples)
        .ceil()
        .clamp(1, source.length)
        .toInt();

    final List<double> sampled = <double>[];
    for (int i = 0; i < source.length; i += step) {
      final double value = source[i];
      if (value.isFinite) sampled.add(value < 0.0 ? 0.0 : value);
    }

    return List<double>.unmodifiable(sampled);
  }
}

class _ChartEmptyState extends StatelessWidget {
  const _ChartEmptyState({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: _SafeText(
        'Not enough data for chart',
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UnitPill extends StatelessWidget {
  const _UnitPill({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: _SafeText(
        text,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ROUTE QUALITY
// ═══════════════════════════════════════════════════════════════════════════════

class _RouteQuality {
  const _RouteQuality({
    required this.score,
    required this.color,
  });

  final int score;
  final Color color;

  static _RouteQuality fromPoints(List<TripPoint> points) {
    if (points.length < 3) {
      return const _RouteQuality(score: 45, color: _kGold);
    }

    int weakAccuracy = 0;
    int duplicateLike = 0;
    double? lastLat;
    double? lastLng;

    for (final TripPoint point in points) {
      final double acc = point.accuracyMeters;
      if (acc.isFinite && acc > 35.0) weakAccuracy++;

      final double lat = point.position.latitude;
      final double lng = point.position.longitude;
      if (lastLat != null && lastLng != null && lat == lastLat && lng == lastLng) {
        duplicateLike++;
      }
      lastLat = lat;
      lastLng = lng;
    }

    int score = 100;
    if (points.length < 10) score -= 16;
    score -= (weakAccuracy * 4).clamp(0, 30).toInt();
    score -= (duplicateLike * 2).clamp(0, 18).toInt();
    score = score.clamp(0, 100).toInt();

    final Color color;
    if (score >= 85) {
      color = _kGreen;
    } else if (score >= 65) {
      color = _kTeal;
    } else if (score >= 45) {
      color = _kGold;
    } else {
      color = _kRed;
    }

    return _RouteQuality(score: score, color: color);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMALL HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

String _formatDuration(Duration duration) {
  final Duration safe = duration.isNegative ? Duration.zero : duration;
  final int h = safe.inHours;
  final int m = safe.inMinutes.remainder(60);
  final int s = safe.inSeconds.remainder(60);

  if (h > 0) {
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        softWrap: false,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
