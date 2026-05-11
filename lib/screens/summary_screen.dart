import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/trip_data.dart';
import '../services/settings_service.dart';
import '../widgets/ai_analysis_card.dart';
import '../widgets/ai_chat_sheet.dart';
import 'map_screen.dart';
// Important: SavedTrip and SavedRoutePoint models are imported from history_screen
import 'history_screen.dart';

class SummaryScreen extends StatefulWidget {
  final TripSummary summary;
  const SummaryScreen({super.key, required this.summary});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _isSaving = false;
  bool _isSaved = false;

  /// Handles the Supabase upload logic
  Future<void> _handleSaveTrip() async {
    if (_isSaved || _isSaving) return;

    setState(() => _isSaving = true);
    await HapticFeedback.mediumImpact();

    // NEW: Map the live TripPoints to the SavedRoutePoint format
    final routePoints = widget.summary.points.map((p) {
      return SavedRoutePoint(
        lat: p.position.latitude,
        lng: p.position.longitude,
        speedMph: p.speedMph,
      );
    }).toList();

    // Convert TripSummary (live data) to SavedTrip (DB format)
    final tripToSave = SavedTrip(
      id: widget.summary.id,
      date: widget.summary.date,
      distanceMiles: widget.summary.distanceMiles,
      maxSpeedMph: widget.summary.maxSpeedMph,
      avgSpeedMph: widget.summary.avgSpeedMph,
      totalTime: widget.summary.totalTime,
      altitudeGainFt: widget.summary.altitudeGainFt,
      route: routePoints, // FIX: Pass the newly mapped route here
    );

    final success = await SavedTrip.saveTrip(tripToSave);

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) _isSaved = true;
      });

      if (success) {
        await HapticFeedback.lightImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip successfully synced to cloud.'),
              backgroundColor: Color(0xFF4ECDC4),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cloud sync failed. Check connection.'),
              backgroundColor: Color(0xFFE74C3C),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final distUnit = settings.distanceUnit.toUpperCase();
    final speedUnit = settings.speedUnit.toUpperCase();
    final altUnit = settings.useKmh ? 'M' : 'FT';
    final altFactor = settings.useKmh ? 0.3048 : 1.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: _AiFab(summary: widget.summary),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                child: Column(
                  children: [
                    _HeroDistanceCard(
                      distance: settings
                          .toDisplayDistance(widget.summary.distanceMiles),
                      unit: distUnit,
                    ),
                    const SizedBox(height: 16),
                    AiAnalysisCard(summary: widget.summary),
                    const SizedBox(height: 16),
                    _SectionCard(title: 'TIME METRICS', children: [
                      _StatRow(
                        left: _StatBox(
                            label: 'TOTAL TIME',
                            value: widget.summary.formattedTotalTime,
                            icon: CupertinoIcons.timer),
                        right: _StatBox(
                            label: 'STOPPED',
                            value: widget.summary.formattedStoppedTime,
                            icon: CupertinoIcons.pause_circle),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _SectionCard(
                        title: 'SPEED ANALYTICS ($speedUnit)',
                        children: [
                          _StatRow(
                            left: _StatBox(
                                label: 'MAXIMUM',
                                value:
                                    '${settings.toDisplaySpeed(widget.summary.maxSpeedMph).toInt()}',
                                icon: CupertinoIcons.speedometer,
                                accent: true),
                            right: _StatBox(
                                label: 'AVERAGE',
                                value:
                                    '${settings.toDisplaySpeed(widget.summary.avgSpeedMph).toInt()}',
                                icon: CupertinoIcons.chart_bar),
                          ),
                          if (widget.summary.points.length > 5) ...[
                            const SizedBox(height: 20),
                            _PerformantChart(
                                points: widget.summary.points,
                                getValue: (p) =>
                                    settings.toDisplaySpeed(p.speedMph),
                                color: const Color(0xFF4A9EFF)),
                          ],
                        ]),
                    const SizedBox(height: 12),
                    _SectionCard(
                        title: 'ELEVATION PROFILE ($altUnit)',
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: _StatBox(
                                      label: 'GAIN',
                                      value:
                                          '+${(widget.summary.altitudeGainFt * altFactor).toInt()}',
                                      icon: CupertinoIcons.graph_square,
                                      accent: true)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _StatBox(
                                      label: 'MAX',
                                      value:
                                          '${(widget.summary.maxAltitudeFt * altFactor).toInt()}',
                                      icon: CupertinoIcons.chevron_up)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _StatBox(
                                      label: 'MIN',
                                      value:
                                          '${(widget.summary.minAltitudeFt * altFactor).toInt()}',
                                      icon: CupertinoIcons.chevron_down)),
                            ],
                          ),
                          if (widget.summary.points.length > 5) ...[
                            const SizedBox(height: 20),
                            _PerformantChart(
                                points: widget.summary.points,
                                getValue: (p) => p.altitudeFt * altFactor,
                                color: const Color(0xFF4ECDC4)),
                          ],
                        ]),
                    const SizedBox(height: 32),
                    _SaveButton(
                        isSaving: _isSaving,
                        isSaved: _isSaved,
                        onTap: _handleSaveTrip),
                    const SizedBox(height: 12),
                    _DismissButton(),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          _RoundIconButton(
              icon: CupertinoIcons.chevron_back,
              onTap: () => Navigator.pop(context)),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SESSION OVERVIEW',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              Text('Performance Analytics',
                  style: TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          _MapPreviewButton(points: widget.summary.points),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool isSaving, isSaved;
  final VoidCallback onTap;
  const _SaveButton(
      {required this.isSaving, required this.isSaved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF4ECDC4);
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 18),
        color: isSaved ? const Color(0xFF1A1A1A) : teal,
        borderRadius: BorderRadius.circular(20),
        onPressed: onTap,
        child: isSaving
            ? const CupertinoActivityIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      isSaved
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.cloud_upload_fill,
                      color: isSaved ? teal : Colors.black,
                      size: 18),
                  const SizedBox(width: 10),
                  Text(isSaved ? 'TRIP SAVED' : 'SAVE TO HISTORY',
                      style: TextStyle(
                          color: isSaved ? teal : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                ],
              ),
      ),
    );
  }
}

class _HeroDistanceCard extends StatelessWidget {
  final double distance;
  final String unit;
  const _HeroDistanceCard({required this.distance, required this.unit});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF4ECDC4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: teal.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOTAL DISTANCE',
              style: TextStyle(
                  color: teal.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(distance.toStringAsFixed(2),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.w300)),
              const SizedBox(width: 8),
              Text(unit,
                  style: const TextStyle(
                      color: teal, fontSize: 20, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
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
    final color = accent ? const Color(0xFF4ECDC4) : const Color(0xFF666666);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent ? color.withValues(alpha: 0.05) : const Color(0xFF181818),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w800))
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _PerformantChart extends StatelessWidget {
  final List<TripPoint> points;
  final double Function(TripPoint) getValue;
  final Color color;
  const _PerformantChart(
      {required this.points, required this.getValue, required this.color});

  @override
  Widget build(BuildContext context) {
    // Sampling logic: show at most 60 points to keep UI performance high
    final List<FlSpot> spots = [];
    final int samplingRate =
        (points.length / 60).ceil().clamp(1, points.length);
    for (int i = 0; i < points.length; i += samplingRate) {
      spots.add(FlSpot(i.toDouble(), getValue(points[i])));
    }
    return RepaintBoundary(
      child: SizedBox(
        height: 100,
        child: LineChart(LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.35,
                preventCurveOverShooting: true,
                color: color,
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.2),
                      color.withValues(alpha: 0.0)
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ))
          ],
        )),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final Widget left, right;
  const _StatRow({required this.left, required this.right});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right)
      ]);
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: Color(0xFF4ECDC4),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5)),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }
}

class _AiFab extends StatelessWidget {
  final TripSummary summary;
  const _AiFab({required this.summary});
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => AiChatSheet(summary: summary)),
      backgroundColor: const Color(0xFFA855F7),
      icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
      label: const Text('ASK AI',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 20)));
  }
}

class _MapPreviewButton extends StatelessWidget {
  final List<TripPoint> points;
  const _MapPreviewButton({required this.points});
  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF4ECDC4);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      minSize: 40,
      color: teal.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      onPressed: () => Navigator.push(
          context,
          CupertinoPageRoute(
              builder: (_) => MapScreen(points: points, isLive: false))),
      child: const Row(children: [
        Icon(CupertinoIcons.map_fill, color: teal, size: 14),
        SizedBox(width: 8),
        Text('VIEW MAP',
            style: TextStyle(
                color: teal, fontSize: 12, fontWeight: FontWeight.w800))
      ]),
    );
  }
}

class _DismissButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 18),
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        onPressed: () => Navigator.pop(context),
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
