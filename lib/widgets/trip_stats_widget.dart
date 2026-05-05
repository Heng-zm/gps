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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF222222)),
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

          // ── Live Charts ────────────────────────────────────────────────────
          if (points.length > 2) ...[
            const Divider(color: Color(0xFF222222), height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ChartSection(
                    title: 'SPEED HISTORY ($speedUnit)',
                    color: const Color(0xFF4A9EFF),
                    // Map points to speed using preferred units
                    data: points
                        .map((p) => settings.toDisplaySpeed(p.speedMph))
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  _ChartSection(
                    title: 'ALTITUDE PROFILE ($altUnit)',
                    color: const Color(0xFF4ECDC4),
                    // Map points to altitude using preferred units
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF555555),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
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
              color: Color(0xFF777777),
              fontSize: 10,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
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
      const Divider(color: Color(0xFF222222), height: 1);
}

class _ChartSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<double> data;

  const _ChartSection(
      {required this.title, required this.color, required this.data});

  @override
  Widget build(BuildContext context) {
    // PERFORMANCE FIX: Data Downsampling
    // LineChart cannot handle thousands of points. We sample a maximum of 50 spots.
    final int samplingStep = (data.length / 50).ceil().clamp(1, data.length);
    final List<double> sampledData = [];
    for (int i = 0; i < data.length; i += samplingStep) {
      sampledData.add(data[i]);
    }

    final double minVal = sampledData.reduce((a, b) => a < b ? a : b);
    final double maxVal = sampledData.reduce((a, b) => a > b ? a : b);
    final double range = (maxVal - minVal).clamp(1.0, double.infinity);

    final List<FlSpot> spots = List.generate(
      sampledData.length,
      (i) => FlSpot(i.toDouble(), sampledData[i]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
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
              minY: minVal - (range * 0.15),
              maxY: maxVal + (range * 0.15),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  // UPGRADE: Prevents the curve from dipping below 0 or overshooting peaks
                  preventCurveOverShooting: true,
                  // Optimization: Adjust smoothness (0.35 is the sweet spot for GPS data)
                  curveSmoothness: 0.35,
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
                        color.withValues(alpha: 0.25),
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
    );
  }
}
