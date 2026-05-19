import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trip_data.dart';
import '../services/settings_service.dart';
import '../services/trip_export_service.dart';
import '../services/offline_sync_queue.dart';
import '../widgets/ai_analysis_card.dart';
import '../widgets/ai_chat_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/common/app_speed_chart.dart';
import '../widgets/common/app_route_preview.dart';
import '../widgets/common/app_section_card.dart';
import '../widgets/common/app_status_pill.dart';
import '../widgets/common/app_action_button.dart';
import '../widgets/common/app_metric_card.dart';
import '../widgets/common/app_glass_card.dart';
import '../widgets/common/app_page_shell.dart';
import 'map/map_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SUMMARY SCREEN — Fixed + Optimized Premium UI
// ═══════════════════════════════════════════════════════════════════════════════

const Color _kCard = Color(0xFF111111);
const Color _kBorder = Color(0x14FFFFFF);
const Color _kTeal = Color(0xFF4ECDC4);
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD86B);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kPurple = Color(0xFFA855F7);
const Color _kRed = Color(0xFFE74C3C);
const Color _kGreen = Color(0xFF27AE60);

const int _kMaxLocalHistoryItems = 100;
const int _kJsonComputeThreshold = 30;
const double _kCoordinateTolerance = 0.00001;

bool _sameCoordinate(double a, double b) {
  return (a - b).abs() < _kCoordinateTolerance;
}

bool _tripHistoryContainsIdSync(List<String> items, String id) {
  if (id.isEmpty) return false;

  for (final String item in items) {
    try {
      final Object? decoded = jsonDecode(item);
      if (decoded is Map && decoded['id']?.toString() == id) {
        return true;
      }
    } catch (_) {
      // Ignore legacy/corrupted entries.
    }
  }

  return false;
}

bool _tripHistoryContainsIdWorker(Map<String, Object?> args) {
  final Object? rawItems = args['items'];
  final Object? rawId = args['id'];

  if (rawItems is! List || rawId is! String) return false;

  return _tripHistoryContainsIdSync(rawItems.cast<String>(), rawId);
}

List<String> _buildLocalMirrorHistorySync({
  required List<String> existing,
  required Map<String, dynamic> payload,
  required int limit,
}) {
  final String id = payload['id']?.toString() ?? '';
  final String encodedPayload = jsonEncode(payload);
  final List<String> next = <String>[encodedPayload];

  for (final String item in existing) {
    if (next.length >= limit) break;

    try {
      final Object? decoded = jsonDecode(item);
      if (decoded is Map && decoded['id']?.toString() == id) {
        continue;
      }
    } catch (_) {
      // Keep legacy/corrupted entries at the end so the app never destroys
      // user history during a cache update.
    }

    next.add(item);
  }

  return next;
}

List<String> _buildLocalMirrorHistoryWorker(Map<String, Object?> args) {
  final Object? rawExisting = args['existing'];
  final Object? rawPayload = args['payload'];
  final Object? rawLimit = args['limit'];

  if (rawExisting is! List || rawPayload is! Map || rawLimit is! int) {
    return const <String>[];
  }

  return _buildLocalMirrorHistorySync(
    existing: rawExisting.cast<String>(),
    payload: Map<String, dynamic>.from(rawPayload),
    limit: rawLimit,
  );
}

class _RouteQualitySnapshot {
  const _RouteQualitySnapshot({
    required this.score,
    required this.label,
    required this.accuracyLabel,
    required this.color,
  });

  final int score;
  final String label;
  final String accuracyLabel;
  final Color color;

  static _RouteQualitySnapshot fromPoints(List<TripPoint> points) {
    if (points.length < 3) {
      return const _RouteQualitySnapshot(
        score: 45,
        label: 'Limited',
        accuracyLabel: '--',
        color: _kGold,
      );
    }

    double accuracySum = 0.0;
    int accuracyCount = 0;
    int weakAccuracy = 0;
    int duplicateLike = 0;
    double? lastLat;
    double? lastLng;

    for (final TripPoint point in points) {
      final double accuracy = point.accuracyMeters;
      if (accuracy.isFinite && accuracy > 0.0) {
        accuracySum += accuracy;
        accuracyCount++;
        if (accuracy > 35.0) weakAccuracy++;
      }

      final double lat = point.position.latitude;
      final double lng = point.position.longitude;

      if (lastLat != null &&
          lastLng != null &&
          _sameCoordinate(lastLat, lat) &&
          _sameCoordinate(lastLng, lng)) {
        duplicateLike++;
      }

      lastLat = lat;
      lastLng = lng;
    }

    final double avgAccuracy =
        accuracyCount == 0 ? 25.0 : accuracySum / accuracyCount;

    int score = 100;
    if (points.length < 10) score -= 18;
    if (points.length < 5) score -= 20;
    score -= (weakAccuracy * 4).clamp(0, 28).toInt();
    score -= (duplicateLike * 3).clamp(0, 18).toInt();

    if (avgAccuracy > 10) score -= 6;
    if (avgAccuracy > 20) score -= 10;
    if (avgAccuracy > 35) score -= 14;

    score = score.clamp(0, 100).toInt();

    final String label;
    final Color color;
    if (score >= 88) {
      label = 'Excellent';
      color = _kGreen;
    } else if (score >= 72) {
      label = 'Good';
      color = _kTeal;
    } else if (score >= 50) {
      label = 'Fair';
      color = _kGold;
    } else {
      label = 'Weak';
      color = _kRed;
    }

    final String accuracyLabel =
        accuracyCount == 0 ? '--' : '±${avgAccuracy.clamp(0.0, 99.0).round()}m';

    return _RouteQualitySnapshot(
      score: score,
      label: label,
      accuracyLabel: accuracyLabel,
      color: color,
    );
  }
}

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
      final OfflineSyncResult result = await OfflineSyncQueue.instance.syncNow();

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

// Reusable widgets

class _SummaryHeroRedesign extends StatelessWidget {
  static String _heroDateLabel(DateTime date) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final int monthIndex = date.month.clamp(1, 12).toInt() - 1;
    final String month = months[monthIndex];
    final String hour = date.hour.toString().padLeft(2, '0');
    final String minute = date.minute.toString().padLeft(2, '0');

    return '$month ${date.day}, ${date.year} · $hour:$minute';
  }

  const _SummaryHeroRedesign({
    required this.distance,
    required this.distanceUnit,
    required this.duration,
    required this.date,
    required this.quality,
  });

  final double distance;
  final String distanceUnit;
  final String duration;
  final DateTime date;
  final _RouteQualitySnapshot quality;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.blueButtonGradient,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.32),
                      blurRadius: 22,
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.location_north_line_fill,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Trip completed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _heroDateLabel(date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              AppStatusPill(
                label: '${quality.score}%',
                color: quality.color,
                icon: CupertinoIcons.checkmark_shield_fill,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Flexible(
                child: Text(
                  distance.toStringAsFixed(distance >= 100 ? 0 : 2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    height: 0.92,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -3.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  distanceUnit,
                  style: const TextStyle(
                    color: _kGoldSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              AppStatusPill(
                label: duration,
                color: _kTeal,
                icon: CupertinoIcons.timer,
              ),
              AppStatusPill(
                label: quality.accuracyLabel,
                color: quality.color,
                icon: CupertinoIcons.scope,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryEmptyNote extends StatelessWidget {
  const _SummaryEmptyNote({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      shadow: false,
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.info_circle_fill,
            color: Colors.white38,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveTripResult {
  const _SaveTripResult({
    required this.savedLocally,
    required this.syncedToCloud,
  });

  final bool savedLocally;
  final bool syncedToCloud;
}

class _OfflineSyncCard extends StatelessWidget {
  const _OfflineSyncCard({
    required this.pendingCount,
    required this.onSync,
  });

  final ValueNotifier<int> pendingCount;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: pendingCount,
      builder: (_, int count, __) {
        if (count <= 0) return const SizedBox.shrink();

        return _GlassCard(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _kGold.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  color: _kGold,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const _SafeText(
                      'OFFLINE SYNC QUEUE',
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _SafeText(
                      '$count trip${count == 1 ? '' : 's'} waiting for cloud sync',
                      maxLines: 2,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _MiniSyncButton(onTap: onSync),
            ],
          ),
        );
      },
    );
  }
}

class _MiniSyncButton extends StatelessWidget {
  const _MiniSyncButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: _kGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _kGold.withValues(alpha: 0.18),
          ),
        ),
        child: const _SafeText(
          'SYNC',
          maxLines: 1,
          style: TextStyle(
            color: _kGold,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}

class _RouteInsightStrip extends StatelessWidget {
  const _RouteInsightStrip({
    required this.distance,
    required this.avgSpeed,
    required this.pointCount,
    required this.speedUnit,
    required this.distanceUnit,
    required this.quality,
  });

  final double distance;
  final double avgSpeed;
  final int pointCount;
  final String speedUnit;
  final String distanceUnit;
  final _RouteQualitySnapshot quality;

  @override
  Widget build(BuildContext context) {
    final String message = pointCount < 3
        ? 'Route data is limited. Longer trips will produce better insights.'
        : '${quality.label} route quality · $pointCount points over '
            '${distance.toStringAsFixed(1)} $distanceUnit at '
            '${avgSpeed.toStringAsFixed(0)} $speedUnit average.';

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
          const Icon(CupertinoIcons.sparkles, color: _kTeal, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: _SafeText(
              message,
              maxLines: 3,
              softWrap: true,
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
      label: const _SafeText(
        'ASK AI',
        maxLines: 1,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

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

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign,
    this.softWrap = false,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        softWrap: softWrap,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}
