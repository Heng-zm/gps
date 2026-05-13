// ignore_for_file: unused_element, prefer_const_constructors

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip_data.dart';
import '../models/weather_data.dart';
import '../services/services.dart';
import '../utils/smooth_polyline.dart';
import '../widgets/ai_chat_sheet.dart';
import '../widgets/speedometer_widget.dart';
import '../widgets/weather_widget.dart';
import 'map_screen.dart';
import 'summary_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TRACKING SCREEN — Premium Dark Amber UI
// UI/UX enhanced + performance optimized + Flutter Web text hit-test safe
// ═══════════════════════════════════════════════════════════════════════════════

// ── Colors ───────────────────────────────────────────────────────────────────
const Color _kAmber = Color(0xFFFFB300);
const Color _kAmberSoft = Color(0xFFFFD54F);
const Color _kAmberDeep = Color(0xFF7A4D00);
const Color _kRed = Color(0xFFFF453A);
const Color _kRedGlow = Color(0x33FF453A);
const Color _kGreen = Color(0xFF34C759);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kBg = Color(0xFF000000);
const Color _kSurface = Color(0xFF0D0D0F);
const Color _kBorder = Color(0xFF2A2A2E);
const Color _kTextPrimary = Color(0xFFFFFFFF);
const Color _kTextMuted = Color(0x66FFFFFF);

// ── Timing ───────────────────────────────────────────────────────────────────
const Duration _kTick = Duration(seconds: 1);
const Duration _kSignalDebounce = Duration(seconds: 2);
const Duration _kBatteryPoll = Duration(seconds: 60);
const Duration _kWeatherGap = Duration(minutes: 10);
const Duration _kMapThrottle = Duration(milliseconds: 420);
const Duration _kAnimFast = Duration(milliseconds: 150);
const Duration _kAnimMed = Duration(milliseconds: 300);

// ── Map / GPS ────────────────────────────────────────────────────────────────
const LatLng _kDefaultCenter = LatLng(11.5564, 104.9282);
const double _kDefaultZoom = 16.0;
const double _kMinHeadingMph = 2.0;
const double _kMapMoveDist = 3.0;
const double _kAutoPauseEnterMph = 1.2;
const double _kAutoPauseResumeMph = 2.8;
const int _kAutoPauseEnterSeconds = 12;
const int _kAutoPauseResumeSeconds = 3;

enum _MapFollowMode {
  followMe,
  headingUp,
  northUp,
  freeView,
}

extension _MapFollowModeLabel on _MapFollowMode {
  String get label {
    switch (this) {
      case _MapFollowMode.followMe:
        return 'FOLLOW';
      case _MapFollowMode.headingUp:
        return 'HEADING';
      case _MapFollowMode.northUp:
        return 'NORTH';
      case _MapFollowMode.freeView:
        return 'FREE';
    }
  }

  String get subtitle {
    switch (this) {
      case _MapFollowMode.followMe:
        return 'Centered on you';
      case _MapFollowMode.headingUp:
        return 'Rotates with route';
      case _MapFollowMode.northUp:
        return 'North locked';
      case _MapFollowMode.freeView:
        return 'Camera paused';
    }
  }

  IconData get icon {
    switch (this) {
      case _MapFollowMode.followMe:
        return CupertinoIcons.location_fill;
      case _MapFollowMode.headingUp:
        return Icons.navigation_rounded;
      case _MapFollowMode.northUp:
        return CupertinoIcons.compass_fill;
      case _MapFollowMode.freeView:
        return CupertinoIcons.hand_draw_fill;
    }
  }

  _MapFollowMode get next {
    switch (this) {
      case _MapFollowMode.followMe:
        return _MapFollowMode.headingUp;
      case _MapFollowMode.headingUp:
        return _MapFollowMode.northUp;
      case _MapFollowMode.northUp:
        return _MapFollowMode.freeView;
      case _MapFollowMode.freeView:
        return _MapFollowMode.followMe;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin {
  final GpsService _gps = GpsService.instance;
  final WeatherService _weather = WeatherService.instance;
  final SettingsService _settings = SettingsService.instance;

  final ValueNotifier<int> _tickN = ValueNotifier<int>(0);
  final ValueNotifier<double> _speedN = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _travelHdgN = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _compassN = ValueNotifier<double>(0.0);
  final ValueNotifier<int> _signalN = ValueNotifier<int>(0);
  final ValueNotifier<bool> _trackingN = ValueNotifier<bool>(false);
  final ValueNotifier<WeatherData?> _weatherN =
      ValueNotifier<WeatherData?>(null);
  final ValueNotifier<LatLng?> _posN = ValueNotifier<LatLng?>(null);
  final ValueNotifier<bool> _wxLoadingN = ValueNotifier<bool>(false);
  final ValueNotifier<int> _elapsedN = ValueNotifier<int>(0);
  final ValueNotifier<int?> _batteryN = ValueNotifier<int?>(null);
  final ValueNotifier<double> _maxSpeedN = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _accuracyN = ValueNotifier<double>(40.0);
  final ValueNotifier<_MapFollowMode> _followModeN =
      ValueNotifier<_MapFollowMode>(_MapFollowMode.followMe);
  final ValueNotifier<bool> _autoPausedN = ValueNotifier<bool>(false);
  final ValueNotifier<int> _autoPauseStoppedN = ValueNotifier<int>(0);

  bool _mapReady = false;
  bool _handlingAction = false;
  bool _disposed = false;

  int _polylinePointCount = 0;
  int _pendingSignal = 0;
  DateTime? _lastWeatherFetch;
  DateTime? _lastMapMoveAt;
  LatLng? _lastMapPos;
  int _autoPauseSlowTicks = 0;
  int _autoPauseMoveTicks = 0;
  DateTime? _autoPauseEnteredAt;

  Timer? _tickTimer;
  Timer? _signalDebounce;
  late final fm.MapController _mapController;
  late final ScrollController _scrollController;
  StreamSubscription<TripPoint>? _pointSub;
  StreamSubscription<CompassEvent>? _compassSub;

  static const MethodChannel _batteryChannel =
      MethodChannel('trackpro/battery');

  @override
  void initState() {
    super.initState();
    _mapController = fm.MapController();
    _scrollController = ScrollController();

    _settings.addListener(_onSettingsChanged);
    _hydrateInitialGpsState();
    _initCompass();
    _startTickTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) unawaited(_pollBattery());
    });

    if (_gps.isTracking) _attachGpsStream();
    unawaited(_fetchWeather(force: true));
  }

  void _hydrateInitialGpsState() {
    final points = _gps.currentPoints;
    if (points.isNotEmpty) {
      final last = points.last;
      if (_isValidLL(last.position)) {
        _posN.value = last.position;
        _lastMapPos = last.position;
      }
      _speedN.value = _safeSpeed(last.speedMph);
      _polylinePointCount = points.length;
    }

    _trackingN.value = _gps.isTracking;
    _autoPausedN.value = false;
    _autoPauseStoppedN.value = 0;
    _maxSpeedN.value = _safeSpeed(_gps.currentMaxSpeedMph);

    if (_gps.isTracking) {
      _elapsedN.value = math.max(0, _gps.currentTripTime.inSeconds);
    }
  }

  void _initCompass() {
    try {
      final stream = FlutterCompass.events;
      if (stream == null) return;

      _compassSub = stream.listen(
        (CompassEvent event) {
          if (!mounted || _disposed) return;

          final heading = event.heading;
          if (heading == null || !heading.isFinite) return;

          final current = _compassN.value;
          double delta = heading - (current % 360.0);
          if (delta > 180.0) delta -= 360.0;
          if (delta < -180.0) delta += 360.0;

          _setN(_compassN, current + delta);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Compass error: $error\n$stackTrace');
        },
        cancelOnError: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Compass init error: $error\n$stackTrace');
    }
  }

  void _startTickTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_kTick, (_) {
      if (!mounted || _disposed) return;

      _tickN.value++;

      if (_trackingN.value) {
        _setN(_elapsedN, math.max(0, _gps.currentTripTime.inSeconds));
        if (_autoPausedN.value && _autoPauseEnteredAt != null) {
          _setN(
            _autoPauseStoppedN,
            math.max(
              0,
              DateTime.now().difference(_autoPauseEnteredAt!).inSeconds,
            ),
          );
        }
      }

      if (_tickN.value % _kBatteryPoll.inSeconds == 0) {
        unawaited(_pollBattery());
      }
    });
  }

  Future<void> _pollBattery() async {
    if (!mounted || _disposed) return;

    try {
      final int? level =
          await _batteryChannel.invokeMethod<int>('getBatteryLevel');

      if (!mounted || _disposed) return;
      _setN(_batteryN, level?.clamp(0, 100).toInt());
    } on MissingPluginException {
      if (mounted && !_disposed) _setN(_batteryN, null);
    } on PlatformException catch (error) {
      debugPrint('Battery platform error: ${error.message}');
      if (mounted && !_disposed) _setN(_batteryN, null);
    } catch (error, stackTrace) {
      debugPrint('Battery poll error: $error\n$stackTrace');
      if (mounted && !_disposed) _setN(_batteryN, null);
    }
  }

  void _onSettingsChanged() {
    if (!mounted || _disposed) return;
    unawaited(_fetchWeather(force: true));
    setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;

    _settings.removeListener(_onSettingsChanged);
    _tickTimer?.cancel();
    _signalDebounce?.cancel();
    unawaited(_pointSub?.cancel());
    unawaited(_compassSub?.cancel());

    _scrollController.dispose();
    _mapController.dispose();

    _tickN.dispose();
    _speedN.dispose();
    _travelHdgN.dispose();
    _compassN.dispose();
    _signalN.dispose();
    _trackingN.dispose();
    _weatherN.dispose();
    _posN.dispose();
    _wxLoadingN.dispose();
    _elapsedN.dispose();
    _batteryN.dispose();
    _maxSpeedN.dispose();
    _accuracyN.dispose();
    _followModeN.dispose();
    _autoPausedN.dispose();
    _autoPauseStoppedN.dispose();

    super.dispose();
  }

  // ── GPS stream ─────────────────────────────────────────────────────────────

  void _attachGpsStream() {
    unawaited(_pointSub?.cancel());
    _pointSub = null;

    final stream = _gps.pointStream;
    if (stream == null) return;

    _pointSub = stream.listen(
      _onTripPoint,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('GPS stream error: $error\n$stackTrace');
      },
      cancelOnError: false,
    );
  }

  void _onTripPoint(TripPoint point) {
    if (!mounted || _disposed) return;
    if (!_isValidLL(point.position)) return;

    final double speed = _safeSpeed(point.speedMph);

    _setN(_speedN, speed);
    _setN(_posN, point.position);
    _updateAutoPause(speed);

    if (speed > _maxSpeedN.value) {
      _setN(_maxSpeedN, speed);
    }

    _updateTravelHeading(point);
    _updateSignal(point);
    _updateMapCamera(point);

    _polylinePointCount = _gps.currentPoints.length;
  }

  void _updateAutoPause(double speedMph) {
    if (!_trackingN.value) {
      _autoPauseSlowTicks = 0;
      _autoPauseMoveTicks = 0;
      return;
    }

    if (speedMph <= _kAutoPauseEnterMph) {
      _autoPauseSlowTicks++;
      _autoPauseMoveTicks = 0;
    } else if (speedMph >= _kAutoPauseResumeMph) {
      _autoPauseMoveTicks++;
      _autoPauseSlowTicks = 0;
    } else {
      _autoPauseMoveTicks = 0;
      _autoPauseSlowTicks = math.max(0, _autoPauseSlowTicks - 1);
    }

    if (!_autoPausedN.value && _autoPauseSlowTicks >= _kAutoPauseEnterSeconds) {
      _setN(_autoPausedN, true);
      _setN(_autoPauseStoppedN, 0);
      _autoPauseEnteredAt = DateTime.now();
      HapticFeedback.selectionClick();
      return;
    }

    if (_autoPausedN.value && _autoPauseMoveTicks >= _kAutoPauseResumeSeconds) {
      _setN(_autoPausedN, false);
      _setN(_autoPauseStoppedN, 0);
      _autoPauseEnteredAt = null;
      _autoPauseSlowTicks = 0;
      _autoPauseMoveTicks = 0;
      HapticFeedback.selectionClick();
    }
  }

  void _updateTravelHeading(TripPoint point) {
    if (point.speedMph <= _kMinHeadingMph) return;

    final points = _gps.currentPoints;
    if (points.length < 2) return;

    final LatLng previous = points[points.length - 2].position;
    final LatLng current = points.last.position;

    if (!_isValidLL(previous) || !_isValidLL(current)) return;

    final double bearing = const Distance().bearing(previous, current);
    if (!bearing.isFinite) return;

    final double normalized = _normDeg(bearing);
    final double old = _normDeg(_travelHdgN.value);

    double delta = normalized - old;
    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;

    _setN(_travelHdgN, _travelHdgN.value + delta);
  }

  void _updateSignal(TripPoint point) {
    final double raw = point.accuracyMeters;
    final double accuracy = raw.isFinite ? raw.clamp(5.0, 40.0) : 40.0;

    _setN(_accuracyN, accuracy);

    _pendingSignal = ((40.0 - accuracy) / 35.0 * 4.0).round().clamp(0, 4);

    _signalDebounce?.cancel();
    _signalDebounce = Timer(_kSignalDebounce, () {
      if (!mounted || _disposed) return;
      _setN(_signalN, _pendingSignal);
    });
  }

  void _updateMapCamera(TripPoint point) {
    if (!_mapReady || !_isValidLL(point.position)) return;

    final _MapFollowMode mode = _followModeN.value;
    if (mode == _MapFollowMode.freeView) return;

    final DateTime now = DateTime.now();
    final DateTime? lastMove = _lastMapMoveAt;

    if (lastMove != null && now.difference(lastMove) < _kMapThrottle) {
      return;
    }

    final LatLng? previous = _lastMapPos;
    if (previous != null && _isValidLL(previous)) {
      final double metres = const Distance().as(
        LengthUnit.Meter,
        previous,
        point.position,
      );

      if (metres.isFinite &&
          metres < _kMapMoveDist &&
          point.speedMph < _kMinHeadingMph) {
        return;
      }
    }

    _lastMapMoveAt = now;
    _lastMapPos = point.position;

    try {
      final double zoom = _mapController.camera.zoom.isFinite
          ? _mapController.camera.zoom
          : _kDefaultZoom;

      _mapController.move(point.position, zoom);

      switch (mode) {
        case _MapFollowMode.followMe:
        case _MapFollowMode.northUp:
          _mapController.rotate(0.0);
          break;
        case _MapFollowMode.headingUp:
          if (point.speedMph > _kMinHeadingMph) {
            _mapController.rotate(-_normDeg(_travelHdgN.value));
          }
          break;
        case _MapFollowMode.freeView:
          break;
      }
    } catch (error) {
      debugPrint('Map camera error: $error');
    }
  }

  void _cycleMapFollowMode() {
    HapticFeedback.selectionClick();

    final _MapFollowMode next = _followModeN.value.next;
    _setN(_followModeN, next);

    if (!_mapReady) return;

    try {
      if (next == _MapFollowMode.followMe || next == _MapFollowMode.northUp) {
        _mapController.rotate(0.0);
      }

      final LatLng? position = _posN.value;
      if (next != _MapFollowMode.freeView &&
          position != null &&
          _isValidLL(position)) {
        final double zoom = _mapController.camera.zoom.isFinite
            ? _mapController.camera.zoom
            : _kDefaultZoom;
        _mapController.move(position, zoom);
      }
    } catch (error) {
      debugPrint('Map follow mode change error: $error');
    }
  }

  // ── Weather ────────────────────────────────────────────────────────────────

  Future<void> _fetchWeather({bool force = false}) async {
    if (!_settings.showWeather) {
      _setN(_weatherN, null);
      _setN(_wxLoadingN, false);
      return;
    }

    if (_wxLoadingN.value && !force) return;

    final DateTime now = DateTime.now();
    final DateTime? last = _lastWeatherFetch;

    if (!force &&
        last != null &&
        now.difference(last) < _kWeatherGap &&
        _weatherN.value != null) {
      return;
    }

    _setN(_wxLoadingN, true);

    try {
      final Position? position = await _gps.getCurrentLocation();
      if (!mounted || _disposed) return;

      if (position == null ||
          !position.latitude.isFinite ||
          !position.longitude.isFinite) {
        _setN(_weatherN, null);
        return;
      }

      final WeatherData? data = await _weather.fetchWeather(
        position.latitude,
        position.longitude,
      );

      if (!mounted || _disposed) return;

      _lastWeatherFetch = DateTime.now();
      _setN(_weatherN, data);
    } catch (error, stackTrace) {
      debugPrint('Weather fetch error: $error\n$stackTrace');
    } finally {
      if (mounted && !_disposed) _setN(_wxLoadingN, false);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _handleAction() async {
    if (_handlingAction) return;

    _handlingAction = true;

    try {
      if (_trackingN.value) {
        await _stopTracking();
      } else {
        await _startTracking();
      }
    } finally {
      _handlingAction = false;
    }
  }

  Future<void> _startTracking() async {
    await HapticFeedback.mediumImpact();

    _elapsedN.value = 0;
    _maxSpeedN.value = 0.0;
    _speedN.value = 0.0;
    _signalN.value = 0;
    _travelHdgN.value = 0.0;
    _accuracyN.value = 40.0;
    _followModeN.value = _MapFollowMode.followMe;
    _autoPausedN.value = false;
    _autoPauseStoppedN.value = 0;
    _autoPauseSlowTicks = 0;
    _autoPauseMoveTicks = 0;
    _autoPauseEnteredAt = null;

    _polylinePointCount = 0;
    _pendingSignal = 0;
    _lastMapPos = null;
    _lastMapMoveAt = null;

    try {
      await _gps.startTracking();
    } catch (error, stackTrace) {
      debugPrint('GPS start error: $error\n$stackTrace');
    }

    if (!mounted || _disposed) return;

    if (_gps.isTracking) {
      _setN(_trackingN, true);
      _attachGpsStream();
      unawaited(_fetchWeather(force: true));
    } else {
      _promptGpsSettings();
    }
  }

  Future<void> _stopTracking() async {
    await HapticFeedback.heavyImpact();

    TripSummary? summary;

    try {
      summary = await _gps.stopTracking();
    } catch (error, stackTrace) {
      debugPrint('GPS stop error: $error\n$stackTrace');
    }

    await _pointSub?.cancel();
    _pointSub = null;

    if (!mounted || _disposed) return;

    _setN(_trackingN, false);
    _setN(_speedN, 0.0);
    _setN(_maxSpeedN, 0.0);
    _setN(_travelHdgN, 0.0);
    _setN(_elapsedN, 0);
    _setN(_signalN, 0);
    _setN(_accuracyN, 40.0);
    _setN(_autoPausedN, false);
    _setN(_autoPauseStoppedN, 0);
    _autoPauseSlowTicks = 0;
    _autoPauseMoveTicks = 0;
    _autoPauseEnteredAt = null;

    _polylinePointCount = 0;
    _pendingSignal = 0;
    _lastMapPos = null;
    _lastMapMoveAt = null;

    _signalDebounce?.cancel();

    if (_mapReady) {
      try {
        _mapController.rotate(0.0);
      } catch (_) {}
    }

    if (summary == null) return;

    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => SummaryScreen(summary: summary!),
      ),
    );
  }

  void _promptGpsSettings() {
    if (!mounted || _disposed) return;

    showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('GPS Access Required'),
          content: const Text(
            'Enable high-accuracy location to monitor your trip and live speed.',
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.pop(dialogContext);
                Geolocator.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _openMap() {
    HapticFeedback.lightImpact();

    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => MapScreen(
          points: _gps.currentPoints,
          isLive: _trackingN.value,
        ),
      ),
    );
  }

  void _openAiAssistant() {
    HapticFeedback.lightImpact();

    final Duration movingTime = _safeMovingTime(
      _gps.currentTripTime,
      _gps.currentStoppedTime,
    );

    final TripSummary liveSummary = TripSummary(
      id: 'live_${DateTime.now().millisecondsSinceEpoch}',
      date: DateTime.now(),
      totalTime: _gps.currentTripTime,
      stoppedTime: _gps.currentStoppedTime,
      movingTime: movingTime,
      maxSpeedMph: _gps.currentMaxSpeedMph,
      avgSpeedMph: _gps.currentAvgSpeedMph,
      altitudeGainFt: 0.0,
      maxAltitudeFt: 0.0,
      minAltitudeFt: 0.0,
      distanceMiles: _gps.currentDistanceMiles,
      points: List<TripPoint>.unmodifiable(_gps.currentPoints),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => AiChatSheet(summary: liveSummary),
    );
  }

  void _openFullWeather() {
    HapticFeedback.lightImpact();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WeatherSheet(
        weatherN: _weatherN,
        loadingN: _wxLoadingN,
        onRetry: () => unawaited(_fetchWeather(force: true)),
      ),
    );
  }

  void _markMapReady() {
    _mapReady = true;

    final LatLng? position = _posN.value;
    if (position == null || !_isValidLL(position)) return;

    try {
      _mapController.move(position, _kDefaultZoom);
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static void _setN<T>(ValueNotifier<T> notifier, T value) {
    if (notifier.value != value) notifier.value = value;
  }

  static bool _isValidLL(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90.0 &&
        point.latitude <= 90.0 &&
        point.longitude >= -180.0 &&
        point.longitude <= 180.0;
  }

  static double _safeSpeed(double value) {
    return value.isFinite && value >= 0.0 ? value : 0.0;
  }

  static double _normDeg(double degrees) {
    final double normalized = degrees % 360.0;
    return normalized < 0.0 ? normalized + 360.0 : normalized;
  }

  static Duration _safeMovingTime(Duration total, Duration stopped) {
    final Duration moving = total - stopped;
    return moving.isNegative ? Duration.zero : moving;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _FullScreenLiveMap(
                posN: _posN,
                mapController: _mapController,
                gps: _gps,
                settings: _settings,
                polylineCount: () => _polylinePointCount,
                onMapReady: _markMapReady,
              ),
            ),
            const Positioned.fill(child: _MapFirstGradientScrim()),
            _MapFirstTopHud(
              compassN: _compassN,
              weatherN: _weatherN,
              trackingN: _trackingN,
              tickN: _tickN,
              signalN: _signalN,
              batteryN: _batteryN,
              accuracyN: _accuracyN,
              autoPausedN: _autoPausedN,
              settings: _settings,
            ),
            _MapFirstSpeedHud(
              speedN: _speedN,
              trackingN: _trackingN,
              signalN: _signalN,
              accuracyN: _accuracyN,
              autoPausedN: _autoPausedN,
              posN: _posN,
              settings: _settings,
            ),
            _MapFirstBottomDock(
              tickN: _tickN,
              trackingN: _trackingN,
              elapsedN: _elapsedN,
              maxSpeedN: _maxSpeedN,
              autoPausedN: _autoPausedN,
              autoPauseStoppedN: _autoPauseStoppedN,
              followModeN: _followModeN,
              settings: _settings,
              gps: _gps,
              onAction: _handleAction,
              onMapTap: _openMap,
              onAiTap: _openAiAssistant,
              onWeatherTap: _openFullWeather,
              onFollowModeTap: _cycleMapFollowMode,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FULL-SCREEN MAP FIRST UI
// ═══════════════════════════════════════════════════════════════════════════════

class _FullScreenLiveMap extends StatefulWidget {
  const _FullScreenLiveMap({
    required this.posN,
    required this.mapController,
    required this.gps,
    required this.settings,
    required this.polylineCount,
    required this.onMapReady,
  });

  final ValueNotifier<LatLng?> posN;
  final fm.MapController mapController;
  final GpsService gps;
  final SettingsService settings;
  final int Function() polylineCount;
  final VoidCallback onMapReady;

  @override
  State<_FullScreenLiveMap> createState() => _FullScreenLiveMapState();
}

class _FullScreenLiveMapState extends State<_FullScreenLiveMap> {
  List<LatLng> _cachedSmooth = const <LatLng>[];
  int _cachedCount = -1;
  LatLng? _cachedLast;

  List<LatLng> _smoothedPolyline() {
    final int count = widget.polylineCount();
    final LatLng? last = widget.posN.value;

    if (count == _cachedCount && last == _cachedLast) {
      return _cachedSmooth;
    }

    final List<LatLng> raw = widget.gps.currentPoints
        .map((TripPoint point) => point.position)
        .where(_isValid)
        .toList(growable: false);

    _cachedCount = count;
    _cachedLast = last;

    if (raw.length < 2) {
      _cachedSmooth = const <LatLng>[];
      return _cachedSmooth;
    }

    final List<LatLng> simplified = simplifyPolyline(raw, epsilon: 0.00004);
    final List<LatLng> smoothed = smoothPolyline(
      simplified,
      tension: 0.5,
      subdivisions: 8,
    );

    final List<LatLng> valid = <LatLng>[];
    for (final LatLng point in smoothed) {
      if (!_isValid(point)) continue;
      if (valid.isEmpty || valid.last != point) valid.add(point);
    }

    _cachedSmooth = List<LatLng>.unmodifiable(valid);
    return _cachedSmooth;
  }

  static bool _isValid(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90.0 &&
        point.latitude <= 90.0 &&
        point.longitude >= -180.0 &&
        point.longitude <= 180.0;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: fm.FlutterMap(
        mapController: widget.mapController,
        options: fm.MapOptions(
          initialCenter: widget.posN.value ?? _kDefaultCenter,
          initialZoom: _kDefaultZoom,
          interactionOptions: const fm.InteractionOptions(
            flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
          ),
          onMapReady: widget.onMapReady,
        ),
        children: <Widget>[
          fm.TileLayer(
            urlTemplate: _mapTileUrl(widget.settings.mapStyle),
            userAgentPackageName: 'com.trackpro.ai',
            tileBuilder: _mapTileBuilder(widget.settings.mapStyle),
          ),
          ValueListenableBuilder<LatLng?>(
            valueListenable: widget.posN,
            builder: (_, __, ___) {
              final List<LatLng> polyline = _smoothedPolyline();

              if (polyline.length < 2) {
                return const SizedBox.shrink();
              }

              return fm.PolylineLayer(
                polylines: <fm.Polyline>[
                  fm.Polyline(
                    points: polyline,
                    color: _kAmber.withValues(alpha: 0.30),
                    strokeWidth: 10.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  fm.Polyline(
                    points: polyline,
                    color: _kAmberSoft,
                    strokeWidth: 4.2,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              );
            },
          ),
          ValueListenableBuilder<LatLng?>(
            valueListenable: widget.posN,
            builder: (_, LatLng? position, __) {
              if (position == null || !_isValid(position)) {
                return const SizedBox.shrink();
              }

              return fm.MarkerLayer(
                markers: <fm.Marker>[
                  fm.Marker(
                    point: position,
                    width: 70,
                    height: 70,
                    alignment: Alignment.center,
                    child: const _LiveMarker(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _mapTileUrl(AppMapStyle style) {
    final String name = style.name.toLowerCase();

    // IMPORTANT:
    // Do not use public volunteer map tile servers here because they may
    // block production apps that do not follow their tile usage policy.
    //
    // For real Apple Maps on iOS, the app must use MapKit through a plugin such
    // as apple_maps_flutter. flutter_map cannot legally render Apple Maps tiles
    // by simply changing the URL.
    if (name.contains('light')) {
      return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
    }

    if (name.contains('dark')) {
      return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
    }

    // Satellite / default.
    return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
        'World_Imagery/MapServer/tile/{z}/{y}/{x}';
  }

  static Widget Function(BuildContext, Widget, fm.TileImage)? _mapTileBuilder(
    AppMapStyle style,
  ) {
    final String name = style.name.toLowerCase();

    if (name.contains('light')) {
      return _lightTileBuilder;
    }

    if (name.contains('dark')) {
      return _darkGrayTileBuilder;
    }

    return _satelliteTileBuilder;
  }

  static Widget _lightTileBuilder(
    BuildContext context,
    Widget tile,
    fm.TileImage tileImage,
  ) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.04),
        BlendMode.darken,
      ),
      child: tile,
    );
  }

  static Widget _darkGrayTileBuilder(
    BuildContext context,
    Widget tile,
    fm.TileImage tileImage,
  ) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.02),
        BlendMode.darken,
      ),
      child: tile,
    );
  }

  static Widget _satelliteTileBuilder(
    BuildContext context,
    Widget tile,
    fm.TileImage tileImage,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.50,
        0,
        0,
        0,
        -16,
        0,
        0.50,
        0,
        0,
        -16,
        0,
        0,
        0.50,
        0,
        -16,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: tile,
    );
  }
}

class _MapFirstGradientScrim extends StatelessWidget {
  const _MapFirstGradientScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0.22),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.40),
              Colors.black.withValues(alpha: 0.90),
            ],
            stops: const <double>[0.0, 0.18, 0.46, 0.72, 1.0],
          ),
        ),
      ),
    );
  }
}

class _MapFirstFloatingModeBadge extends StatelessWidget {
  const _MapFirstFloatingModeBadge({
    required this.followModeN,
  });

  final ValueNotifier<_MapFollowMode> followModeN;

  @override
  Widget build(BuildContext context) {
    final double bottom = MediaQuery.of(context).padding.bottom + 168.0;

    return Positioned(
      left: 16,
      bottom: bottom,
      child: ValueListenableBuilder<_MapFollowMode>(
        valueListenable: followModeN,
        builder: (_, _MapFollowMode mode, __) {
          return _MapModeBadge(mode: mode);
        },
      ),
    );
  }
}

class _MapFirstTopHud extends StatelessWidget {
  const _MapFirstTopHud({
    required this.compassN,
    required this.weatherN,
    required this.trackingN,
    required this.tickN,
    required this.signalN,
    required this.batteryN,
    required this.accuracyN,
    required this.autoPausedN,
    required this.settings,
  });

  final ValueNotifier<double> compassN;
  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> tickN;
  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            children: <Widget>[
              _GlassPanel(
                radius: 26,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: <Widget>[
                    _CompassWidget(headingN: compassN),
                    const SizedBox(width: 8),
                    _TempDisplay(weatherN: weatherN, settings: settings),
                    const Spacer(),
                    _DigitalClock(tickN: tickN),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _SlimStatusPill(
                signalN: signalN,
                batteryN: batteryN,
                accuracyN: accuracyN,
                autoPausedN: autoPausedN,
                trackingN: trackingN,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlimStatusPill extends StatelessWidget {
  const _SlimStatusPill({
    required this.signalN,
    required this.batteryN,
    required this.accuracyN,
    required this.autoPausedN,
    required this.trackingN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<bool> trackingN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: trackingN,
      builder: (_, bool tracking, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: autoPausedN,
          builder: (_, bool autoPaused, __) {
            return ValueListenableBuilder<int>(
              valueListenable: signalN,
              builder: (_, int signal, __) {
                return ValueListenableBuilder<double>(
                  valueListenable: accuracyN,
                  builder: (_, double accuracy, __) {
                    return ValueListenableBuilder<int?>(
                      valueListenable: batteryN,
                      builder: (_, int? battery, __) {
                        final int safeSignal = signal.clamp(0, 4);
                        final bool hasGoodGps = safeSignal >= 2 &&
                            accuracy.isFinite &&
                            accuracy < 30.0;

                        final Color gpsColor = hasGoodGps
                            ? _kGreen
                            : tracking
                                ? _kAmberSoft
                                : _kAmberSoft;

                        final Color batteryColor = battery == null
                            ? _kTextMuted
                            : battery > 40
                                ? _kGreen
                                : battery > 20
                                    ? _kAmberSoft
                                    : _kRed;

                        final String gpsText =
                            accuracy.isFinite && accuracy < 40.0
                                ? 'GPS ±${accuracy.round()}m'
                                : tracking
                                    ? 'GPS searching'
                                    : 'GPS ready';

                        final String routeText = autoPaused
                            ? 'Auto paused'
                            : hasGoodGps || !tracking
                                ? 'Route ready'
                                : 'Route weak';

                        final Color routeColor =
                            autoPaused ? _kAmberSoft : gpsColor;

                        final String batteryText = battery == null
                            ? 'Battery --%'
                            : 'Battery $battery%';

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 345),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.48),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      CupertinoIcons.location_fill,
                                      size: 12,
                                      color: gpsColor,
                                    ),
                                    const SizedBox(width: 5),
                                    _SafeText(
                                      gpsText,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    _StatusDot(color: routeColor),
                                    Icon(
                                      autoPaused
                                          ? CupertinoIcons.pause_circle_fill
                                          : CupertinoIcons
                                              .checkmark_circle_fill,
                                      size: 12,
                                      color: routeColor,
                                    ),
                                    const SizedBox(width: 5),
                                    _SafeText(
                                      routeText,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: routeColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    _StatusDot(color: batteryColor),
                                    Icon(
                                      CupertinoIcons.battery_100,
                                      size: 12,
                                      color: batteryColor,
                                    ),
                                    const SizedBox(width: 5),
                                    _SafeText(
                                      batteryText,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: _kTextPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.80),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _MiniHudChip extends StatelessWidget {
  const _MiniHudChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          _SafeText(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          _SafeText(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              fontFeatures: const <ui.FontFeature>[
                ui.FontFeature.tabularFigures(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapFirstSpeedHud extends StatelessWidget {
  const _MapFirstSpeedHud({
    required this.speedN,
    required this.trackingN,
    required this.signalN,
    required this.accuracyN,
    required this.autoPausedN,
    required this.posN,
    required this.settings,
  });

  final ValueNotifier<double> speedN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> signalN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<LatLng?> posN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.of(context).size;
    final double side = math
        .min(screen.width * 0.74, screen.height * 0.32)
        .clamp(205.0, 290.0)
        .toDouble();

    return Positioned(
      left: 0,
      right: 0,
      top: screen.height * 0.255,
      child: Center(
        child: SizedBox(
          width: side,
          child: RepaintBoundary(
            child: ValueListenableBuilder<bool>(
              valueListenable: trackingN,
              builder: (_, bool tracking, __) {
                return ValueListenableBuilder<double>(
                  valueListenable: speedN,
                  builder: (_, double speed, __) {
                    final bool isOver =
                        tracking && speed > settings.speedAlertMph;

                    return AnimatedContainer(
                      duration: _kAnimMed,
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha: isOver ? 0.46 : 0.22,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isOver
                              ? _kRed.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.06),
                          width: isOver ? 1.5 : 0.8,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: isOver
                                ? _kRed.withValues(alpha: 0.24)
                                : Colors.black.withValues(alpha: 0.20),
                            blurRadius: isOver ? 30 : 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SpeedometerWidget(
                            speedMph: speed,
                            isOverLimit: isOver,
                          ),
                          Transform.translate(
                            offset: const Offset(0, -10),
                            child: ValueListenableBuilder<bool>(
                              valueListenable: autoPausedN,
                              builder: (_, bool autoPaused, __) {
                                return _ReadyTrackingLabel(
                                  tracking: tracking,
                                  autoPaused: autoPaused,
                                  isOverLimit: isOver,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadyTrackingLabel extends StatelessWidget {
  const _ReadyTrackingLabel({
    required this.tracking,
    required this.autoPaused,
    required this.isOverLimit,
  });

  final bool tracking;
  final bool autoPaused;
  final bool isOverLimit;

  @override
  Widget build(BuildContext context) {
    final Color color = isOverLimit
        ? _kRed
        : autoPaused
            ? _kAmberSoft
            : tracking
                ? _kGreen
                : _kAmberSoft;

    final String label = isOverLimit
        ? 'SPEED ALERT'
        : autoPaused
            ? 'AUTO PAUSED'
            : tracking
                ? 'LIVE · Tracking'
                : 'READY · Tap Start';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class _CompactRouteQualityLine extends StatelessWidget {
  const _CompactRouteQualityLine({
    required this.signalN,
    required this.accuracyN,
    required this.speedN,
    required this.trackingN,
    required this.posN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<double> speedN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<LatLng?> posN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: trackingN,
      builder: (_, bool tracking, __) {
        return ValueListenableBuilder<int>(
          valueListenable: signalN,
          builder: (_, int signal, __) {
            return ValueListenableBuilder<double>(
              valueListenable: accuracyN,
              builder: (_, double accuracy, __) {
                return ValueListenableBuilder<double>(
                  valueListenable: speedN,
                  builder: (_, double speed, __) {
                    return ValueListenableBuilder<LatLng?>(
                      valueListenable: posN,
                      builder: (_, LatLng? position, __) {
                        final _RouteQuality quality = _RouteQuality.resolve(
                          tracking: tracking,
                          signal: signal,
                          accuracy: accuracy,
                          speedMph: speed,
                          hasPosition: position != null,
                        );

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(quality.icon, color: quality.color, size: 15),
                            const SizedBox(width: 7),
                            Flexible(
                              child: _SafeText(
                                quality.title,
                                maxLines: 1,
                                style: TextStyle(
                                  color: quality.color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _RouteAccuracyPill(
                              accuracy: accuracy,
                              color: quality.color,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MapFirstBottomDock extends StatelessWidget {
  const _MapFirstBottomDock({
    required this.tickN,
    required this.trackingN,
    required this.elapsedN,
    required this.maxSpeedN,
    required this.autoPausedN,
    required this.autoPauseStoppedN,
    required this.followModeN,
    required this.settings,
    required this.gps,
    required this.onAction,
    required this.onMapTap,
    required this.onAiTap,
    required this.onWeatherTap,
    required this.onFollowModeTap,
  });

  final ValueNotifier<int> tickN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> elapsedN;
  final ValueNotifier<double> maxSpeedN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<int> autoPauseStoppedN;
  final ValueNotifier<_MapFollowMode> followModeN;
  final SettingsService settings;
  final GpsService gps;
  final VoidCallback onAction;
  final VoidCallback onMapTap;
  final VoidCallback onAiTap;
  final VoidCallback onWeatherTap;
  final VoidCallback onFollowModeTap;

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.84),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 28,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              14,
              8,
              14,
              bottomPad > 0 ? bottomPad + 8 : 14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ValueListenableBuilder<int>(
                  valueListenable: tickN,
                  builder: (_, __, ___) {
                    return Row(
                      children: <Widget>[
                        Expanded(
                          child: _DockStat(
                            label: 'DISTANCE',
                            value:
                                '${settings.toDisplayDistance(gps.currentDistanceMiles).toStringAsFixed(1)} ${settings.distanceUnit}',
                            color: _kAmberSoft,
                          ),
                        ),
                        Expanded(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: autoPausedN,
                            builder: (_, bool autoPaused, __) {
                              return _DockStat(
                                label: autoPaused ? 'PAUSED' : 'TIME',
                                value: _formatSeconds(
                                  autoPaused
                                      ? autoPauseStoppedN.value
                                      : gps.currentTripTime.inSeconds,
                                ),
                                color: autoPaused ? _kAmberSoft : _kGreen,
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: _DockStat(
                            label: 'AVG',
                            value:
                                '${settings.toDisplaySpeed(gps.currentAvgSpeedMph).round()} ${settings.speedUnit}',
                            color: _kBlue,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: autoPausedN,
                  builder: (_, bool autoPaused, __) {
                    if (!autoPaused) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: _AutoPauseBanner(
                        stoppedN: autoPauseStoppedN,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: ValueListenableBuilder<_MapFollowMode>(
                        valueListenable: followModeN,
                        builder: (_, _MapFollowMode mode, __) {
                          return _DockIconButton(
                            icon: mode.icon,
                            label: mode.label,
                            onTap: onFollowModeTap,
                            color: _kBlue,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: trackingN,
                        builder: (_, bool tracking, __) {
                          return _PrimaryActionButton(
                            isTracking: tracking,
                            onTap: onAction,
                            timerNotifier: elapsedN,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DockIconButton(
                        icon: Icons.auto_awesome_rounded,
                        label: 'AI',
                        onTap: onAiTap,
                        color: _kAmberSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _DockIconButton(
                        icon: CupertinoIcons.map_fill,
                        label: 'FULL MAP',
                        onTap: onMapTap,
                        color: _kGreen,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DockIconButton(
                        icon: CupertinoIcons.cloud_sun_fill,
                        label: 'WEATHER',
                        onTap: onWeatherTap,
                        color: _kAmberSoft,
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatSeconds(int seconds) {
    final int safeSeconds = math.max(0, seconds);
    final int hours = safeSeconds ~/ 3600;
    final String minutes =
        ((safeSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final String secs = (safeSeconds % 60).toString().padLeft(2, '0');

    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$secs'
        : '$minutes:$secs';
  }
}

class _AutoPauseBanner extends StatelessWidget {
  const _AutoPauseBanner({
    required this.stoppedN,
  });

  final ValueNotifier<int> stoppedN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: stoppedN,
      builder: (_, int seconds, __) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _kAmberSoft.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _kAmberSoft.withValues(alpha: 0.18),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.pause_circle_fill,
                      color: _kAmberSoft,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    _SafeText(
                      'AUTO PAUSED · ${_MapFirstBottomDock._formatSeconds(seconds)} · MOVE TO RESUME',
                      maxLines: 1,
                      style: const TextStyle(
                        color: _kAmberSoft,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DockStat extends StatelessWidget {
  const _DockStat({
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
          value,
          maxLines: 1,
          style: const TextStyle(
            color: _kTextPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(height: 3),
        _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: compact ? 35 : 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: compact ? 12 : 14),
            SizedBox(height: compact ? 2 : 3),
            _SafeText(
              label,
              maxLines: 1,
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: compact ? 7.5 : 8.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAFE TEXT — avoids Flutter Web EllipsisFragment hit-test assertion
// ═══════════════════════════════════════════════════════════════════════════════

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: style,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND
// ═══════════════════════════════════════════════════════════════════════════════

class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground({required this.child});

  final Widget child;

  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (_, Widget? child) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.lerp(
                const Alignment(-0.38, -0.70),
                const Alignment(0.42, -0.95),
                _animation.value,
              )!,
              radius: 1.04 + _animation.value * 0.22,
              colors: const <Color>[
                Color(0xFF1B1200),
                Color(0xFF0C0800),
                Color(0xFF000000),
              ],
              stops: const <double>[0.0, 0.48, 1.0],
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -90 + _animation.value * 22,
                top: 96,
                child: _AmbientOrb(
                  size: 210,
                  color: _kAmber.withValues(alpha: 0.07),
                ),
              ),
              Positioned(
                left: -120,
                bottom: 180 - _animation.value * 18,
                child: _AmbientOrb(
                  size: 250,
                  color: _kBlue.withValues(alpha: 0.045),
                ),
              ),
              child!,
            ],
          ),
        );
      },
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color,
              blurRadius: size * 0.45,
              spreadRadius: size * 0.16,
            ),
          ],
        ),
        child: SizedBox.square(dimension: size),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.compassN,
    required this.weatherN,
    required this.trackingN,
    required this.tickN,
    required this.settings,
  });

  final ValueNotifier<double> compassN;
  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> tickN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: _GlassPanel(
          radius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: <Widget>[
              _CompassWidget(headingN: compassN),
              const SizedBox(width: 12),
              _TempDisplay(weatherN: weatherN, settings: settings),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: trackingN,
                builder: (_, bool tracking, __) {
                  return AnimatedSwitcher(
                    duration: _kAnimMed,
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (Widget child, Animation<double> anim) {
                      return FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child),
                      );
                    },
                    child: tracking
                        ? const _LivePill(key: ValueKey<String>('live'))
                        : const _IdlePill(key: ValueKey<String>('idle')),
                  );
                },
              ),
              const SizedBox(width: 10),
              _DigitalClock(tickN: tickN),
            ],
          ),
        ),
      ),
    );
  }
}

class _TempDisplay extends StatelessWidget {
  const _TempDisplay({
    required this.weatherN,
    required this.settings,
  });

  final ValueNotifier<WeatherData?> weatherN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: weatherN,
      builder: (_, WeatherData? weather, __) {
        final bool metric = settings.useKmh;
        final String unit = metric ? '°C' : '°F';

        String value = '--';
        if (weather != null) {
          final double temp =
              metric ? weather.temperature : (weather.temperature * 9 / 5) + 32;
          value = temp.isFinite ? temp.round().toString() : '--';
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SafeText(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -0.4,
                fontFeatures: <ui.FontFeature>[
                  ui.FontFeature.tabularFigures(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1, left: 2),
              child: _SafeText(
                unit,
                maxLines: 1,
                style: const TextStyle(
                  color: _kAmberSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DigitalClock extends StatelessWidget {
  const _DigitalClock({required this.tickN});

  final ValueNotifier<int> tickN;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tickN,
      builder: (_, __, ___) {
        final DateTime now = DateTime.now();
        final String h = now.hour.toString().padLeft(2, '0');
        final String m = now.minute.toString().padLeft(2, '0');
        final String s = now.second.toString().padLeft(2, '0');

        return IgnorePointer(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFeatures: <ui.FontFeature>[
                  ui.FontFeature.tabularFigures(),
                ],
                letterSpacing: -0.5,
                height: 1.0,
              ),
              children: <InlineSpan>[
                TextSpan(
                  text: '$h:$m',
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: ':$s',
                  style: const TextStyle(
                    color: _kTextMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPEEDOMETER
// ═══════════════════════════════════════════════════════════════════════════════

class _SpeedometerSection extends StatelessWidget {
  const _SpeedometerSection({
    required this.speedN,
    required this.trackingN,
    required this.settings,
  });

  final ValueNotifier<double> speedN;
  final ValueNotifier<bool> trackingN;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: trackingN,
        builder: (_, bool tracking, __) {
          return ValueListenableBuilder<double>(
            valueListenable: speedN,
            builder: (_, double speed, __) {
              final bool isOver = tracking && speed > settings.speedAlertMph;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedContainer(
                  duration: _kAnimMed,
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        isOver
                            ? _kRedGlow.withValues(alpha: 0.38)
                            : Colors.white.withValues(alpha: 0.085),
                        isOver
                            ? _kRedGlow.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.025),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: isOver
                          ? _kRed.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.08),
                      width: isOver ? 1.5 : 1.0,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: isOver
                            ? _kRed.withValues(alpha: 0.24)
                            : Colors.black.withValues(alpha: 0.34),
                        blurRadius: isOver ? 34 : 24,
                        spreadRadius: isOver ? 1 : 0,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: SpeedometerWidget(
                    speedMph: speed,
                    isOverLimit: isOver,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATUS ROW
// ═══════════════════════════════════════════════════════════════════════════════

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.signalN,
    required this.batteryN,
    required this.accuracyN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<int?> batteryN;
  final ValueNotifier<double> accuracyN;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: signalN,
              builder: (_, int strength, __) {
                final int signal = strength.clamp(0, 4);

                return ValueListenableBuilder<double>(
                  valueListenable: accuracyN,
                  builder: (_, double accuracy, __) {
                    final String value =
                        accuracy < 40 ? '±${accuracy.round()}m' : '--';

                    return _StatusChip(
                      label: 'GPS SIGNAL',
                      leading: _SignalBars(strength: signal),
                      value: value,
                      valueColor: _signalColor(signal),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder<int?>(
              valueListenable: batteryN,
              builder: (_, int? percent, __) {
                return _StatusChip(
                  label: 'BATTERY',
                  leading: _BatteryIcon(percent: percent),
                  value: percent == null ? '--%' : '$percent%',
                  valueColor: _batteryColor(percent),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Color _signalColor(int signal) {
    if (signal >= 3) return _kGreen;
    if (signal >= 2) return _kAmber;
    return _kRed;
  }

  static Color _batteryColor(int? percent) {
    if (percent == null) return _kTextMuted;
    if (percent > 40) return _kGreen;
    if (percent > 20) return const Color(0xFFFFCC00);
    return _kRed;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.leading,
    required this.value,
    this.valueColor = _kTextPrimary,
  });

  final String label;
  final Widget leading;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: <Widget>[
          leading,
          const SizedBox(width: 9),
          Expanded(
            child: _SafeText(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SafeText(
            value,
            maxLines: 1,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIVE ROUTE QUALITY INDICATOR
// ═══════════════════════════════════════════════════════════════════════════════

class _RouteQualityCard extends StatelessWidget {
  const _RouteQualityCard({
    required this.signalN,
    required this.accuracyN,
    required this.speedN,
    required this.trackingN,
    required this.posN,
  });

  final ValueNotifier<int> signalN;
  final ValueNotifier<double> accuracyN;
  final ValueNotifier<double> speedN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<LatLng?> posN;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: trackingN,
        builder: (_, bool tracking, __) {
          return ValueListenableBuilder<int>(
            valueListenable: signalN,
            builder: (_, int signal, __) {
              return ValueListenableBuilder<double>(
                valueListenable: accuracyN,
                builder: (_, double accuracy, __) {
                  return ValueListenableBuilder<double>(
                    valueListenable: speedN,
                    builder: (_, double speed, __) {
                      return ValueListenableBuilder<LatLng?>(
                        valueListenable: posN,
                        builder: (_, LatLng? position, __) {
                          final _RouteQuality quality = _RouteQuality.resolve(
                            tracking: tracking,
                            signal: signal,
                            accuracy: accuracy,
                            speedMph: speed,
                            hasPosition: position != null,
                          );

                          return _GlassPanel(
                            radius: 20,
                            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                            child: Row(
                              children: <Widget>[
                                _RouteQualityBadge(quality: quality),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          _SafeText(
                                            quality.title,
                                            maxLines: 1,
                                            style: TextStyle(
                                              color: quality.color,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (tracking)
                                            _SafeText(
                                              speed < 1.0
                                                  ? 'STATIONARY'
                                                  : 'MOVING',
                                              maxLines: 1,
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.35),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      _SafeText(
                                        quality.message,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          color: _kTextMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _RouteAccuracyPill(
                                  accuracy: accuracy,
                                  color: quality.color,
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _RouteQuality {
  const _RouteQuality({
    required this.title,
    required this.message,
    required this.color,
    required this.icon,
    required this.score,
  });

  final String title;
  final String message;
  final Color color;
  final IconData icon;
  final double score;

  static _RouteQuality resolve({
    required bool tracking,
    required int signal,
    required double accuracy,
    required double speedMph,
    required bool hasPosition,
  }) {
    final int safeSignal = signal.clamp(0, 4);
    final double safeAccuracy =
        accuracy.isFinite ? accuracy.clamp(5.0, 40.0) : 40.0;

    if (!tracking) {
      return const _RouteQuality(
        title: 'ROUTE QUALITY READY',
        message: 'Start tracking to measure live GPS route quality.',
        color: _kAmberSoft,
        icon: CupertinoIcons.location,
        score: 0.42,
      );
    }

    if (!hasPosition || safeSignal <= 0) {
      return const _RouteQuality(
        title: 'SEARCHING GPS',
        message: 'Waiting for accurate location before drawing the route.',
        color: _kRed,
        icon: CupertinoIcons.location_slash,
        score: 0.14,
      );
    }

    if (safeAccuracy <= 8.0 && safeSignal >= 3) {
      return const _RouteQuality(
        title: 'EXCELLENT ROUTE',
        message: 'Strong GPS lock. Route line should be very accurate.',
        color: _kGreen,
        icon: CupertinoIcons.check_mark_circled_solid,
        score: 1.0,
      );
    }

    if (safeAccuracy <= 18.0 && safeSignal >= 2) {
      return const _RouteQuality(
        title: 'GOOD ROUTE',
        message: 'GPS is stable. Route quality is good for live tracking.',
        color: _kAmberSoft,
        icon: CupertinoIcons.location_fill,
        score: 0.72,
      );
    }

    if (speedMph < 1.0 && safeAccuracy <= 28.0) {
      return const _RouteQuality(
        title: 'IDLE GPS DRIFT',
        message: 'You are still. Small GPS drift may appear on the map.',
        color: _kBlue,
        icon: CupertinoIcons.scope,
        score: 0.55,
      );
    }

    return const _RouteQuality(
      title: 'WEAK ROUTE QUALITY',
      message: 'Move outdoors or wait for better GPS accuracy.',
      color: _kRed,
      icon: CupertinoIcons.exclamationmark_triangle_fill,
      score: 0.32,
    );
  }
}

class _RouteQualityBadge extends StatelessWidget {
  const _RouteQualityBadge({required this.quality});

  final _RouteQuality quality;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CircularProgressIndicator(
            value: quality.score,
            strokeWidth: 3.2,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(quality.color),
          ),
          Icon(
            quality.icon,
            color: quality.color,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _RouteAccuracyPill extends StatelessWidget {
  const _RouteAccuracyPill({
    required this.accuracy,
    required this.color,
  });

  final double accuracy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String label =
        accuracy.isFinite && accuracy < 40.0 ? '±${accuracy.round()}m' : '--';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            fontFeatures: const <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

class _GridDashboard extends StatelessWidget {
  const _GridDashboard({
    required this.tickN,
    required this.posN,
    required this.weatherN,
    required this.loadingN,
    required this.maxSpeedN,
    required this.followModeN,
    required this.settings,
    required this.gps,
    required this.mapController,
    required this.polylineCount,
    required this.onMapReady,
    required this.onMapTap,
    required this.onWeatherTap,
    required this.onFollowModeTap,
  });

  final ValueNotifier<int> tickN;
  final ValueNotifier<LatLng?> posN;
  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> loadingN;
  final ValueNotifier<double> maxSpeedN;
  final ValueNotifier<_MapFollowMode> followModeN;
  final SettingsService settings;
  final GpsService gps;
  final fm.MapController mapController;
  final int Function() polylineCount;
  final VoidCallback onMapReady;
  final VoidCallback onMapTap;
  final VoidCallback onWeatherTap;
  final VoidCallback onFollowModeTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: tickN,
            builder: (_, __, ___) {
              final double distance =
                  settings.toDisplayDistance(gps.currentDistanceMiles);
              final double average =
                  settings.toDisplaySpeed(gps.currentAvgSpeedMph);

              return Row(
                children: <Widget>[
                  Expanded(
                    child: _StatCard(
                      label: 'DISTANCE',
                      value: _safeNum(distance),
                      unit: settings.distanceUnit,
                      isDecimal: true,
                      icon: CupertinoIcons.location_fill,
                      accent: _kAmber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'AVG SPEED',
                      value: _safeNum(average),
                      unit: settings.speedUnit,
                      isDecimal: false,
                      icon: CupertinoIcons.speedometer,
                      accent: _kGreen,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: ValueListenableBuilder<double>(
                  valueListenable: maxSpeedN,
                  builder: (_, double maxMph, __) {
                    return _StatCard(
                      label: 'MAX SPEED',
                      value: _safeNum(settings.toDisplaySpeed(maxMph)),
                      unit: settings.speedUnit,
                      isDecimal: false,
                      icon: CupertinoIcons.bolt_fill,
                      accent: _kAmberSoft,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickN,
                  builder: (_, __, ___) {
                    final Duration moving = _safeMoving(
                      gps.currentTripTime,
                      gps.currentStoppedTime,
                    );

                    return _StatCard(
                      label: 'MOVING TIME',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.timer_fill,
                      accent: _kGreen,
                      overrideText: _fmtDuration(moving),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickN,
                  builder: (_, __, ___) {
                    return _StatCard(
                      label: 'STOPPED',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.pause_fill,
                      accent: _kRed,
                      overrideText: _fmtDuration(gps.currentStoppedTime),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickN,
                  builder: (_, __, ___) {
                    return _StatCard(
                      label: 'TOTAL TIME',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.clock_fill,
                      accent: _kAmber,
                      overrideText: _fmtDuration(gps.currentTripTime),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MapFollowModeStrip(
            followModeN: followModeN,
            onTap: onFollowModeTap,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 194,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _MapThumbnail(
                    posN: posN,
                    mapController: mapController,
                    gps: gps,
                    polylineCount: polylineCount,
                    onMapReady: onMapReady,
                    onTap: onMapTap,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: settings.showWeather
                      ? _WeatherThumbnail(
                          weatherN: weatherN,
                          loadingN: loadingN,
                          onTap: onWeatherTap,
                        )
                      : const _EmptyCard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _safeNum(double value) {
    return value.isFinite && value >= 0.0 ? value : 0.0;
  }

  static Duration _safeMoving(Duration total, Duration stopped) {
    final Duration moving = total - stopped;
    return moving.isNegative ? Duration.zero : moving;
  }

  static String _fmtDuration(Duration duration) {
    final int seconds = math.max(0, duration.inSeconds);
    final int hours = seconds ~/ 3600;
    final String minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final String secs = (seconds % 60).toString().padLeft(2, '0');

    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$secs'
        : '$minutes:$secs';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STAT CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _StatCard extends StatefulWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.isDecimal,
    required this.icon,
    this.accent,
    this.overrideText,
  });

  final String label;
  final double value;
  final String unit;
  final bool isDecimal;
  final IconData icon;
  final Color? accent;
  final String? overrideText;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  late double _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
  }

  @override
  void didUpdateWidget(covariant _StatCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.overrideText != null &&
        oldWidget.overrideText != widget.overrideText) {
      _previousValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? _kAmber;
    final double begin = _previousValue;

    return _GlassPanel(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.20),
                  ),
                ),
                child: Icon(widget.icon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SafeText(
                  widget.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: widget.overrideText != null
                ? _SafeText(
                    widget.overrideText!,
                    maxLines: 1,
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      fontFeatures: const <ui.FontFeature>[
                        ui.FontFeature.tabularFigures(),
                      ],
                      shadows: <Shadow>[
                        Shadow(
                          color: accent.withValues(alpha: 0.28),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: begin,
                          end: widget.value,
                        ),
                        duration: _kAnimMed,
                        curve: Curves.easeOutCubic,
                        onEnd: () {
                          _previousValue = widget.value;
                        },
                        builder: (_, double value, __) {
                          return _SafeText(
                            widget.isDecimal
                                ? value.toStringAsFixed(1)
                                : value.round().toString(),
                            maxLines: 1,
                            style: TextStyle(
                              color: _kTextPrimary,
                              fontSize: 31,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              fontFeatures: const <ui.FontFeature>[
                                ui.FontFeature.tabularFigures(),
                              ],
                              shadows: <Shadow>[
                                Shadow(
                                  color: accent.withValues(alpha: 0.28),
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (widget.unit.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 5),
                        _SafeText(
                          widget.unit,
                          maxLines: 1,
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART MAP FOLLOW MODE
// ═══════════════════════════════════════════════════════════════════════════════

class _MapFollowModeStrip extends StatelessWidget {
  const _MapFollowModeStrip({
    required this.followModeN,
    required this.onTap,
  });

  final ValueNotifier<_MapFollowMode> followModeN;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_MapFollowMode>(
      valueListenable: followModeN,
      builder: (_, _MapFollowMode mode, __) {
        return _PressableScale(
          onTap: onTap,
          child: _GlassPanel(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _kBlue.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Icon(
                    mode.icon,
                    color: _kBlue,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const _SafeText(
                        'SMART MAP FOLLOW',
                        maxLines: 1,
                        style: TextStyle(
                          color: _kTextMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          _SafeText(
                            mode.label,
                            maxLines: 1,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: _SafeText(
                              mode.subtitle,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.055),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _SafeText(
                        'CHANGE',
                        maxLines: 1,
                        style: TextStyle(
                          color: _kAmberSoft,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: _kAmberSoft,
                        size: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MapModeBadge extends StatelessWidget {
  const _MapModeBadge({
    required this.mode,
  });

  final _MapFollowMode mode;

  @override
  Widget build(BuildContext context) {
    final Color color = mode == _MapFollowMode.freeView ? _kAmberSoft : _kBlue;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: color.withValues(alpha: 0.26),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(mode.icon, color: color, size: 12),
                const SizedBox(width: 5),
                _SafeText(
                  mode.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
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

// ═══════════════════════════════════════════════════════════════════════════════
// MAP THUMBNAIL
// ═══════════════════════════════════════════════════════════════════════════════

class _MapThumbnail extends StatefulWidget {
  const _MapThumbnail({
    required this.posN,
    required this.mapController,
    required this.gps,
    required this.polylineCount,
    required this.onMapReady,
    required this.onTap,
  });

  final ValueNotifier<LatLng?> posN;
  final fm.MapController mapController;
  final GpsService gps;
  final int Function() polylineCount;
  final VoidCallback onMapReady;
  final VoidCallback onTap;

  @override
  State<_MapThumbnail> createState() => _MapThumbnailState();
}

class _MapThumbnailState extends State<_MapThumbnail> {
  List<LatLng> _cachedSmooth = const <LatLng>[];
  int _cachedCount = -1;
  LatLng? _cachedLast;

  List<LatLng> _smoothedPolyline() {
    final int count = widget.polylineCount();
    final LatLng? last = widget.posN.value;

    if (count == _cachedCount && last == _cachedLast) {
      return _cachedSmooth;
    }

    final List<LatLng> raw = widget.gps.currentPoints
        .map((TripPoint p) => p.position)
        .where(_isValid)
        .toList(growable: false);

    _cachedCount = count;
    _cachedLast = last;

    if (raw.length < 2) {
      _cachedSmooth = const <LatLng>[];
      return _cachedSmooth;
    }

    final List<LatLng> simplified = simplifyPolyline(raw, epsilon: 0.00004);
    final List<LatLng> smoothed = smoothPolyline(
      simplified,
      tension: 0.5,
      subdivisions: 8,
    );

    final List<LatLng> valid = <LatLng>[];
    for (final LatLng point in smoothed) {
      if (!_isValid(point)) continue;
      if (valid.isEmpty || valid.last != point) valid.add(point);
    }

    _cachedSmooth = List<LatLng>.unmodifiable(valid);
    return _cachedSmooth;
  }

  static bool _isValid(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: _GlassPanel(
          radius: 24,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: <Widget>[
                AbsorbPointer(
                  child: fm.FlutterMap(
                    mapController: widget.mapController,
                    options: fm.MapOptions(
                      initialCenter: widget.posN.value ?? _kDefaultCenter,
                      initialZoom: _kDefaultZoom,
                      interactionOptions: const fm.InteractionOptions(
                        flags: fm.InteractiveFlag.none,
                      ),
                      onMapReady: widget.onMapReady,
                    ),
                    children: <Widget>[
                      fm.TileLayer(
                        urlTemplate:
                            'https://server.arcgisonline.com/ArcGIS/rest/services/'
                            'World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.trackpro.ai',
                        tileBuilder: _legacySatelliteDarkTileBuilder,
                      ),
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: widget.posN,
                        builder: (_, __, ___) {
                          final List<LatLng> polyline = _smoothedPolyline();

                          if (polyline.length < 2) {
                            return const SizedBox.shrink();
                          }

                          return fm.PolylineLayer(
                            polylines: <fm.Polyline>[
                              fm.Polyline(
                                points: polyline,
                                color: _kAmber.withValues(alpha: 0.30),
                                strokeWidth: 8.0,
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                              ),
                              fm.Polyline(
                                points: polyline,
                                color: _kAmberSoft,
                                strokeWidth: 3.5,
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                              ),
                            ],
                          );
                        },
                      ),
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: widget.posN,
                        builder: (_, LatLng? position, __) {
                          if (position == null || !_isValid(position)) {
                            return const SizedBox.shrink();
                          }

                          return fm.MarkerLayer(
                            markers: <fm.Marker>[
                              fm.Marker(
                                point: position,
                                width: 60,
                                height: 60,
                                alignment: Alignment.center,
                                child: const _LiveMarker(),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  left: 12,
                  top: 12,
                  child: _OverlayLabel(
                    icon: CupertinoIcons.map_fill,
                    label: 'LIVE MAP',
                  ),
                ),
                const Positioned(
                  top: 12,
                  right: 12,
                  child: _ExpandIcon(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _darkTileBuilder(
    BuildContext context,
    Widget tile,
    fm.TileImage tileImage,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.58,
        0,
        0,
        0,
        -8,
        0,
        0.58,
        0,
        0,
        -8,
        0,
        0,
        0.58,
        0,
        -8,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: tile,
    );
  }
}

Widget _legacySatelliteDarkTileBuilder(
  BuildContext context,
  Widget tile,
  fm.TileImage tileImage,
) {
  return ColorFiltered(
    colorFilter: const ColorFilter.matrix(<double>[
      0.58,
      0,
      0,
      0,
      -8,
      0,
      0.58,
      0,
      0,
      -8,
      0,
      0,
      0.58,
      0,
      -8,
      0,
      0,
      0,
      1,
      0,
    ]),
    child: tile,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEATHER THUMBNAIL + SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _WeatherThumbnail extends StatelessWidget {
  const _WeatherThumbnail({
    required this.weatherN,
    required this.loadingN,
    required this.onTap,
  });

  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> loadingN;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: RepaintBoundary(
        child: _GlassPanel(
          radius: 24,
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ValueListenableBuilder<WeatherData?>(
                    valueListenable: weatherN,
                    builder: (_, WeatherData? weather, __) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: loadingN,
                        builder: (_, bool loading, __) {
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 300,
                              height: 220,
                              child: WeatherWidget(
                                weather: weather,
                                isLoading: loading && weather == null,
                                onRetry: () {},
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Positioned(
                  left: 12,
                  top: 12,
                  child: _OverlayLabel(
                    icon: CupertinoIcons.cloud_sun_fill,
                    label: 'WEATHER',
                  ),
                ),
                const Positioned(
                  top: 12,
                  right: 12,
                  child: _ExpandIcon(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherSheet extends StatelessWidget {
  const _WeatherSheet({
    required this.weatherN,
    required this.loadingN,
    required this.onRetry,
  });

  final ValueNotifier<WeatherData?> weatherN;
  final ValueNotifier<bool> loadingN;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 70),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 14),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    CupertinoIcons.cloud_sun_fill,
                    color: _kAmberSoft,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  _SafeText(
                    'LIVE WEATHER',
                    maxLines: 1,
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: _kBorder, thickness: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 38),
              child: ValueListenableBuilder<WeatherData?>(
                valueListenable: weatherN,
                builder: (_, WeatherData? weather, __) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: loadingN,
                    builder: (_, bool loading, __) {
                      return WeatherWidget(
                        weather: weather,
                        isLoading: loading && weather == null,
                        onRetry: onRetry,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM DOCK
// ═══════════════════════════════════════════════════════════════════════════════

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.trackingN,
    required this.elapsedN,
    required this.onAction,
    required this.onMapTap,
    required this.onAiTap,
  });

  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> elapsedN;
  final VoidCallback onAction;
  final VoidCallback onMapTap;
  final VoidCallback onAiTap;

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: _kSurface.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            bottomPad > 0 ? bottomPad + 10 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SecondaryButton(
                      icon: CupertinoIcons.map_fill,
                      label: 'FULL MAP',
                      onTap: onMapTap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SecondaryButton(
                      icon: Icons.auto_awesome_rounded,
                      label: 'ASK AI',
                      onTap: onAiTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<bool>(
                valueListenable: trackingN,
                builder: (_, bool tracking, __) {
                  return _PrimaryActionButton(
                    isTracking: tracking,
                    onTap: onAction,
                    timerNotifier: elapsedN,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED UI
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.105),
            Colors.white.withValues(alpha: 0.043),
            Colors.white.withValues(alpha: 0.018),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.075),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: _kAmberDeep.withValues(alpha: 0.05),
            blurRadius: 30,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PressableScale extends StatefulWidget {
  const _PressableScale({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: _kAnimFast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: _kAmberSoft, size: 12),
                const SizedBox(width: 5),
                _SafeText(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
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

class _ExpandIcon extends StatelessWidget {
  const _ExpandIcon();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 31,
          height: 31,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
            ),
          ),
          child: const Icon(
            CupertinoIcons.fullscreen,
            size: 14,
            color: _kTextPrimary,
          ),
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: _kRed.withValues(alpha: 0.28),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LiveDot(),
          SizedBox(width: 7),
          _SafeText(
            'LIVE',
            maxLines: 1,
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _IdlePill extends StatelessWidget {
  const _IdlePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: const Center(
        child: _SafeText(
          'READY',
          maxLines: 1,
          style: TextStyle(
            color: _kTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      radius: 24,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              color: Colors.white.withValues(alpha: 0.22),
              size: 28,
            ),
            const SizedBox(height: 6),
            _SafeText(
              'WEATHER OFF',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.22),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPASS
// ═══════════════════════════════════════════════════════════════════════════════

class _CompassWidget extends StatefulWidget {
  const _CompassWidget({required this.headingN});

  final ValueNotifier<double> headingN;

  @override
  State<_CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<_CompassWidget> {
  double _previousRad = 0.0;

  static const List<String> _cardinals = <String>[
    'N',
    'NE',
    'E',
    'SE',
    'S',
    'SW',
    'W',
    'NW',
  ];

  static String _cardinal(double degrees) {
    return _cardinals[((degrees + 22.5) / 45.0).floor() % 8];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.headingN,
      builder: (_, double unwrapped, __) {
        final double deg = unwrapped % 360.0;
        final double normal = deg < 0.0 ? deg + 360.0 : deg;
        final String label = _cardinal(normal);
        final double target = unwrapped * (math.pi / 180.0);
        final double begin = _previousRad;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: begin, end: target),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          onEnd: () => _previousRad = target,
          builder: (_, double radians, __) {
            return Row(
              children: <Widget>[
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.35),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const SizedBox.expand(),
                      ),
                      Transform.rotate(
                        angle: radians,
                        child: const CustomPaint(
                          size: Size(38, 38),
                          painter: _NeedlePainter(),
                        ),
                      ),
                      const CustomPaint(
                        size: Size(38, 38),
                        painter: _CompassRingPainter(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _SafeText(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CompassRingPainter extends CustomPainter {
  const _CompassRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);
    final double radius = size.width / 2.0 - 3.0;

    final Paint paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final double radians = i * 45.0 * (math.pi / 180.0) - math.pi / 2.0;
      final double length = i.isEven ? 4.5 : 3.0;

      final Offset outer = center +
          Offset(
            math.cos(radians) * radius,
            math.sin(radians) * radius,
          );

      final Offset inner = center +
          Offset(
            math.cos(radians) * (radius - length),
            math.sin(radians) * (radius - length),
          );

      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassRingPainter oldDelegate) => false;
}

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);

    canvas.drawPath(
      ui.Path()
        ..moveTo(center.dx, center.dy - 12.0)
        ..lineTo(center.dx - 3.0, center.dy)
        ..lineTo(center.dx + 3.0, center.dy)
        ..close(),
      Paint()
        ..color = _kRed
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      ui.Path()
        ..moveTo(center.dx, center.dy + 12.0)
        ..lineTo(center.dx - 3.0, center.dy)
        ..lineTo(center.dx + 3.0, center.dy)
        ..close(),
      Paint()
        ..color = Colors.white30
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIGNAL / BATTERY / MARKERS
// ═══════════════════════════════════════════════════════════════════════════════

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.strength});

  final int strength;

  @override
  Widget build(BuildContext context) {
    final int safeStrength = strength.clamp(0, 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List<Widget>.generate(4, (int index) {
        final bool active = index < safeStrength;

        final Color color;
        if (!active) {
          color = Colors.white12;
        } else if (safeStrength >= 3) {
          color = _kGreen;
        } else if (safeStrength >= 2) {
          color = _kAmber;
        } else {
          color = _kRed;
        }

        return AnimatedContainer(
          duration: _kAnimMed,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 4,
          height: active ? 8.0 + index * 4.0 : 6.0 + index * 3.0,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
            boxShadow: active
                ? <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.50),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  const _BatteryIcon({required this.percent});

  final int? percent;

  Color get _color {
    final int? value = percent;
    if (value == null) return Colors.white38;
    if (value > 40) return _kGreen;
    if (value > 20) return const Color(0xFFFFCC00);
    return _kRed;
  }

  IconData get _icon {
    final int? value = percent;
    if (value == null) return CupertinoIcons.battery_0;
    if (value > 75) return CupertinoIcons.battery_100;
    if (value > 20) return CupertinoIcons.battery_25;
    return CupertinoIcons.battery_0;
  }

  @override
  Widget build(BuildContext context) {
    return Icon(_icon, size: 20, color: _color);
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();

    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kRed.withValues(alpha: 0.5 + _animation.value * 0.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _kRed.withValues(alpha: 0.4),
                blurRadius: 8 + _animation.value * 10,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveMarker extends StatefulWidget {
  const _LiveMarker();

  @override
  State<_LiveMarker> createState() => _LiveMarkerState();
}

class _LiveMarkerState extends State<_LiveMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _pulse = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Opacity(
                opacity: (1.0 - _pulse.value).clamp(0.0, 1.0),
                child: Container(
                  width: 20 + _pulse.value * 38,
                  height: 20 + _pulse.value * 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _kGreen.withValues(alpha: 0.60),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGreen,
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kGreen.withValues(alpha: 0.60),
                      blurRadius: 16,
                    ),
                    const BoxShadow(
                      color: Colors.black54,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUTTONS
// ═══════════════════════════════════════════════════════════════════════════════

class _SecondaryButton extends StatefulWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: _kAnimFast,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: _kAnimFast,
          height: 50,
          decoration: BoxDecoration(
            color: _pressed
                ? Colors.white.withValues(alpha: 0.115)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.075),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(widget.icon, color: _kAmberSoft, size: 17),
              const SizedBox(width: 8),
              Flexible(
                child: _SafeText(
                  widget.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatefulWidget {
  const _PrimaryActionButton({
    required this.isTracking,
    required this.onTap,
    required this.timerNotifier,
  });

  final bool isTracking;
  final VoidCallback onTap;
  final ValueNotifier<int> timerNotifier;

  @override
  State<_PrimaryActionButton> createState() => _PrimaryActionButtonState();
}

class _PrimaryActionButtonState extends State<_PrimaryActionButton> {
  bool _pressed = false;

  static String _formatSeconds(int seconds) {
    final int safeSeconds = math.max(0, seconds);
    final int hours = safeSeconds ~/ 3600;
    final String minutes =
        ((safeSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final String secs = (safeSeconds % 60).toString().padLeft(2, '0');

    return hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$secs'
        : '$minutes:$secs';
  }

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Color main = widget.isTracking ? _kRed : _kGreen;
    final Color textColor = widget.isTracking ? Colors.white : Colors.black;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: _kAnimFast,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: _kAnimFast,
          curve: Curves.easeOut,
          height: 50,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _pressed
                  ? <Color>[
                      main.withValues(alpha: 0.72),
                      main.withValues(alpha: 0.55),
                    ]
                  : <Color>[
                      main,
                      main.withValues(alpha: 0.80),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: main.withValues(alpha: _pressed ? 0.18 : 0.32),
                blurRadius: _pressed ? 14 : 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: _kAnimMed,
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale:
                        Tween<double>(begin: 0.88, end: 1.0).animate(animation),
                    child: child,
                  ),
                );
              },
              child: widget.isTracking
                  ? ValueListenableBuilder<int>(
                      key: const ValueKey<String>('tracking'),
                      valueListenable: widget.timerNotifier,
                      builder: (_, int seconds, __) {
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              const Icon(
                                CupertinoIcons.stop_fill,
                                color: Colors.white,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              _SafeText(
                                _formatSeconds(seconds),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: 1.0,
                                  fontFeatures: <ui.FontFeature>[
                                    ui.FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : FittedBox(
                      key: const ValueKey<String>('stopped'),
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            CupertinoIcons.play_fill,
                            color: textColor,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          _SafeText(
                            'START',
                            maxLines: 1,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
