import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/trip_data.dart';
import '../services/settings_service.dart';

class TripStatsWidget extends StatelessWidget {
  final List<TripPoint> points;
  final double avgSpeedMph;
  final double maxSpeedMph;
  final double distanceMiles;
  final double altitudeFt;
  final Duration tripTime;
  final Duration stoppedTime;

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

  String _formatDuration(Duration d) {
    if (d.isNegative) return "00:00";
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;

    // Unit Conversion Logic
    final String speedUnit = settings.speedUnit.toUpperCase();
    final String distUnit = settings.distanceUnit.toUpperCase();
    final String altUnit = settings.useKmh ? 'M' : 'FT';

    final double displayDistance = settings.toDisplayDistance(distanceMiles);
    final double displayMaxSpeed = settings.toDisplaySpeed(maxSpeedMph);
    final double displayAvgSpeed = settings.toDisplaySpeed(avgSpeedMph);
    final double displayAltitude =
        settings.useKmh ? altitudeFt * 0.3048 : altitudeFt;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF222222), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Stats Grid ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _StatRow(
                  label: 'TIME',
                  left: _StatCell(
                      title: 'Total Duration',
                      value: _formatDuration(tripTime)),
                  right: _StatCell(
                      title: 'Time Stopped',
                      value: _formatDuration(stoppedTime)),
                ),
                const _Divider(),
                _StatRow(
                  label: 'SPEED',
                  left: _StatCell(
                      title: 'Max ($speedUnit)',
                      value: displayMaxSpeed.toInt().toString()),
                  right: _StatCell(
                      title: 'Avg ($speedUnit)',
                      value: displayAvgSpeed.toInt().toString()),
                ),
                const _Divider(),
                _StatRow(
                  label: 'PATH',
                  left: _StatCell(
                      title: distUnit,
                      value: displayDistance.toStringAsFixed(1)),
                  right: _StatCell(
                      title: 'Current Alt ($altUnit)',
                      value: displayAltitude.toInt().toString()),
                ),
              ],
            ),
          ),

          // ── Live Line Charts ──────────────────────────────────────────────
          if (points.length > 2) ...[
            const Divider(color: Color(0xFF222222), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChartSection(
                    title: 'SPEED PROFILE ($speedUnit)',
                    color: const Color(0xFF4A9EFF),
                    data: points
                        .map((p) => settings.toDisplaySpeed(p.speedMph))
                        .toList(),
                  ),
                  const SizedBox(height: 28),
                  _ChartSection(
                    title: 'ALTITUDE PROFILE ($altUnit)',
                    color: const Color(0xFF4ECDC4),
                    data: points
                        .map((p) => settings.useKmh
                            ? p.altitudeFt * 0.3048
                            : p.altitudeFt)
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final Widget left, right;
  const _StatRow(
      {required this.label, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF444444),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(child: left),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String title, value;
  const _StatCell({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(color: Color(0xFF222222), height: 1, thickness: 1);
}

class _ChartSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<double> data;

  const _ChartSection(
      {required this.title, required this.color, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return const SizedBox.shrink();

    // PERFORMANCE: Sample max 60 points for high-frequency live rendering
    final int step = (data.length / 60).ceil().clamp(1, data.length);
    final List<double> sampled = [];
    for (int i = 0; i < data.length; i += step) {
      sampled.add(data[i]);
    }

    final double minVal = sampled.reduce((a, b) => a < b ? a : b);
    final double maxVal = sampled.reduce((a, b) => a > b ? a : b);
    final double range = (maxVal - minVal).clamp(1.0, double.infinity);

    final List<FlSpot> spots = List.generate(
      sampled.length,
      (i) => FlSpot(i.toDouble(), sampled[i]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color.withValues(alpha: 0.6), // FIXED
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 80,
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              minY: minVal - (range * 0.1),
              maxY: maxVal + (range * 0.1),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.35,
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
                      colors: [
                        color.withValues(alpha: 0.2), // FIXED
                        color.withValues(alpha: 0.0), // FIXED
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
