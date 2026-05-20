import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/trip_data.dart';
import '../../services/settings_service.dart';
import '../../services/trip_export_service.dart';
import '../../services/offline_sync_queue.dart';
import '../../widgets/ai_analysis_card.dart';
import '../../widgets/ai_chat_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_speed_chart.dart';
import '../../widgets/common/app_route_preview.dart';
import '../../widgets/common/app_section_card.dart';
import '../../widgets/common/app_status_pill.dart';
import '../../widgets/common/app_action_button.dart';
import '../../widgets/common/app_metric_card.dart';
import '../../widgets/common/app_glass_card.dart';
import '../../widgets/common/app_page_shell.dart';
import '../map/map_screen.dart';

part 'summary_models.dart';
part 'summary_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SUMMARY SCREEN — Fixed + Optimized Premium UI
// Split into part files under lib/screens/summary/ for cleaner maintenance.
// ═══════════════════════════════════════════════════════════════════════════════
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

  late final List<TripPoint> _validPoints;
  late final _RouteQualitySnapshot _routeQuality;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _validPoints = _validatedPoints(widget.summary.points);
    _routeQuality = _RouteQualitySnapshot.fromPoints(_validPoints);
    OfflineSyncQueue.instance.loadStatus();
    _checkSavedState();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _checkSavedState() async {
    try {
      final Map<String, dynamic>? row = await Supabase.instance.client
          .from('saved_trips')
          .select('id')
          .eq('id', widget.summary.id)
          .maybeSingle();

      if (!mounted) return;

      if (row != null) {
        setState(() => _isSaved = true);
        return;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'SummaryScreen Supabase saved-state check failed: $error\n$stackTrace',
      );
    }

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> existing = prefs.getStringList('trip_history') ??
          prefs.getStringList('saved_trips') ??
          prefs.getStringList('trips') ??
          <String>[];

      final bool alreadySaved = existing.length > _kJsonComputeThreshold
          ? await compute<Map<String, Object?>, bool>(
              _tripHistoryContainsIdWorker,
              <String, Object?>{
                'items': existing,
                'id': widget.summary.id,
              },
            )
          : _tripHistoryContainsIdSync(existing, widget.summary.id);

      if (!mounted) return;
      setState(() => _isSaved = alreadySaved);
    } catch (error, stackTrace) {
      debugPrint(
          'SummaryScreen local saved-state check failed: $error\n$stackTrace');
    }
  }

  Future<void> _handleSaveTrip() async {
    if (_isSaved || _isSaving) return;

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final _SaveTripResult result =
          await _saveSummaryToHistory(widget.summary);

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _isSaved = result.savedLocally;
      });

      if (result.syncedToCloud) {
        HapticFeedback.lightImpact();
        _showSnack(
          message: 'Trip saved to cloud history.',
          color: _kTeal,
          darkText: true,
        );
      } else if (result.savedLocally) {
        HapticFeedback.lightImpact();
        _showSnack(
          message: 'Saved offline. Will sync when internet returns.',
          color: _kGold,
          darkText: true,
        );
      } else {
        HapticFeedback.heavyImpact();
        _showSnack(
          message: 'Save failed. Please try again.',
          color: _kRed,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('SummaryScreen save failed: $error\n$stackTrace');

      if (!mounted) return;

      setState(() => _isSaving = false);

      _showSnack(
        message: 'Save failed. Please try again.',
        color: _kRed,
      );
    }
  }

  Future<_SaveTripResult> _saveSummaryToHistory(TripSummary summary) async {
    final Map<String, dynamic> payload = _summaryToJson(summary);

    try {
      await Supabase.instance.client
          .from('saved_trips')
          .upsert(payload, onConflict: 'id');

      await _saveLocalMirror(payload);
      await OfflineSyncQueue.instance.remove(summary.id);

      return const _SaveTripResult(
        savedLocally: true,
        syncedToCloud: true,
      );
    } catch (error, stackTrace) {
      debugPrint('SummaryScreen Supabase save error: $error\n$stackTrace');

      bool localSaved = false;

      try {
        await _saveLocalMirror(payload);
        await OfflineSyncQueue.instance.enqueueTrip(payload, error: error);
        localSaved = true;
      } catch (localError, localStackTrace) {
        debugPrint(
          'SummaryScreen offline queue save failed: '
          '$localError\n$localStackTrace',
        );
      }

      return _SaveTripResult(
        savedLocally: localSaved,
        syncedToCloud: false,
      );
    }
  }

  Future<void> _syncOfflineQueue() async {
    HapticFeedback.selectionClick();

    _showSnack(
      message: 'Syncing offline trips...',
      color: _kBlue,
    );

    try {
      final OfflineSyncResult result =
          await OfflineSyncQueue.instance.syncNow();

      if (!mounted) return;

      _showSnack(
        message: result.message,
        color: result.hasPending ? _kGold : _kGreen,
        darkText: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Offline sync failed: $error\n$stackTrace');
      if (!mounted) return;
      _showSnack(
        message: 'Offline sync failed. Check your connection.',
        color: _kRed,
      );
    }
  }

  Future<void> _saveLocalMirror(Map<String, dynamic> payload) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<String> existing = prefs.getStringList('trip_history') ??
        prefs.getStringList('saved_trips') ??
        prefs.getStringList('trips') ??
        <String>[];

    final int routePointCount = payload['route_points'] is List
        ? (payload['route_points'] as List).length
        : 0;

    final bool useBackgroundIsolate =
        existing.length > _kJsonComputeThreshold || routePointCount > 250;

    final List<String> next = useBackgroundIsolate
        ? await compute<Map<String, Object?>, List<String>>(
            _buildLocalMirrorHistoryWorker,
            <String, Object?>{
              'existing': existing,
              'payload': payload,
              'limit': _kMaxLocalHistoryItems,
            },
          )
        : _buildLocalMirrorHistorySync(
            existing: existing,
            payload: payload,
            limit: _kMaxLocalHistoryItems,
          );

    await prefs.setStringList('trip_history', next);

    if (prefs.containsKey('saved_trips')) await prefs.remove('saved_trips');
    if (prefs.containsKey('trips')) await prefs.remove('trips');
  }

  Map<String, dynamic> _summaryToJson(TripSummary summary) {
    // Must match public.saved_trips schema exactly.
    // Extra keys will make Supabase/PostgREST reject the upsert.
    return <String, dynamic>{
      'id': summary.id,
      'date': summary.date.millisecondsSinceEpoch,
      'distanceMiles': _safeDouble(summary.distanceMiles),
      'maxSpeedMph': _safeDouble(summary.maxSpeedMph),
      'avgSpeedMph': _safeDouble(summary.avgSpeedMph),
      'totalTimeSeconds': math.max(0, summary.totalTime.inSeconds),
      'altitudeGainFt': _safeDouble(summary.altitudeGainFt),
      'route_points': _validPoints.map(_pointToJson).toList(growable: false),
    };
  }

  Map<String, dynamic> _pointToJson(TripPoint point) {
    // route_points is JSONB, so extra fields are safe and make replay/export
    // better without changing the saved_trips table columns.
    return <String, dynamic>{
      'lat': _safeCoordinate(point.position.latitude),
      'lng': _safeCoordinate(point.position.longitude),
      'spd': _safeDouble(point.speedMph),
      'altFt': _safeDouble(point.altitudeFt),
      'time': point.timestamp.millisecondsSinceEpoch,
      'acc': _safeDouble(point.accuracyMeters),
    };
  }

  Future<void> _copySummary() async {
    HapticFeedback.selectionClick();

    await Clipboard.setData(ClipboardData(text: _buildShareText()));

    if (!mounted) return;

    _showSnack(
      message: 'Trip summary copied.',
      color: _kGold,
      darkText: true,
    );
  }

  Future<void> _exportTripFiles() async {
    HapticFeedback.selectionClick();

    if (_validPoints.length < 2) {
      _showSnack(
        message: 'Not enough route points to export files.',
        color: _kGold,
        darkText: true,
      );
      return;
    }

    _showSnack(
      message: 'Preparing GPX, CSV and KML files...',
      color: _kBlue,
      darkText: false,
    );

    final TripExportResult result = await TripExportService.shareTripFiles(
      tripId: widget.summary.id,
      date: widget.summary.date,
      points: _validPoints,
    );

    if (!mounted) return;

    _showSnack(
      message: result.message,
      color: result.success ? _kGreen : _kGold,
      darkText: result.success,
    );
  }

  void _showSnack({
    required String message,
    required Color color,
    bool darkText = false,
  }) {
    if (!mounted) return;

    final EdgeInsets safeMargin = EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: math.max(16.0, MediaQuery.paddingOf(context).bottom + 12),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(seconds: 2),
          margin: safeMargin,
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: darkText ? Colors.black : Colors.white,
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

    if (_validPoints.isEmpty) {
      _showSnack(
        message: 'No route points available for this trip.',
        color: _kGold,
        darkText: true,
      );
      return;
    }

    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => MapScreen(
          points: _validPoints,
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
Route Points: ${_validPoints.length}
Route Quality: ${_routeQuality.score}% - ${_routeQuality.label}
Date: ${widget.summary.date}
''';
  }

  Duration get _movingTime {
    final Duration summaryMoving = widget.summary.movingTime;

    if (!summaryMoving.isNegative && summaryMoving > Duration.zero) {
      return summaryMoving;
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

    final List<LatLng> routePreviewPoints = _validPoints
        .map((TripPoint point) => point.position)
        .toList(growable: false);

    final List<double> speedValues = _validPoints
        .map((TripPoint point) => _settings.toDisplaySpeed(point.speedMph))
        .where((double value) => value.isFinite && value >= 0.0)
        .toList(growable: false);

    final List<double> altitudeValues = _validPoints
        .map((TripPoint point) => point.altitudeFt * _altFactor)
        .where((double value) => value.isFinite)
        .toList(growable: false);

    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    const double fabHeight = 56.0;
    const double fabBottomGap = 18.0;
    const double afterFabContentGap = 24.0;
    final double listBottomPadding =
        safeBottom + fabHeight + fabBottomGap + afterFabContentGap;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AppPageShell(
        title: 'Trip Summary',
        subtitle:
            '${summary.formattedTotalTime} · ${_validPoints.length} points',
        showBackButton: true,
        onBack: () => Navigator.of(context).pop(),
        trailing: AppStatusPill(
          label: '${_routeQuality.score}% QUALITY',
          color: _routeQuality.color,
          icon: CupertinoIcons.checkmark_shield_fill,
        ),
        padding: EdgeInsets.zero,
        child: Stack(
          children: <Widget>[
            ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 4, 16, listBottomPadding),
              children: <Widget>[
                _SummaryHeroRedesign(
                  distance: distance,
                  distanceUnit: _settings.distanceUnit.toUpperCase(),
                  duration: summary.formattedTotalTime,
                  date: summary.date,
                  quality: _routeQuality,
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppActionButton(
                        label: _isSaved ? 'Saved' : 'Save',
                        icon: _isSaved
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.square_arrow_down_fill,
                        primary: !_isSaved,
                        enabled: !_isSaving,
                        onTap: _handleSaveTrip,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppActionButton(
                        label: 'Map Replay',
                        icon: CupertinoIcons.play_rectangle_fill,
                        onTap: _openMap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppActionButton(
                        label: 'AI Coach',
                        icon: CupertinoIcons.sparkles,
                        onTap: _openAiCoach,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppActionButton(
                        label: 'Export',
                        icon: CupertinoIcons.share,
                        onTap: _exportTripFiles,
                      ),
                    ),
                  ],
                ),
                AppSectionCard(
                  title: 'Core metrics',
                  subtitle: 'Distance, speed and time overview',
                  icon: CupertinoIcons.chart_bar_fill,
                  spacing: 10,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppMetricCard(
                            label: 'Average',
                            value: avgSpeed.toStringAsFixed(0),
                            unit: _settings.speedUnit,
                            icon: CupertinoIcons.speedometer,
                            color: _kBlue,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppMetricCard(
                            label: 'Maximum',
                            value: maxSpeed.toStringAsFixed(0),
                            unit: _settings.speedUnit,
                            icon: CupertinoIcons.bolt_fill,
                            color: _kGoldSoft,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppMetricCard(
                            label: 'Moving',
                            value: _formatDuration(_movingTime),
                            icon: CupertinoIcons.play_circle_fill,
                            color: _kGreen,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppMetricCard(
                            label: 'Stopped',
                            value: summary.formattedStoppedTime,
                            icon: CupertinoIcons.pause_circle_fill,
                            color: _kGold,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                AppSectionCard(
                  title: 'Route preview',
                  subtitle: routePreviewPoints.length >= 2
                      ? 'Recorded path overview'
                      : 'Route points unavailable',
                  icon: CupertinoIcons.map_fill,
                  children: <Widget>[
                    AppRoutePreview(
                      points: routePreviewPoints,
                      height: 130,
                      color: _kBlue,
                    ),
                    const SizedBox(height: 12),
                    _RouteInsightStrip(
                      distance: distance,
                      avgSpeed: avgSpeed,
                      pointCount: _validPoints.length,
                      speedUnit: _settings.speedUnit,
                      distanceUnit: _settings.distanceUnit,
                      quality: _routeQuality,
                    ),
                  ],
                ),
                AppSectionCard(
                  title: 'Speed profile',
                  subtitle: _showCharts
                      ? 'Performance across the trip'
                      : 'Charts are hidden',
                  icon: CupertinoIcons.waveform_path_ecg,
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showCharts = !_showCharts);
                    },
                    child: AppStatusPill(
                      label: _showCharts ? 'HIDE' : 'SHOW',
                      color: _showCharts ? _kBlue : Colors.white54,
                    ),
                  ),
                  children: <Widget>[
                    if (_showCharts && speedValues.length > 1)
                      AppSpeedChart(
                        values: speedValues,
                        height: 128,
                        color: _kBlue,
                      )
                    else
                      const _SummaryEmptyNote(
                        text: 'Not enough speed samples for charting.',
                      ),
                  ],
                ),
                AppSectionCard(
                  title: 'Elevation',
                  subtitle: 'Gain, highest and lowest altitude',
                  icon: CupertinoIcons.graph_square_fill,
                  spacing: 10,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppMetricCard(
                            label: 'Gain',
                            value: '+${altitudeGain.toStringAsFixed(0)}',
                            unit: _altUnit,
                            icon: CupertinoIcons.arrow_up_right,
                            color: _kTeal,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppMetricCard(
                            label: 'Max',
                            value: maxAltitude.toStringAsFixed(0),
                            unit: _altUnit,
                            icon: CupertinoIcons.chevron_up,
                            color: _kGold,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppMetricCard(
                            label: 'Min',
                            value: minAltitude.toStringAsFixed(0),
                            unit: _altUnit,
                            icon: CupertinoIcons.chevron_down,
                            color: _kPurple,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    if (_showCharts && altitudeValues.length > 1)
                      AppSpeedChart(
                        values: altitudeValues,
                        height: 116,
                        color: _kTeal,
                      ),
                  ],
                ),
                AppSectionCard(
                  title: 'AI Insight',
                  subtitle: 'Trip analysis and recommendations',
                  icon: CupertinoIcons.sparkles,
                  children: <Widget>[
                    AiAnalysisCard(summary: summary),
                  ],
                ),
                AppSectionCard(
                  title: 'Sync & export',
                  subtitle: 'Offline queue and shareable files',
                  icon: CupertinoIcons.cloud_upload_fill,
                  children: <Widget>[
                    _OfflineSyncCard(
                      pendingCount: OfflineSyncQueue.instance.pendingCount,
                      onSync: _syncOfflineQueue,
                    ),
                    const SizedBox(height: 10),
                    AppActionButton(
                      label: 'Copy summary text',
                      icon: CupertinoIcons.doc_on_doc_fill,
                      onTap: _copySummary,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                AppActionButton(
                  label: 'Done',
                  icon: CupertinoIcons.checkmark_circle_fill,
                  primary: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Positioned(
              right: 18,
              bottom: math.max(18.0, safeBottom + 12.0),
              child: _AiFab(onTap: _openAiCoach),
            ),
          ],
        ),
      ),
    );
  }

  static List<TripPoint> _validatedPoints(List<TripPoint> points) {
    if (points.isEmpty) return const <TripPoint>[];

    final List<TripPoint> valid = <TripPoint>[];
    double? lastLat;
    double? lastLng;

    for (final TripPoint point in points) {
      final double lat = point.position.latitude;
      final double lng = point.position.longitude;

      final bool ok = lat.isFinite &&
          lng.isFinite &&
          lat.abs() <= 90.0 &&
          lng.abs() <= 180.0;

      if (!ok) continue;
      if (lastLat != null &&
          lastLng != null &&
          _sameCoordinate(lastLat, lat) &&
          _sameCoordinate(lastLng, lng) &&
          valid.isNotEmpty) {
        continue;
      }

      valid.add(point);
      lastLat = lat;
      lastLng = lng;
    }

    return List<TripPoint>.unmodifiable(valid);
  }

  static double _safeDouble(double value) {
    if (!value.isFinite) return 0.0;
    return value < 0.0 ? 0.0 : value;
  }

  static double _safeCoordinate(double value) {
    if (!value.isFinite) return 0.0;
    return value;
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
}
