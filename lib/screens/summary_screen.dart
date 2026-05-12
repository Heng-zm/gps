import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_data.dart';
import '../services/settings_service.dart';
import '../widgets/ai_analysis_card.dart';
import '../widgets/ai_chat_sheet.dart';
import 'map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

const Color _kBg = Color(0xFF070707);
const Color _kCard = Color(0xFF111111);
const Color _kBorder = Color(0x14FFFFFF);
const Color _kTeal = Color(0xFF4ECDC4);
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD86B);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kPurple = Color(0xFFA855F7);
const Color _kRed = Color(0xFFE74C3C);
const Color _kGreen = Color(0xFF27AE60);

const int _kMaxChartSamples = 70;

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    required this.summary,
  });

  final TripSummary summary;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final SettingsService _settings = SettingsService.instance;

  bool _isSaving = false;
  bool _isSaved = false;
  bool _showCharts = true;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _handleSaveTrip() async {
    if (_isSaved || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    HapticFeedback.mediumImpact();

    try {
      final bool success = await _saveSummaryToHistory(widget.summary);

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _isSaved = success;
      });

      if (success) {
        HapticFeedback.lightImpact();
        _showSnack(
          message: 'Trip saved to history.',
          color: _kTeal,
        );
      } else {
        HapticFeedback.heavyImpact();
        _showSnack(
          message: 'Save failed. Check history storage.',
          color: _kRed,
        );
      }
    } catch (e, st) {
      debugPrint('SummaryScreen save failed: $e\n$st');

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      _showSnack(
        message: 'Save failed. Please try again.',
        color: _kRed,
      );
    }
  }

  Future<bool> _saveSummaryToHistory(TripSummary summary) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final List<String> existing = prefs.getStringList('trip_history') ??
          prefs.getStringList('saved_trips') ??
          prefs.getStringList('trips') ??
          <String>[];

      final Map<String, dynamic> payload = _summaryToJson(summary);
      final List<String> next = <String>[];
      bool replaced = false;

      for (final String item in existing) {
        try {
          final Object? decoded = jsonDecode(item);

          if (decoded is Map<String, dynamic>) {
            if (decoded['id'] == summary.id) {
              next.add(jsonEncode(payload));
              replaced = true;
            } else {
              next.add(item);
            }
          } else {
            next.add(item);
          }
        } catch (_) {
          next.add(item);
        }
      }

      if (!replaced) {
        next.insert(0, jsonEncode(payload));
      }

      await prefs.setStringList('trip_history', next);

      if (prefs.containsKey('saved_trips')) {
        await prefs.remove('saved_trips');
      }
      if (prefs.containsKey('trips')) {
        await prefs.remove('trips');
      }

      return true;
    } catch (e, st) {
      debugPrint('SummaryScreen history save error: $e\n$st');
      return false;
    }
  }

  Map<String, dynamic> _summaryToJson(TripSummary summary) {
    return <String, dynamic>{
      'id': summary.id,
      'date': summary.date.toIso8601String(),
      'totalSeconds': summary.totalTime.inSeconds,
      'stoppedSeconds': summary.stoppedTime.inSeconds,
      'movingSeconds': _movingTime.inSeconds,
      'maxSpeedMph': _safeDouble(summary.maxSpeedMph),
      'avgSpeedMph': _safeDouble(summary.avgSpeedMph),
      'altitudeGainFt': _safeDouble(summary.altitudeGainFt),
      'maxAltitudeFt': _safeDouble(summary.maxAltitudeFt),
      'minAltitudeFt': _safeDouble(summary.minAltitudeFt),
      'distanceMiles': _safeDouble(summary.distanceMiles),
      'pointCount': summary.points.length,
    };
  }

  Future<void> _copySummary() async {
    HapticFeedback.selectionClick();

    final String summaryText = _buildShareText();

    await Clipboard.setData(ClipboardData(text: summaryText));

    if (!mounted) {
      return;
    }

    _showSnack(
      message: 'Trip summary copied.',
      color: _kGold,
    );
  }

  void _showSnack({
    required String message,
    required Color color,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(seconds: 2),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
  }

  void _openAiCoach() {
    HapticFeedback.lightImpact();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => AiChatSheet(summary: widget.summary),
    );
  }

  void _openMap() {
    HapticFeedback.lightImpact();

    final List<TripPoint> validPoints = widget.summary.points.where(
      (TripPoint point) {
        final double lat = point.position.latitude;
        final double lng = point.position.longitude;

        return lat.isFinite &&
            lng.isFinite &&
            lat.abs() <= 90.0 &&
            lng.abs() <= 180.0;
      },
    ).toList(growable: false);

    if (validPoints.isEmpty) {
      _showSnack(
        message: 'No route points available for this trip.',
        color: _kGold,
      );
      return;
    }

    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => MapScreen(
          points: validPoints,
          isLive: false,
          tripStartTime: widget.summary.date,
        ),
      ),
    );
  }

  String _buildShareText() {
    final String distance = _settings
        .toDisplayDistance(widget.summary.distanceMiles)
        .toStringAsFixed(2);

    final String avgSpeed =
        _settings.toDisplaySpeed(widget.summary.avgSpeedMph).toStringAsFixed(0);

    final String maxSpeed =
        _settings.toDisplaySpeed(widget.summary.maxSpeedMph).toStringAsFixed(0);

    final String altitude = _formatAltitude(widget.summary.altitudeGainFt);

    return '''
TrackPro AI Trip Summary

Distance: $distance ${_settings.distanceUnit}
Total Time: ${widget.summary.formattedTotalTime}
Stopped Time: ${widget.summary.formattedStoppedTime}
Moving Time: ${_formatDuration(_movingTime)}
Average Speed: $avgSpeed ${_settings.speedUnit}
Max Speed: $maxSpeed ${_settings.speedUnit}
Altitude Gain: $altitude
Route Points: ${widget.summary.points.length}
Date: ${widget.summary.date}
''';
  }

  Duration get _movingTime {
    if (!widget.summary.movingTime.isNegative &&
        widget.summary.movingTime > Duration.zero) {
      return widget.summary.movingTime;
    }

    final Duration moving =
        widget.summary.totalTime - widget.summary.stoppedTime;

    return moving.isNegative ? Duration.zero : moving;
  }

  double get _altFactor => _settings.useKmh ? 0.3048 : 1.0;

  String get _altUnit => _settings.useKmh ? 'M' : 'FT';

  @override
  Widget build(BuildContext context) {
    final TripSummary summary = widget.summary;

    final double distance = _safeDouble(
      _settings.toDisplayDistance(summary.distanceMiles),
    );

    final double avgSpeed = _safeDouble(
      _settings.toDisplaySpeed(summary.avgSpeedMph),
    );

    final double maxSpeed = _safeDouble(
      _settings.toDisplaySpeed(summary.maxSpeedMph),
    );

    final double altitudeGain =
        _safeDouble(summary.altitudeGainFt * _altFactor);
    final double maxAltitude = _safeDouble(summary.maxAltitudeFt * _altFactor);
    final double minAltitude = _safeDouble(summary.minAltitudeFt * _altFactor);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        floatingActionButton: _AiFab(onTap: _openAiCoach),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.15,
              colors: <Color>[
                Color(0xFF172A28),
                Color(0xFF090909),
                Color(0xFF000000),
              ],
              stops: <double>[0.0, 0.48, 1.0],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _SummaryAppBar(
                  onBack: () => Navigator.of(context).pop(),
                  onMap: _openMap,
                  onCopy: _copySummary,
                  pointCount: summary.points.length,
                ),
                Expanded(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: <Widget>[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            <Widget>[
                              _HeroDistanceCard(
                                distance: distance,
                                unit: _settings.distanceUnit.toUpperCase(),
                                date: summary.date,
                                duration: summary.formattedTotalTime,
                                pointCount: summary.points.length,
                              ),
                              const SizedBox(height: 14),
                              _QuickActionsRow(
                                onMap: _openMap,
                                onCopy: _copySummary,
                                onToggleCharts: () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _showCharts = !_showCharts;
                                  });
                                },
                                chartsVisible: _showCharts,
                              ),
                              const SizedBox(height: 14),
                              AiAnalysisCard(summary: summary),
                              const SizedBox(height: 14),
                              _SectionCard(
                                title: 'TIME METRICS',
                                icon: CupertinoIcons.timer,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: _StatBox(
                                          label: 'TOTAL',
                                          value: summary.formattedTotalTime,
                                          icon: CupertinoIcons.timer,
                                          color: _kTeal,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _StatBox(
                                          label: 'MOVING',
                                          value: _formatDuration(_movingTime),
                                          icon: CupertinoIcons.play_circle,
                                          color: _kGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _StatBox(
                                    label: 'STOPPED TIME',
                                    value: summary.formattedStoppedTime,
                                    icon: CupertinoIcons.pause_circle,
                                    color: _kGold,
                                    wide: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _SectionCard(
                                title:
                                    'SPEED ANALYTICS (${_settings.speedUnit.toUpperCase()})',
                                icon: CupertinoIcons.speedometer,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: _StatBox(
                                          label: 'MAXIMUM',
                                          value: maxSpeed.toStringAsFixed(0),
                                          icon: CupertinoIcons.bolt_fill,
                                          color: _kGoldSoft,
                                          large: true,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _StatBox(
                                          label: 'AVERAGE',
                                          value: avgSpeed.toStringAsFixed(0),
                                          icon: CupertinoIcons.chart_bar,
                                          color: _kBlue,
                                          large: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_showCharts &&
                                      summary.points.length > 5) ...<Widget>[
                                    const SizedBox(height: 18),
                                    _ChartHeader(
                                      title: 'Speed profile',
                                      color: _kBlue,
                                      unit: _settings.speedUnit,
                                    ),
                                    const SizedBox(height: 8),
                                    _PerformanceChart(
                                      points: summary.points,
                                      getValue: (TripPoint point) {
                                        return _settings.toDisplaySpeed(
                                          point.speedMph,
                                        );
                                      },
                                      color: _kBlue,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              _SectionCard(
                                title: 'ELEVATION PROFILE ($_altUnit)',
                                icon: CupertinoIcons.graph_square,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: _StatBox(
                                          label: 'GAIN',
                                          value:
                                              '+${altitudeGain.toStringAsFixed(0)}',
                                          icon: CupertinoIcons.arrow_up_right,
                                          color: _kTeal,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _StatBox(
                                          label: 'MAX',
                                          value: maxAltitude.toStringAsFixed(0),
                                          icon: CupertinoIcons.chevron_up,
                                          color: _kGold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _StatBox(
                                          label: 'MIN',
                                          value: minAltitude.toStringAsFixed(0),
                                          icon: CupertinoIcons.chevron_down,
                                          color: _kPurple,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_showCharts &&
                                      summary.points.length > 5) ...<Widget>[
                                    const SizedBox(height: 18),
                                    _ChartHeader(
                                      title: 'Elevation profile',
                                      color: _kTeal,
                                      unit: _altUnit,
                                    ),
                                    const SizedBox(height: 8),
                                    _PerformanceChart(
                                      points: summary.points,
                                      getValue: (TripPoint point) {
                                        final double alt =
                                            point.altitudeFt * _altFactor;

                                        return alt.isFinite ? alt : 0.0;
                                      },
                                      color: _kTeal,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              _SectionCard(
                                title: 'ROUTE QUALITY',
                                icon: CupertinoIcons.location_fill,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: _StatBox(
                                          label: 'POINTS',
                                          value: '${summary.points.length}',
                                          icon: CupertinoIcons
                                              .circle_grid_hex_fill,
                                          color: _kBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _StatBox(
                                          label: 'PACE',
                                          value: _paceLabel(avgSpeed),
                                          icon: CupertinoIcons.gauge,
                                          color: _paceColor(avgSpeed),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _RouteInsightStrip(
                                    distance: distance,
                                    avgSpeed: avgSpeed,
                                    pointCount: summary.points.length,
                                    speedUnit: _settings.speedUnit,
                                    distanceUnit: _settings.distanceUnit,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _SaveButton(
                                isSaving: _isSaving,
                                isSaved: _isSaved,
                                onTap: _handleSaveTrip,
                              ),
                              const SizedBox(height: 12),
                              _DismissButton(
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double _safeDouble(double value) {
    if (!value.isFinite) {
      return 0.0;
    }

    return value < 0.0 ? 0.0 : value;
  }

  String _formatAltitude(double altitudeFt) {
    final double value = _safeDouble(altitudeFt * _altFactor);
    return '${value.toStringAsFixed(0)} $_altUnit';
  }

  static String _formatDuration(Duration duration) {
    final Duration safe = duration.isNegative ? Duration.zero : duration;

    final int h = safe.inHours;
    final int m = safe.inMinutes.remainder(60);
    final int s = safe.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }

    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  static String _paceLabel(double avgSpeed) {
    if (avgSpeed <= 0.5) {
      return 'IDLE';
    }
    if (avgSpeed < 15) {
      return 'SLOW';
    }
    if (avgSpeed < 45) {
      return 'CITY';
    }
    if (avgSpeed < 85) {
      return 'CRUISE';
    }

    return 'FAST';
  }

  static Color _paceColor(double avgSpeed) {
    if (avgSpeed <= 0.5) {
      return Colors.white38;
    }
    if (avgSpeed < 15) {
      return _kTeal;
    }
    if (avgSpeed < 45) {
      return _kGreen;
    }
    if (avgSpeed < 85) {
      return _kGold;
    }

    return _kRed;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryAppBar extends StatelessWidget {
  const _SummaryAppBar({
    required this.onBack,
    required this.onMap,
    required this.onCopy,
    required this.pointCount,
  });

  final VoidCallback onBack;
  final VoidCallback onMap;
  final VoidCallback onCopy;
  final int pointCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: <Widget>[
                _RoundIconButton(
                  icon: CupertinoIcons.chevron_back,
                  onTap: onBack,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'SESSION OVERVIEW',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$pointCount route points · performance analytics',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _HeaderMiniButton(
                  icon: CupertinoIcons.doc_on_doc,
                  onTap: onCopy,
                ),
                const SizedBox(width: 8),
                _HeaderMiniButton(
                  icon: CupertinoIcons.map_fill,
                  onTap: onMap,
                  color: _kTeal,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderMiniButton extends StatelessWidget {
  const _HeaderMiniButton({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Icon(
          icon,
          color: color,
          size: 17,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO CARD
// ─────────────────────────────────────────────────────────────────────────────

class _HeroDistanceCard extends StatelessWidget {
  const _HeroDistanceCard({
    required this.distance,
    required this.unit,
    required this.date,
    required this.duration,
    required this.pointCount,
  });

  final double distance;
  final String unit;
  final DateTime date;
  final String duration;
  final int pointCount;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(22),
      radius: 30,
      borderColor: _kTeal.withValues(alpha: 0.13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _IconBadge(
                icon: CupertinoIcons.location_fill,
                color: _kTeal,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'TOTAL DISTANCE',
                  style: TextStyle(
                    color: _kTeal,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              _SmallPill(
                text: '${date.month}/${date.day}/${date.year}',
                color: _kGold,
              ),
            ],
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  distance.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 58,
                    fontWeight: FontWeight.w300,
                    height: 0.95,
                    letterSpacing: -2,
                    fontFeatures: <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  unit,
                  style: const TextStyle(
                    color: _kTeal,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniMetric(
                  label: 'DURATION',
                  value: duration,
                  color: _kGold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniMetric(
                  label: 'ROUTE POINTS',
                  value: '$pointCount',
                  color: _kBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color.withValues(alpha: 0.75),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK ACTIONS
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onMap,
    required this.onCopy,
    required this.onToggleCharts,
    required this.chartsVisible,
  });

  final VoidCallback onMap;
  final VoidCallback onCopy;
  final VoidCallback onToggleCharts;
  final bool chartsVisible;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ActionChipButton(
            icon: CupertinoIcons.map_fill,
            label: 'MAP',
            color: _kTeal,
            onTap: onMap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionChipButton(
            icon: CupertinoIcons.doc_on_doc,
            label: 'COPY',
            color: _kGold,
            onTap: onCopy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionChipButton(
            icon: chartsVisible
                ? CupertinoIcons.chart_bar_fill
                : CupertinoIcons.chart_bar,
            label: chartsVisible ? 'CHARTS ON' : 'CHARTS OFF',
            color: _kBlue,
            onTap: onToggleCharts,
          ),
        ),
      ],
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: _kTeal, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTeal,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS
// ─────────────────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.large = false,
    this.wide = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool large;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: EdgeInsets.all(large ? 17 : 15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: large ? 26 : 18,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -0.5,
                fontFeatures: const <ui.FontFeature>[
                  ui.FontFeature.tabularFigures(),
                ],
                shadows: <Shadow>[
                  Shadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART
// ─────────────────────────────────────────────────────────────────────────────

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.title,
    required this.color,
    required this.unit,
  });

  final String title;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: color.withValues(alpha: 0.78),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        _SmallPill(
          text: unit.toUpperCase(),
          color: color,
        ),
      ],
    );
  }
}

class _PerformanceChart extends StatelessWidget {
  const _PerformanceChart({
    required this.points,
    required this.getValue,
    required this.color,
  });

  final List<TripPoint> points;
  final double Function(TripPoint) getValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final List<FlSpot> spots = _buildSpots();

    if (spots.length < 2) {
      return _ChartEmptyState(color: color);
    }

    final double maxY = spots
        .map((FlSpot spot) => spot.y)
        .fold<double>(0.0, math.max)
        .clamp(1.0, double.infinity)
        .toDouble();

    return RepaintBoundary(
      child: SizedBox(
        height: 112,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY * 1.12,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 3,
              getDrawingHorizontalLine: (_) {
                return FlLine(
                  color: Colors.white.withValues(alpha: 0.05),
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
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
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
                    colors: <Color>[
                      color.withValues(alpha: 0.22),
                      color.withValues(alpha: 0.0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<FlSpot> _buildSpots() {
    if (points.isEmpty) {
      return const <FlSpot>[];
    }

    final int sampleRate = (points.length / _kMaxChartSamples)
        .ceil()
        .clamp(1, points.length)
        .toInt();

    final List<FlSpot> spots = <FlSpot>[];

    for (int i = 0; i < points.length; i += sampleRate) {
      final double value = getValue(points[i]);
      if (!value.isFinite) {
        continue;
      }

      spots.add(
        FlSpot(
          spots.length.toDouble(),
          value < 0 ? 0.0 : value,
        ),
      );
    }

    return spots;
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
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Text(
        'Not enough data for chart',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROUTE INSIGHT
// ─────────────────────────────────────────────────────────────────────────────

class _RouteInsightStrip extends StatelessWidget {
  const _RouteInsightStrip({
    required this.distance,
    required this.avgSpeed,
    required this.pointCount,
    required this.speedUnit,
    required this.distanceUnit,
  });

  final double distance;
  final double avgSpeed;
  final int pointCount;
  final String speedUnit;
  final String distanceUnit;

  @override
  Widget build(BuildContext context) {
    final String message = pointCount < 3
        ? 'Route data is limited. Longer trips will produce better insights.'
        : 'Route captured with $pointCount points over ${distance.toStringAsFixed(1)} $distanceUnit at ${avgSpeed.toStringAsFixed(0)} $speedUnit average.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kTeal.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _kTeal.withValues(alpha: 0.13)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.sparkles,
            color: _kTeal,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAVE / DISMISS / AI
// ─────────────────────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.isSaving,
    required this.isSaved,
    required this.onTap,
  });

  final bool isSaving;
  final bool isSaved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = isSaved ? _kGreen : _kTeal;

    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(22),
        onPressed: isSaving || isSaved ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            gradient: isSaved
                ? null
                : const LinearGradient(
                    colors: <Color>[
                      _kTeal,
                      Color(0xFF3DBDB5),
                    ],
                  ),
            color: isSaved ? _kGreen.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: color.withValues(alpha: isSaved ? 0.32 : 0.0),
            ),
            boxShadow: isSaved
                ? null
                : <BoxShadow>[
                    BoxShadow(
                      color: _kTeal.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Center(
            child: isSaving
                ? const CupertinoActivityIndicator(color: Colors.black)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        isSaved
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.cloud_upload_fill,
                        color: isSaved ? _kGreen : Colors.black,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isSaved ? 'TRIP SAVED' : 'SAVE TO HISTORY',
                        style: TextStyle(
                          color: isSaved ? _kGreen : Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(22),
        onPressed: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Text(
            'DISMISS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _AiFab extends StatelessWidget {
  const _AiFab({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      elevation: 12,
      onPressed: onTap,
      backgroundColor: _kPurple,
      icon: const Icon(
        Icons.auto_awesome,
        color: Colors.white,
        size: 18,
      ),
      label: const Text(
        'ASK AI',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.borderColor = _kBorder,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.075),
            Colors.white.withValues(alpha: 0.035),
            Colors.white.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        color: _kCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 19,
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Icon(
        icon,
        color: color,
        size: 16,
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
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
