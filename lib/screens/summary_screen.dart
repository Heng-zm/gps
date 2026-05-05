import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/trip_data.dart';
import '../services/settings_service.dart';
import '../widgets/ai_analysis_card.dart';
import '../widgets/ai_chat_sheet.dart';
import 'map_screen.dart';

class SummaryScreen extends StatelessWidget {
  final TripSummary summary;
  const SummaryScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final speedUnit = settings.speedUnit.toUpperCase();
    final distUnit = settings.distanceUnit.toUpperCase();

    // Altitude logic: Metric (Meters) vs Imperial (Feet)
    final altUnit = settings.useKmh ? 'M' : 'FT';
    final altFactor = settings.useKmh ? 0.3048 : 1.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      // ── FEATURE: Floating AI Chat Assistant ────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => AiChatSheet(summary: summary),
          );
        },
        backgroundColor: const Color(0xFFA855F7),
        icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
        label: const Text(
          'ASK AI',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _HeroCard(
                        summary: summary,
                        settings: settings,
                        distUnit: distUnit),
                    const SizedBox(height: 16),

                    // GEMINI: Automatic Trip Analysis
                    AiAnalysisCard(summary: summary),

                    const SizedBox(height: 16),

                    // TIME SECTION
                    _SectionCard(title: 'TIME', children: [
                      _StatRow2(
                        left: _StatBox(
                            label: 'Total Time',
                            value: summary.formattedTotalTime,
                            icon: CupertinoIcons.clock),
                        right: _StatBox(
                            label: 'Stopped',
                            value: summary.formattedStoppedTime,
                            icon: CupertinoIcons.pause_circle),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    // SPEED SECTION
                    _SectionCard(title: 'SPEED ($speedUnit)', children: [
                      _StatRow2(
                        left: _StatBox(
                            label: 'Max Speed',
                            value:
                                '${settings.toDisplaySpeed(summary.maxSpeedMph).toInt()} $speedUnit',
                            icon: CupertinoIcons.speedometer,
                            accent: true),
                        right: _StatBox(
                            label: 'Avg Speed',
                            value:
                                '${settings.toDisplaySpeed(summary.avgSpeedMph).toInt()} $speedUnit',
                            icon: CupertinoIcons.arrow_right_circle),
                      ),
                      if (summary.points.length > 2) ...[
                        const SizedBox(height: 20),
                        _SpeedChart(points: summary.points, settings: settings),
                      ],
                    ]),
                    const SizedBox(height: 12),

                    // ALTITUDE SECTION
                    _SectionCard(title: 'ALTITUDE ($altUnit)', children: [
                      _StatRow3(
                        s1: _StatBox(
                            label: 'Gain',
                            value:
                                '+${(summary.altitudeGainFt * altFactor).toInt()} $altUnit',
                            icon: CupertinoIcons.arrow_up,
                            accent: true),
                        s2: _StatBox(
                            label: 'Max',
                            value:
                                '${(summary.maxAltitudeFt * altFactor).toInt()} $altUnit',
                            icon: CupertinoIcons.chevron_up),
                        s3: _StatBox(
                            label: 'Min',
                            value:
                                '${(summary.minAltitudeFt * altFactor).toInt()} $altUnit',
                            icon: CupertinoIcons.chevron_down),
                      ),
                      if (summary.points.length > 2) ...[
                        const SizedBox(height: 20),
                        _AltitudeChart(
                            points: summary.points, factor: altFactor),
                      ],
                    ]),

                    const SizedBox(height: 32),
                    _buildDoneButton(context),
                    const SizedBox(height: 60), // Extra space for FAB
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(CupertinoIcons.chevron_back,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TRIP SUMMARY',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
              Text('Performance Analytics',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
            ],
          ),
          const Spacer(),
          _buildMapButton(context),
        ],
      ),
    );
  }

  Widget _buildMapButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute(
            builder: (_) => MapScreen(points: summary.points, isLive: false)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: const Color(0xFF4ECDC4).withValues(alpha: 0.2)),
        ),
        child: const Row(
          children: [
            Icon(CupertinoIcons.map_fill, color: Color(0xFF4ECDC4), size: 14),
            SizedBox(width: 6),
            Text('MAP',
                style: TextStyle(
                    color: Color(0xFF4ECDC4),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('DISMISS',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 2)),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final TripSummary summary;
  final SettingsService settings;
  final String distUnit;
  const _HeroCard(
      {required this.summary, required this.settings, required this.distUnit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3330), Color(0xFF1A1A1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: const Color(0xFF4ECDC4).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL DISTANCE',
                  style: TextStyle(
                      color: const Color(0xFF4ECDC4).withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                      settings
                          .toDisplayDistance(summary.distanceMiles)
                          .toStringAsFixed(2),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.w200,
                          height: 1)),
                  const SizedBox(width: 8),
                  Text(distUnit,
                      style: const TextStyle(
                          color: Color(0xFF4ECDC4),
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          const Spacer(),
          _buildBadge(),
        ],
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border:
            Border.all(color: const Color(0xFF4ECDC4).withValues(alpha: 0.1)),
      ),
      child: const Icon(CupertinoIcons.flag_fill,
          color: Color(0xFF4ECDC4), size: 24),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.03))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF4ECDC4),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _StatRow2 extends StatelessWidget {
  final Widget left, right;
  const _StatRow2({required this.left, required this.right});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right)
      ]);
}

class _StatRow3 extends StatelessWidget {
  final Widget s1, s2, s3;
  const _StatRow3({required this.s1, required this.s2, required this.s3});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: s1),
        const SizedBox(width: 8),
        Expanded(child: s2),
        const SizedBox(width: 8),
        Expanded(child: s3)
      ]);
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final bool accent;
  const _StatBox(
      {required this.label,
      required this.value,
      required this.icon,
      this.accent = false});

  @override
  Widget build(BuildContext context) {
    final color = accent ? const Color(0xFF4ECDC4) : const Color(0xFF555555);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent
            ? const Color(0xFF4ECDC4).withValues(alpha: 0.05)
            : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: accent
            ? Border.all(color: const Color(0xFF4ECDC4).withValues(alpha: 0.15))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5))),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SpeedChart extends StatelessWidget {
  final List<TripPoint> points;
  final SettingsService settings;
  const _SpeedChart({required this.points, required this.settings});

  @override
  Widget build(BuildContext context) {
    final step = (points.length / 50).ceil().clamp(1, points.length);
    final List<FlSpot> spots = [];
    for (var i = 0; i < points.length; i += step) {
      spots.add(
          FlSpot(i.toDouble(), settings.toDisplaySpeed(points[i].speedMph)));
    }

    return SizedBox(
      height: 90,
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: const Color(0xFF4A9EFF),
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF4A9EFF).withValues(alpha: 0.2),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }
}

class _AltitudeChart extends StatelessWidget {
  final List<TripPoint> points;
  final double factor;
  const _AltitudeChart({required this.points, required this.factor});

  @override
  Widget build(BuildContext context) {
    final step = (points.length / 50).ceil().clamp(1, points.length);
    final List<FlSpot> spots = [];
    for (var i = 0; i < points.length; i += step) {
      spots.add(FlSpot(i.toDouble(), points[i].altitudeFt * factor));
    }

    return SizedBox(
      height: 90,
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: const Color(0xFF4ECDC4),
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF4ECDC4).withValues(alpha: 0.2),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }
}
