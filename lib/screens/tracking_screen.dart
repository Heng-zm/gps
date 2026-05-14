// ignore_for_file: unused_element, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../models/trip_data.dart';
import '../models/weather_data.dart';
import '../services/services.dart';
import '../utils/smooth_polyline.dart';
import '../config/mapbox_config.dart';
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
const Duration _kActionDebounce = Duration(milliseconds: 850);
const String _kMapboxAccessToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
  defaultValue: MapboxConfig.accessToken,
);

// ── Map / GPS ────────────────────────────────────────────────────────────────
const LatLng _kDefaultCenter = LatLng(11.5564, 104.9282);
const double _kDefaultZoom = 16.0;
const double _kMinHeadingMph = 2.0;
const double _kMapMoveDist = 3.0;
const double _kAutoPauseEnterMph = 1.2;
const double _kAutoPauseResumeMph = 2.8;
const int _kAutoPauseEnterSeconds = 12;
const int _kAutoPauseResumeSeconds = 3;
final Distance _distanceCalc = const Distance();

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

enum _MapboxRuntimeMode {
  auto,
  native,
  webFallback,
}

extension _MapboxRuntimeModeLabel on _MapboxRuntimeMode {
  String get label {
    switch (this) {
      case _MapboxRuntimeMode.auto:
        return 'AUTO';
      case _MapboxRuntimeMode.native:
        return 'NATIVE';
      case _MapboxRuntimeMode.webFallback:
        return 'WEB';
    }
  }

  String get description {
    switch (this) {
      case _MapboxRuntimeMode.auto:
        return 'Native on mobile, fallback on web';
      case _MapboxRuntimeMode.native:
        return 'Force native SDK on Android/iOS';
      case _MapboxRuntimeMode.webFallback:
        return 'Force flutter_map fallback';
    }
  }

  _MapboxRuntimeMode get next {
    switch (this) {
      case _MapboxRuntimeMode.auto:
        return _MapboxRuntimeMode.native;
      case _MapboxRuntimeMode.native:
        return _MapboxRuntimeMode.webFallback;
      case _MapboxRuntimeMode.webFallback:
        return _MapboxRuntimeMode.auto;
    }
  }
}

enum _MapboxStandardPreset {
  day,
  dusk,
  dawn,
  night,
}

extension _MapboxStandardPresetLabel on _MapboxStandardPreset {
  String get label {
    switch (this) {
      case _MapboxStandardPreset.day:
        return 'DAY';
      case _MapboxStandardPreset.dusk:
        return 'DUSK';
      case _MapboxStandardPreset.dawn:
        return 'DAWN';
      case _MapboxStandardPreset.night:
        return 'NIGHT';
    }
  }

  String get mapboxValue {
    switch (this) {
      case _MapboxStandardPreset.day:
        return 'day';
      case _MapboxStandardPreset.dusk:
        return 'dusk';
      case _MapboxStandardPreset.dawn:
        return 'dawn';
      case _MapboxStandardPreset.night:
        return 'night';
    }
  }

  _MapboxStandardPreset get next {
    switch (this) {
      case _MapboxStandardPreset.day:
        return _MapboxStandardPreset.dusk;
      case _MapboxStandardPreset.dusk:
        return _MapboxStandardPreset.dawn;
      case _MapboxStandardPreset.dawn:
        return _MapboxStandardPreset.night;
      case _MapboxStandardPreset.night:
        return _MapboxStandardPreset.day;
    }
  }
}

enum _DirectionsProfile {
  drivingTraffic,
  driving,
  walking,
  cycling,
}

extension _DirectionsProfileLabel on _DirectionsProfile {
  String get label {
    switch (this) {
      case _DirectionsProfile.drivingTraffic:
        return 'DRIVE+TRAFFIC';
      case _DirectionsProfile.driving:
        return 'DRIVING';
      case _DirectionsProfile.walking:
        return 'WALKING';
      case _DirectionsProfile.cycling:
        return 'CYCLING';
    }
  }

  String get apiProfile {
    switch (this) {
      case _DirectionsProfile.drivingTraffic:
        return 'mapbox/driving-traffic';
      case _DirectionsProfile.driving:
        return 'mapbox/driving';
      case _DirectionsProfile.walking:
        return 'mapbox/walking';
      case _DirectionsProfile.cycling:
        return 'mapbox/cycling';
    }
  }

  _DirectionsProfile get next {
    switch (this) {
      case _DirectionsProfile.drivingTraffic:
        return _DirectionsProfile.driving;
      case _DirectionsProfile.driving:
        return _DirectionsProfile.walking;
      case _DirectionsProfile.walking:
        return _DirectionsProfile.cycling;
      case _DirectionsProfile.cycling:
        return _DirectionsProfile.drivingTraffic;
    }
  }
}

class _PlannedRoute {
  const _PlannedRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.profile,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final _DirectionsProfile profile;

  String distanceLabel(SettingsService settings) {
    final double miles = distanceMeters / 1609.344;
    return '${settings.toDisplayDistance(miles).toStringAsFixed(1)} ${settings.distanceUnit}';
  }

  String durationLabel() {
    final int total = durationSeconds.round().clamp(0, 1 << 31);
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    return '${minutes}m';
  }
}

class _MapboxPlaceResult {
  const _MapboxPlaceResult({
    required this.name,
    required this.address,
    required this.position,
  });

  final String name;
  final String address;
  final LatLng position;
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
  final ValueNotifier<bool> _actionBusyN = ValueNotifier<bool>(false);
  final ValueNotifier<_MapboxStandardPreset> _mapPresetN =
      ValueNotifier<_MapboxStandardPreset>(_MapboxStandardPreset.day);
  final ValueNotifier<_MapboxRuntimeMode> _mapRuntimeModeN =
      ValueNotifier<_MapboxRuntimeMode>(_MapboxRuntimeMode.auto);
  final ValueNotifier<_PlannedRoute?> _plannedRouteN =
      ValueNotifier<_PlannedRoute?>(null);
  final ValueNotifier<bool> _directionsLoadingN = ValueNotifier<bool>(false);

  bool _mapReady = false;
  bool _handlingAction = false;
  bool _disposed = false;

  int _polylinePointCount = 0;
  int _pendingSignal = 0;
  DateTime? _lastWeatherFetch;
  DateTime? _lastActionAt;
  DateTime? _lastMapMoveAt;
  LatLng? _lastMapPos;
  int _weatherRequestToken = 0;
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
    _actionBusyN.dispose();
    _mapPresetN.dispose();
    _mapRuntimeModeN.dispose();
    _plannedRouteN.dispose();
    _directionsLoadingN.dispose();

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

    final double bearing = _distanceCalc.bearing(previous, current);
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

    final int nextSignal = ((40.0 - accuracy) / 35.0 * 4.0).round().clamp(0, 4);

    if (nextSignal == _pendingSignal && _signalDebounce?.isActive == true) {
      return;
    }

    _pendingSignal = nextSignal;
    _signalDebounce?.cancel();
    _signalDebounce = Timer(_kSignalDebounce, () {
      if (!mounted || _disposed) return;
      _setN(_signalN, _pendingSignal);
    });
  }

  void _updateMapCamera(TripPoint point) {
    if (!_mapReady || !_usesFlutterMapFallback || !_isValidLL(point.position)) {
      return;
    }

    final _MapFollowMode mode = _followModeN.value;
    if (mode == _MapFollowMode.freeView) return;

    final DateTime now = DateTime.now();
    final DateTime? lastMove = _lastMapMoveAt;

    if (lastMove != null && now.difference(lastMove) < _kMapThrottle) {
      return;
    }

    final LatLng? previous = _lastMapPos;
    if (previous != null && _isValidLL(previous)) {
      final double metres = _distanceCalc.as(
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

    if (!_mapReady || !_usesFlutterMapFallback) return;

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
      _weatherRequestToken++;
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

    final int requestToken = ++_weatherRequestToken;
    _setN(_wxLoadingN, true);

    try {
      final Position? position = await _gps.getCurrentLocation();
      if (!mounted || _disposed || requestToken != _weatherRequestToken) {
        return;
      }

      if (position == null ||
          !position.latitude.isFinite ||
          !position.longitude.isFinite) {
        // Keep last good weather instead of flashing empty UI.
        return;
      }

      final WeatherData? data = await _weather.fetchWeather(
        position.latitude,
        position.longitude,
      );

      if (!mounted || _disposed || requestToken != _weatherRequestToken) {
        return;
      }

      if (data != null) {
        _lastWeatherFetch = DateTime.now();
        _setN(_weatherN, data);
      } else {
        debugPrint('Weather fetch returned no data; keeping previous weather.');
      }
    } catch (error, stackTrace) {
      debugPrint('Weather fetch error: $error\n$stackTrace');
    } finally {
      if (mounted && !_disposed && requestToken == _weatherRequestToken) {
        _setN(_wxLoadingN, false);
      }
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _handleAction() async {
    if (_handlingAction) return;

    final DateTime now = DateTime.now();
    final DateTime? lastAction = _lastActionAt;
    if (lastAction != null && now.difference(lastAction) < _kActionDebounce) {
      HapticFeedback.selectionClick();
      return;
    }

    _lastActionAt = now;
    _handlingAction = true;
    _setN(_actionBusyN, true);

    try {
      if (_trackingN.value) {
        await _stopTracking();
      } else {
        await _startTracking();
      }
    } catch (error, stackTrace) {
      debugPrint('Tracking action failed: $error\n$stackTrace');
    } finally {
      _handlingAction = false;
      if (mounted && !_disposed) {
        _setN(_actionBusyN, false);
      }
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
    _setN(_posN, null);

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
      _setN(_trackingN, false);
      _setN(_speedN, 0.0);
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
          points: List<TripPoint>.unmodifiable(_gps.currentPoints),
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

  void _openMapboxControls() {
    HapticFeedback.lightImpact();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MapboxControlsSheet(
        posN: _posN,
        plannedRouteN: _plannedRouteN,
        presetN: _mapPresetN,
        runtimeModeN: _mapRuntimeModeN,
        directionsLoadingN: _directionsLoadingN,
        settings: _settings,
        onPlanRoute: _planDirectionsRoute,
        onClearRoute: () {
          _setN(_plannedRouteN, null);
          Navigator.of(context).maybePop();
        },
      ),
    );
  }

  Future<LatLng?> _resolveRouteStart() async {
    final LatLng? livePosition = _posN.value;
    if (livePosition != null && _isValidLL(livePosition)) {
      return livePosition;
    }

    final List<TripPoint> points = _gps.currentPoints;
    if (points.isNotEmpty && _isValidLL(points.last.position)) {
      return points.last.position;
    }

    try {
      final Position? current = await _gps.getCurrentLocation();
      if (!mounted || _disposed || current == null) return null;

      final LatLng resolved = LatLng(current.latitude, current.longitude);
      if (_isValidLL(resolved)) {
        _setN(_posN, resolved);
        return resolved;
      }
    } catch (error, stackTrace) {
      debugPrint('Route start resolve error: $error\n$stackTrace');
    }

    return null;
  }

  Future<void> _planDirectionsRoute({
    required double destinationLat,
    required double destinationLng,
    required _DirectionsProfile profile,
  }) async {
    final LatLng? start = await _resolveRouteStart();
    if (start == null || !_isValidLL(start)) {
      _showSnack('GPS position is not ready. Enable location and try again.');
      return;
    }

    final LatLng destination = LatLng(destinationLat, destinationLng);
    if (!_isValidLL(destination)) {
      _showSnack('Destination coordinate is invalid.');
      return;
    }

    if (_kMapboxAccessToken.isEmpty) {
      _showSnack('Mapbox token is missing.');
      return;
    }

    _setN(_directionsLoadingN, true);

    try {
      final Uri uri = Uri.parse(
        'https://api.mapbox.com/directions/v5/${profile.apiProfile}/'
        '${start.longitude},${start.latitude};'
        '${destination.longitude},${destination.latitude}',
      ).replace(
        queryParameters: <String, String>{
          'alternatives': 'false',
          'geometries': 'geojson',
          'overview': 'full',
          'steps': 'false',
          'access_token': _kMapboxAccessToken,
        },
      );

      final http.Response response = await http.get(uri).timeout(
            const Duration(seconds: 15),
          );

      if (!mounted || _disposed) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Mapbox Directions error ${response.statusCode}: '
            '${response.body}');
        _showSnack(
            'Route planning failed (${response.statusCode}). Check Mapbox token.');
        return;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _showSnack('Route planning response was invalid.');
        return;
      }

      final List<dynamic> routes = decoded['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty || routes.first is! Map<String, dynamic>) {
        _showSnack('No route found.');
        return;
      }

      final Map<String, dynamic> route = routes.first as Map<String, dynamic>;
      final Map<String, dynamic>? geometry =
          route['geometry'] as Map<String, dynamic>?;
      final List<dynamic> coordinates =
          geometry?['coordinates'] as List<dynamic>? ?? [];

      final List<LatLng> points = <LatLng>[];
      for (final dynamic coordinate in coordinates) {
        if (coordinate is! List || coordinate.length < 2) continue;
        final double? lng = (coordinate[0] as num?)?.toDouble();
        final double? lat = (coordinate[1] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final LatLng point = LatLng(lat, lng);
        if (_isValidLL(point)) points.add(point);
      }

      if (points.length < 2) {
        _showSnack('Route has no usable geometry.');
        return;
      }

      _setN(
        _plannedRouteN,
        _PlannedRoute(
          points: List<LatLng>.unmodifiable(points),
          distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0.0,
          durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0.0,
          profile: profile,
        ),
      );

      if (mounted && !_disposed) {
        Navigator.of(context).maybePop();
        _showSnack('Route planned successfully.');
      }
    } on TimeoutException {
      if (mounted && !_disposed) _showSnack('Route request timed out.');
    } catch (error, stackTrace) {
      debugPrint('Directions planning error: $error\n$stackTrace');
      if (mounted && !_disposed) _showSnack('Route planning failed.');
    } finally {
      if (mounted && !_disposed) _setN(_directionsLoadingN, false);
    }
  }

  void _showSnack(String message) {
    if (!mounted || _disposed) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _markMapReady() {
    if (_mapReady) return;
    _mapReady = true;

    final LatLng? position = _posN.value;
    if (position == null || !_isValidLL(position)) return;

    if (!_usesFlutterMapFallback) return;

    try {
      _mapController.move(position, _kDefaultZoom);
    } catch (_) {}
  }

  bool get _usesFlutterMapFallback {
    return kIsWeb || _mapRuntimeModeN.value == _MapboxRuntimeMode.webFallback;
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
                headingN: _travelHdgN,
                followModeN: _followModeN,
                mapController: _mapController,
                gps: _gps,
                settings: _settings,
                presetN: _mapPresetN,
                runtimeModeN: _mapRuntimeModeN,
                plannedRouteN: _plannedRouteN,
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
            _MapFirstFloatingModeBadge(followModeN: _followModeN),
            _MapFirstBottomDock(
              tickN: _tickN,
              trackingN: _trackingN,
              elapsedN: _elapsedN,
              maxSpeedN: _maxSpeedN,
              autoPausedN: _autoPausedN,
              autoPauseStoppedN: _autoPauseStoppedN,
              actionBusyN: _actionBusyN,
              followModeN: _followModeN,
              settings: _settings,
              gps: _gps,
              onAction: _handleAction,
              onMapTap: _openMap,
              onAiTap: _openAiAssistant,
              onWeatherTap: _openFullWeather,
              onMapboxTap: _openMapboxControls,
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
    required this.headingN,
    required this.followModeN,
    required this.mapController,
    required this.gps,
    required this.settings,
    required this.presetN,
    required this.runtimeModeN,
    required this.plannedRouteN,
    required this.polylineCount,
    required this.onMapReady,
  });

  final ValueNotifier<LatLng?> posN;
  final ValueNotifier<double> headingN;
  final ValueNotifier<_MapFollowMode> followModeN;

  /// Kept only for constructor compatibility with existing TrackingScreen.
  /// Native Mapbox uses its own [mb.MapboxMap] controller.
  final fm.MapController mapController;

  final GpsService gps;
  final SettingsService settings;
  final ValueNotifier<_MapboxStandardPreset> presetN;
  final ValueNotifier<_MapboxRuntimeMode> runtimeModeN;
  final ValueNotifier<_PlannedRoute?> plannedRouteN;
  final int Function() polylineCount;
  final VoidCallback onMapReady;

  @override
  State<_FullScreenLiveMap> createState() => _FullScreenLiveMapState();
}

class _FullScreenLiveMapState extends State<_FullScreenLiveMap> {
  mb.MapboxMap? _mapboxMap;
  mb.PolylineAnnotationManager? _routeOuterManager;
  mb.PolylineAnnotationManager? _routeCoreManager;
  mb.PolylineAnnotationManager? _plannedOuterManager;
  mb.PolylineAnnotationManager? _plannedCoreManager;

  bool _styleLoaded = false;
  bool _locationReady = false;
  int _lastRouteCount = -1;
  int _lastRouteSignature = 0;
  int _lastPlannedRouteSignature = 0;
  DateTime? _lastCameraAt;
  DateTime? _lastRouteAt;

  @override
  void initState() {
    super.initState();
    widget.posN.addListener(_onLiveMapInputChanged);
    widget.headingN.addListener(_onLiveMapInputChanged);
    widget.followModeN.addListener(_onFollowModeChanged);
    widget.presetN.addListener(_onMapboxPresetChanged);
    widget.runtimeModeN.addListener(_onMapRuntimeChanged);
    widget.plannedRouteN.addListener(_onPlannedRouteChanged);
  }

  @override
  void didUpdateWidget(covariant _FullScreenLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.mapStyle != widget.settings.mapStyle) {
      unawaited(_loadMapboxStyle());
    }
  }

  @override
  void dispose() {
    widget.posN.removeListener(_onLiveMapInputChanged);
    widget.headingN.removeListener(_onLiveMapInputChanged);
    widget.followModeN.removeListener(_onFollowModeChanged);
    widget.presetN.removeListener(_onMapboxPresetChanged);
    widget.runtimeModeN.removeListener(_onMapRuntimeChanged);
    widget.plannedRouteN.removeListener(_onPlannedRouteChanged);
    super.dispose();
  }

  void _onMapCreated(mb.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    unawaited(_configureMapboxMap());
  }

  Future<void> _configureMapboxMap() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null) return;

    try {
      await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
      await map.compass.updateSettings(mb.CompassSettings(enabled: false));
      await map.attribution.updateSettings(
        mb.AttributionSettings(enabled: true),
      );
      await map.logo.updateSettings(mb.LogoSettings(enabled: true));
    } catch (error) {
      debugPrint('Mapbox ornament settings error: $error');
    }

    await _configureNativeLocationPuck();
    await _loadMapboxStyle();
    widget.onMapReady();
  }

  Future<void> _configureNativeLocationPuck() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null || _locationReady) return;

    try {
      await map.location.updateSettings(
        mb.LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          puckBearing: mb.PuckBearing.HEADING,
          pulsingEnabled: true,
          pulsingColor: const Color(0xFF1A73FF).toARGB32(),
          pulsingMaxRadius: 48.0,
          showAccuracyRing: true,
          accuracyRingColor: const Color(0x331A73FF).toARGB32(),
          accuracyRingBorderColor: const Color(0x881A73FF).toARGB32(),
        ),
      );
      _locationReady = true;
    } catch (error) {
      debugPrint('Mapbox location puck error: $error');
    }
  }

  Future<void> _loadMapboxStyle() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null) return;

    _styleLoaded = false;
    _lastRouteCount = -1;

    try {
      await map.loadStyleURI(_mapboxStyleUri(widget.settings.mapStyle));
      _styleLoaded = true;
      _routeOuterManager = null;
      _routeCoreManager = null;
      _plannedOuterManager = null;
      _plannedCoreManager = null;
      _lastRouteSignature = 0;
      _lastPlannedRouteSignature = 0;

      await _configureStandardStyle();
      await _configureNativeLocationPuck();
      await _rebuildPlannedRouteAnnotations(force: true);
      await _rebuildRouteAnnotations(force: true);
      await _moveCameraToLatest(force: true);
    } catch (error, stackTrace) {
      debugPrint('Mapbox style load error: $error\n$stackTrace');
    }
  }

  Future<void> _configureStandardStyle() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null) return;

    try {
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'lightPreset',
        widget.presetN.value.mapboxValue,
      );
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'showPointOfInterestLabels',
        false,
      );
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'showTransitLabels',
        false,
      );
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'show3dObjects',
        true,
      );
    } catch (error) {
      debugPrint('Mapbox Standard config skipped: $error');
    }
  }

  void _onMapboxPresetChanged() {
    unawaited(_configureStandardStyle());
  }

  void _onMapRuntimeChanged() {
    if (mounted) setState(() {});
  }

  void _onPlannedRouteChanged() {
    unawaited(_rebuildPlannedRouteAnnotations(force: true));
  }

  void _onFollowModeChanged() {
    if (widget.followModeN.value != _MapFollowMode.freeView) {
      unawaited(_moveCameraToLatest(force: true));
    }
  }

  void _onLiveMapInputChanged() {
    unawaited(_moveCameraToLatest());
    unawaited(_rebuildRouteAnnotations());
  }

  Future<void> _moveCameraToLatest({bool force = false}) async {
    final mb.MapboxMap? map = _mapboxMap;
    final LatLng? position = widget.posN.value;
    if (map == null || position == null || !_isValid(position)) return;

    final _MapFollowMode mode = widget.followModeN.value;
    if (mode == _MapFollowMode.freeView && !force) return;

    final DateTime now = DateTime.now();
    final DateTime? last = _lastCameraAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 520)) {
      return;
    }
    _lastCameraAt = now;

    final double bearing =
        mode == _MapFollowMode.headingUp ? -_normDeg(widget.headingN.value) : 0;
    final double pitch = mode == _MapFollowMode.headingUp ? 50.0 : 0.0;
    final double zoom = mode == _MapFollowMode.headingUp ? 17.2 : 16.3;

    try {
      await map.easeTo(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(position.longitude, position.latitude),
          ),
          zoom: zoom,
          bearing: bearing,
          pitch: pitch,
        ),
        mb.MapAnimationOptions(duration: force ? 650 : 420, startDelay: 0),
      );
    } catch (error) {
      debugPrint('Mapbox camera error: $error');
    }
  }

  Future<void> _rebuildRouteAnnotations({bool force = false}) async {
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null || !_styleLoaded) return;

    final List<TripPoint> currentPoints = widget.gps.currentPoints;
    final int count = currentPoints.length;
    final int signature = _routeSignature(currentPoints);

    if (!force &&
        count == _lastRouteCount &&
        signature == _lastRouteSignature) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? last = _lastRouteAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 900)) {
      return;
    }

    _lastRouteAt = now;
    _lastRouteCount = count;
    _lastRouteSignature = signature;

    final List<LatLng> safePoints = currentPoints
        .map((TripPoint point) => point.position)
        .where(_isValid)
        .toList(growable: false);

    final List<LatLng> renderPoints = safePoints.length > 900
        ? simplifyPolyline(safePoints, epsilon: 0.00004)
        : safePoints;

    final List<mb.Position> coordinates = renderPoints
        .map((LatLng point) => mb.Position(point.longitude, point.latitude))
        .toList(growable: false);

    try {
      _routeOuterManager ??=
          await map.annotations.createPolylineAnnotationManager();
      _routeCoreManager ??=
          await map.annotations.createPolylineAnnotationManager();

      await _routeOuterManager?.deleteAll();
      await _routeCoreManager?.deleteAll();

      if (coordinates.length < 2) return;

      final mb.LineString line = mb.LineString(coordinates: coordinates);

      await _routeOuterManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: Colors.white.toARGB32(),
          lineWidth: 12.5,
          lineOpacity: 0.92,
          lineBorderColor: Colors.black.toARGB32(),
          lineBorderWidth: 2.5,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );

      await _routeCoreManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: const Color(0xFF2F22FF).toARGB32(),
          lineWidth: 6.5,
          lineOpacity: 0.98,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Mapbox route annotation error: $error\n$stackTrace');
    }
  }

  Future<void> _rebuildPlannedRouteAnnotations({bool force = false}) async {
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null || !_styleLoaded) return;

    final _PlannedRoute? route = widget.plannedRouteN.value;
    final int signature = _plannedRouteSignature(route);

    if (!force && signature == _lastPlannedRouteSignature) {
      return;
    }

    _lastPlannedRouteSignature = signature;

    try {
      _plannedOuterManager ??=
          await map.annotations.createPolylineAnnotationManager();
      _plannedCoreManager ??=
          await map.annotations.createPolylineAnnotationManager();

      await _plannedOuterManager?.deleteAll();
      await _plannedCoreManager?.deleteAll();

      if (route == null || route.points.length < 2) return;

      final List<mb.Position> coordinates = route.points
          .where(_isValid)
          .map((LatLng point) => mb.Position(point.longitude, point.latitude))
          .toList(growable: false);

      if (coordinates.length < 2) return;

      final mb.LineString line = mb.LineString(coordinates: coordinates);

      await _plannedOuterManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: Colors.white.toARGB32(),
          lineWidth: 11.0,
          lineOpacity: 0.82,
          lineBorderColor: Colors.black.toARGB32(),
          lineBorderWidth: 2.0,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );

      await _plannedCoreManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: _kBlue.toARGB32(),
          lineWidth: 5.4,
          lineOpacity: 0.94,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Mapbox planned route annotation error: $error\n$stackTrace');
    }
  }

  static int _routeSignature(List<TripPoint> points) {
    if (points.isEmpty) return 0;

    final TripPoint last = points.last;
    final int lat = (last.position.latitude * 100000).round();
    final int lng = (last.position.longitude * 100000).round();
    final int speed = (last.speedMph * 10).round();

    return Object.hash(points.length, lat, lng, speed);
  }

  static int _plannedRouteSignature(_PlannedRoute? route) {
    if (route == null || route.points.isEmpty) return 0;

    final LatLng first = route.points.first;
    final LatLng last = route.points.last;

    return Object.hash(
      route.points.length,
      (first.latitude * 100000).round(),
      (first.longitude * 100000).round(),
      (last.latitude * 100000).round(),
      (last.longitude * 100000).round(),
      route.profile,
    );
  }

  static bool _isValid(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90.0 &&
        point.latitude <= 90.0 &&
        point.longitude >= -180.0 &&
        point.longitude <= 180.0;
  }

  static double _normDeg(double degrees) {
    final double normalized = degrees % 360.0;
    return normalized < 0.0 ? normalized + 360.0 : normalized;
  }

  static String _mapboxStyleUri(AppMapStyle style) {
    final String name = style.name.toLowerCase();
    if (name.contains('satellite')) return mb.MapboxStyles.STANDARD_SATELLITE;
    return mb.MapboxStyles.STANDARD;
  }

  Widget _buildWebFallbackMap(BuildContext context) {
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
          onMapEvent: (fm.MapEvent event) {
            if (event is fm.MapEventMoveStart &&
                event.source != fm.MapEventSource.mapController &&
                widget.followModeN.value != _MapFollowMode.freeView) {
              widget.followModeN.value = _MapFollowMode.freeView;
            }
          },
        ),
        children: <Widget>[
          fm.TileLayer(
            urlTemplate: _webMapTileUrl(widget.settings.mapStyle),
            userAgentPackageName: 'com.trackpro.ai',
            retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.0,
            maxNativeZoom: 19,
            errorTileCallback: (
              fm.TileImage tile,
              Object error,
              StackTrace? stackTrace,
            ) {
              debugPrint('Tracking web fallback tile error: $error');
            },
          ),
          ValueListenableBuilder<_PlannedRoute?>(
            valueListenable: widget.plannedRouteN,
            builder: (_, _PlannedRoute? route, __) {
              if (route == null || route.points.length < 2) {
                return const SizedBox.shrink();
              }

              return fm.PolylineLayer(
                polylines: <fm.Polyline>[
                  fm.Polyline(
                    points: route.points,
                    color: Colors.white.withValues(alpha: 0.82),
                    strokeWidth: 10.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  fm.Polyline(
                    points: route.points,
                    color: _kBlue.withValues(alpha: 0.92),
                    strokeWidth: 5.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              );
            },
          ),
          ValueListenableBuilder<LatLng?>(
            valueListenable: widget.posN,
            builder: (_, __, ___) {
              final List<LatLng> points = widget.gps.currentPoints
                  .map((TripPoint point) => point.position)
                  .where(_isValid)
                  .toList(growable: false);

              if (points.length < 2) return const SizedBox.shrink();

              final List<LatLng> simplified = points.length > 900
                  ? simplifyPolyline(points, epsilon: 0.00004)
                  : points;
              final List<LatLng> polyline = simplified.length > 2
                  ? smoothPolyline(
                      simplified,
                      tension: 0.5,
                      subdivisions: simplified.length > 500 ? 4 : 8,
                    )
                  : simplified;

              return fm.PolylineLayer(
                polylines: <fm.Polyline>[
                  fm.Polyline(
                    points: polyline,
                    color: Colors.white.withValues(alpha: 0.96),
                    strokeWidth: 12.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  fm.Polyline(
                    points: polyline,
                    color: const Color(0xFF2F22FF).withValues(alpha: 0.96),
                    strokeWidth: 6.5,
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
                    width: 74,
                    height: 74,
                    alignment: Alignment.center,
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.headingN,
                      builder: (_, double heading, __) {
                        return ValueListenableBuilder<_MapFollowMode>(
                          valueListenable: widget.followModeN,
                          builder: (_, _MapFollowMode mode, __) {
                            final double markerHeading =
                                mode == _MapFollowMode.headingUp
                                    ? 0.0
                                    : heading;
                            return _LocationPuckMarker(
                              heading: markerHeading,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _webMapTileUrl(AppMapStyle style) {
    final String name = style.name.toLowerCase();
    final String token = _kMapboxAccessToken;

    if (token.isEmpty) {
      if (name.contains('light')) {
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      }

      if (name.contains('dark')) {
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      }

      return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }

    final String styleId = name.contains('satellite')
        ? 'satellite-streets-v12'
        : name.contains('light')
            ? 'navigation-day-v1'
            : 'navigation-night-v1';

    return 'https://api.mapbox.com/styles/v1/mapbox/$styleId/'
        'tiles/512/{z}/{x}/{y}@2x?access_token=$token';
  }

  @override
  Widget build(BuildContext context) {
    final _MapboxRuntimeMode runtimeMode = widget.runtimeModeN.value;
    final bool useFallback = kIsWeb ||
        runtimeMode == _MapboxRuntimeMode.webFallback ||
        _kMapboxAccessToken.isEmpty;

    if (useFallback) {
      return _buildWebFallbackMap(context);
    }

    final LatLng center = widget.posN.value ?? _kDefaultCenter;
    final String styleUri = _mapboxStyleUri(widget.settings.mapStyle);

    return RepaintBoundary(
      child: mb.MapWidget(
        key: ValueKey<String>('native-mapbox-$styleUri'),
        styleUri: styleUri,
        viewport: mb.CameraViewportState(
          center: mb.Point(
            coordinates: mb.Position(center.longitude, center.latitude),
          ),
          zoom: _kDefaultZoom,
          pitch: 0.0,
          bearing: 0.0,
        ),
        textureView: true,
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: (_) {
          _styleLoaded = true;
          unawaited(_configureStandardStyle());
          unawaited(_configureNativeLocationPuck());
          unawaited(_rebuildPlannedRouteAnnotations(force: true));
          unawaited(_rebuildRouteAnnotations(force: true));
          unawaited(_moveCameraToLatest(force: true));
        },
        onScrollListener: (_) {
          if (widget.followModeN.value != _MapFollowMode.freeView) {
            widget.followModeN.value = _MapFollowMode.freeView;
          }
        },
      ),
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
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
    final double bottomSafe = MediaQuery.of(context).padding.bottom;

    return Positioned(
      right: 14,
      bottom: bottomSafe + 214,
      child: RepaintBoundary(
        child: ValueListenableBuilder<bool>(
          valueListenable: trackingN,
          builder: (_, bool tracking, __) {
            return ValueListenableBuilder<double>(
              valueListenable: speedN,
              builder: (_, double speed, __) {
                final bool isOver = tracking && speed > settings.speedAlertMph;

                return AnimatedScale(
                  duration: _kAnimMed,
                  curve: Curves.easeOutCubic,
                  scale: isOver ? 1.035 : 1.0,
                  child: AnimatedContainer(
                    duration: _kAnimMed,
                    curve: Curves.easeOutCubic,
                    width: 108,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: isOver ? 0.64 : 0.42,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isOver
                            ? _kRed.withValues(alpha: 0.52)
                            : Colors.white.withValues(alpha: 0.10),
                        width: isOver ? 1.4 : 0.8,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: isOver
                              ? _kRed.withValues(alpha: 0.26)
                              : Colors.black.withValues(alpha: 0.26),
                          blurRadius: isOver ? 24 : 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SpeedometerWidget(
                          speedMph: speed,
                          isOverLimit: isOver,
                          compact: true,
                          showUnit: true,
                          showOverLimitBadge: false,
                        ),
                        const SizedBox(height: 4),
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPausedN,
                          builder: (_, bool autoPaused, __) {
                            return _ReadyTrackingLabel(
                              tracking: tracking,
                              autoPaused: autoPaused,
                              isOverLimit: isOver,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: _SafeText(
          label,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 8.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.65,
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
    required this.actionBusyN,
    required this.followModeN,
    required this.settings,
    required this.gps,
    required this.onAction,
    required this.onMapTap,
    required this.onAiTap,
    required this.onWeatherTap,
    required this.onMapboxTap,
    required this.onFollowModeTap,
  });

  final ValueNotifier<int> tickN;
  final ValueNotifier<bool> trackingN;
  final ValueNotifier<int> elapsedN;
  final ValueNotifier<double> maxSpeedN;
  final ValueNotifier<bool> autoPausedN;
  final ValueNotifier<int> autoPauseStoppedN;
  final ValueNotifier<bool> actionBusyN;
  final ValueNotifier<_MapFollowMode> followModeN;
  final SettingsService settings;
  final GpsService gps;
  final VoidCallback onAction;
  final VoidCallback onMapTap;
  final VoidCallback onAiTap;
  final VoidCallback onWeatherTap;
  final VoidCallback onMapboxTap;
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
              10,
              14,
              bottomPad > 0 ? bottomPad + 10 : 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 38,
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
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
                          return ValueListenableBuilder<bool>(
                            valueListenable: actionBusyN,
                            builder: (_, bool busy, __) {
                              return _PrimaryActionButton(
                                isTracking: tracking,
                                isBusy: busy,
                                onTap: onAction,
                                timerNotifier: elapsedN,
                              );
                            },
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
                        icon: CupertinoIcons.location_north_line_fill,
                        label: 'ROUTE',
                        onTap: onMapboxTap,
                        color: _kBlue,
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
        height: compact ? 36 : 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.09),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.045),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
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
  // Legacy helper kept for compatibility, but satellite tiles should remain
  // unfiltered so the map is no longer overly black/high-contrast.
  return tile;
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

class _MapboxControlsSheet extends StatefulWidget {
  const _MapboxControlsSheet({
    required this.posN,
    required this.plannedRouteN,
    required this.presetN,
    required this.runtimeModeN,
    required this.directionsLoadingN,
    required this.settings,
    required this.onPlanRoute,
    required this.onClearRoute,
  });

  final ValueNotifier<LatLng?> posN;
  final ValueNotifier<_PlannedRoute?> plannedRouteN;
  final ValueNotifier<_MapboxStandardPreset> presetN;
  final ValueNotifier<_MapboxRuntimeMode> runtimeModeN;
  final ValueNotifier<bool> directionsLoadingN;
  final SettingsService settings;
  final Future<void> Function({
    required double destinationLat,
    required double destinationLng,
    required _DirectionsProfile profile,
  }) onPlanRoute;
  final VoidCallback onClearRoute;

  @override
  State<_MapboxControlsSheet> createState() => _MapboxControlsSheetState();
}

class _MapboxControlsSheetState extends State<_MapboxControlsSheet> {
  late final TextEditingController _searchCtrl;
  late final FocusNode _searchFocus;
  _DirectionsProfile _profile = _DirectionsProfile.drivingTraffic;
  _MapboxPlaceResult? _selectedPlace;
  List<_MapboxPlaceResult> _results = const <_MapboxPlaceResult>[];
  bool _searching = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode();
  }

  @override
  void dispose() {
    _searchToken++;
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _searchPlaces() async {
    final String query = _searchCtrl.text.trim();

    if (query.length < 2) {
      _showSheetSnack('Type a place name first.');
      return;
    }

    if (_kMapboxAccessToken.isEmpty) {
      _showSheetSnack('Mapbox token is missing.');
      return;
    }

    _searchFocus.unfocus();

    final int token = ++_searchToken;
    setState(() {
      _searching = true;
      _results = const <_MapboxPlaceResult>[];
      _selectedPlace = null;
    });

    try {
      LatLng? current = widget.posN.value;
      if (current == null ||
          !current.latitude.isFinite ||
          !current.longitude.isFinite) {
        try {
          final Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(const Duration(seconds: 8));
          current = LatLng(position.latitude, position.longitude);
        } catch (_) {
          current = null;
        }
      }

      final Map<String, String> params = <String, String>{
        'access_token': _kMapboxAccessToken,
        'limit': '6',
        'types':
            'country,region,postcode,district,place,locality,neighborhood,address,poi',
        'language': 'en',
        'autocomplete': 'true',
        'fuzzyMatch': 'true',
      };

      if (current != null &&
          current.latitude.isFinite &&
          current.longitude.isFinite) {
        params['proximity'] = '${current.longitude},${current.latitude}';
      }

      final Uri uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${Uri.encodeComponent(query)}.json',
      ).replace(queryParameters: params);

      final http.Response response = await http.get(uri).timeout(
            const Duration(seconds: 12),
          );

      if (!mounted || token != _searchToken) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Mapbox geocoding error ${response.statusCode}: '
            '${response.body}');
        _showSheetSnack(
          'Location search failed (${response.statusCode}). Check Mapbox token.',
        );
        return;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _showSheetSnack('Location search response was invalid.');
        return;
      }

      final List<dynamic> features =
          decoded['features'] as List<dynamic>? ?? <dynamic>[];

      final List<_MapboxPlaceResult> nextResults = <_MapboxPlaceResult>[];

      for (final dynamic item in features) {
        if (item is! Map<String, dynamic>) continue;

        final String name =
            (item['text'] ?? item['place_name'] ?? '').toString().trim();
        final String address = (item['place_name'] ?? '').toString().trim();
        final List<dynamic> center = item['center'] as List<dynamic>? ?? [];

        if (name.isEmpty || center.length < 2) continue;

        final double? lng = (center[0] as num?)?.toDouble();
        final double? lat = (center[1] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final LatLng position = LatLng(lat, lng);
        if (!_TrackingScreenState._isValidLL(position)) continue;

        nextResults.add(
          _MapboxPlaceResult(
            name: name,
            address: address,
            position: position,
          ),
        );
      }

      setState(() {
        _results = List<_MapboxPlaceResult>.unmodifiable(nextResults);
        if (nextResults.length == 1) {
          _selectedPlace = nextResults.first;
        }
      });

      if (nextResults.isEmpty) {
        _showSheetSnack('No matching location found.');
      }
    } on TimeoutException {
      if (mounted) _showSheetSnack('Location search timed out.');
    } catch (error, stackTrace) {
      debugPrint('Mapbox geocoding search error: $error\n$stackTrace');
      if (mounted) _showSheetSnack('Location search failed.');
    } finally {
      if (mounted && token == _searchToken) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _submit() async {
    final _MapboxPlaceResult? place = _selectedPlace;

    if (place == null) {
      if (_results.isNotEmpty) {
        _showSheetSnack('Tap a search result first.');
      } else {
        _showSheetSnack('Search a location, then tap one result first.');
      }
      return;
    }

    await widget.onPlanRoute(
      destinationLat: place.position.latitude,
      destinationLng: place.position.longitude,
      profile: _profile,
    );
  }

  void _showSheetSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _quickSearch(String query) {
    _searchCtrl.text = query;
    unawaited(_searchPlaces());
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return AnimatedPadding(
      duration: _kAnimMed,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _kSurface.withValues(alpha: 0.96),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 46,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            _RoutePlannerHeader(
                              selectedPlace: _selectedPlace,
                              onClear: _selectedPlace == null
                                  ? null
                                  : () => setState(() {
                                        _selectedPlace = null;
                                        _searchCtrl.clear();
                                        _results = const <_MapboxPlaceResult>[];
                                      }),
                            ),
                            const SizedBox(height: 14),
                            _RoutePlannerSearchCard(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              searching: _searching,
                              selectedPlace: _selectedPlace,
                              results: _results,
                              onSearch: () => unawaited(_searchPlaces()),
                              onSelect: (place) {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedPlace = place);
                              },
                              onQuickSearch: _quickSearch,
                            ),
                            const SizedBox(height: 12),
                            _RoutePlannerModeCard(
                              selectedProfile: _profile,
                              onChanged: (profile) {
                                HapticFeedback.selectionClick();
                                setState(() => _profile = profile);
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _RoutePlannerSelectCard(
                                    title: 'Map style',
                                    subtitle: 'Look of the map',
                                    icon: CupertinoIcons.map_fill,
                                    color: _kAmberSoft,
                                    child: ValueListenableBuilder<
                                        _MapboxStandardPreset>(
                                      valueListenable: widget.presetN,
                                      builder: (_, preset, __) {
                                        return _RoutePlannerSelectButton(
                                          label: preset.label,
                                          icon: _presetIcon(preset),
                                          color: _kAmberSoft,
                                          onTap: () {
                                            widget.presetN.value =
                                                widget.presetN.value.next;
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _RoutePlannerSelectCard(
                                    title: 'Runtime',
                                    subtitle: 'Best map engine',
                                    icon: CupertinoIcons.speedometer,
                                    color: _kGreen,
                                    child: ValueListenableBuilder<
                                        _MapboxRuntimeMode>(
                                      valueListenable: widget.runtimeModeN,
                                      builder: (_, mode, __) {
                                        return _RoutePlannerSelectButton(
                                          label: mode.label,
                                          icon:
                                              CupertinoIcons.arrow_2_circlepath,
                                          color: _kGreen,
                                          onTap: () {
                                            widget.runtimeModeN.value =
                                                widget.runtimeModeN.value.next;
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<_PlannedRoute?>(
                              valueListenable: widget.plannedRouteN,
                              builder: (_, route, __) {
                                return _RoutePlannerSummaryCard(
                                  route: route,
                                  selectedPlace: _selectedPlace,
                                  profile: _profile,
                                  settings: widget.settings,
                                  onClearRoute: route == null
                                      ? null
                                      : widget.onClearRoute,
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            ValueListenableBuilder<bool>(
                              valueListenable: widget.directionsLoadingN,
                              builder: (_, bool loading, __) {
                                final bool canPlan =
                                    _selectedPlace != null && !loading;

                                return _RoutePlannerPlanButton(
                                  loading: loading,
                                  enabled: canPlan,
                                  onTap: canPlan
                                      ? _submit
                                      : () {
                                          _showSheetSnack(
                                            'Search and select a destination first.',
                                          );
                                        },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _presetIcon(_MapboxStandardPreset preset) {
    switch (preset) {
      case _MapboxStandardPreset.day:
        return CupertinoIcons.sun_max_fill;
      case _MapboxStandardPreset.dusk:
        return CupertinoIcons.sunset_fill;
      case _MapboxStandardPreset.dawn:
        return CupertinoIcons.sunrise_fill;
      case _MapboxStandardPreset.night:
        return CupertinoIcons.moon_stars_fill;
    }
  }
}

class _RoutePlannerHeader extends StatelessWidget {
  const _RoutePlannerHeader({
    required this.selectedPlace,
    required this.onClear,
  });

  final _MapboxPlaceResult? selectedPlace;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _kBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBlue.withValues(alpha: 0.22)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _kBlue.withValues(alpha: 0.18),
                blurRadius: 24,
              ),
            ],
          ),
          child: const Icon(
            Icons.navigation_rounded,
            color: _kBlue,
            size: 25,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _SafeText(
                'ROUTE PLANNER',
                maxLines: 1,
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              _SafeText(
                selectedPlace == null
                    ? 'Search and plan your next route'
                    : 'Destination selected',
                maxLines: 1,
                style: const TextStyle(
                  color: _kTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (onClear != null)
          _RoutePlannerTinyButton(
            icon: CupertinoIcons.xmark,
            color: _kTextMuted,
            onTap: onClear!,
          ),
      ],
    );
  }
}

class _RoutePlannerSearchCard extends StatelessWidget {
  const _RoutePlannerSearchCard({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.selectedPlace,
    required this.results,
    required this.onSearch,
    required this.onSelect,
    required this.onQuickSearch,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final _MapboxPlaceResult? selectedPlace;
  final List<_MapboxPlaceResult> results;
  final VoidCallback onSearch;
  final ValueChanged<_MapboxPlaceResult> onSelect;
  final ValueChanged<String> onQuickSearch;

  @override
  Widget build(BuildContext context) {
    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBlue.withValues(alpha: 0.18),
                ),
                child: const Icon(
                  CupertinoIcons.location_fill,
                  color: _kBlue,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              const _SafeText(
                'From:',
                maxLines: 1,
                style: TextStyle(
                  color: _kTextMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: _SafeText(
                  'My Location',
                  maxLines: 1,
                  style: TextStyle(
                    color: _kBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (selectedPlace != null)
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: _kGreen,
                  size: 16,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 54,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.36),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 14),
                const Icon(CupertinoIcons.search, color: _kTextMuted, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: CupertinoTextField.borderless(
                    controller: controller,
                    focusNode: focusNode,
                    placeholder: 'Search destination...',
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => onSearch(),
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    placeholderStyle: const TextStyle(
                      color: _kTextMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 96,
                  height: 44,
                  child: _RoutePlannerGradientButton(
                    label: searching ? '...' : 'SEARCH',
                    icon: CupertinoIcons.search,
                    color: _kBlue,
                    onTap: searching ? () {} : onSearch,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
          if (searching) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                color: _kBlue,
              ),
            ),
          ],
          if (results.isEmpty && selectedPlace == null) ...<Widget>[
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: _SafeText(
                'Recent & popular',
                maxLines: 1,
                style: TextStyle(
                  color: _kTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _RoutePlannerShortcutChip(
                    icon: CupertinoIcons.house_fill,
                    title: 'Home',
                    subtitle: 'Search home',
                    onTap: () => onQuickSearch('home'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RoutePlannerShortcutChip(
                    icon: CupertinoIcons.briefcase_fill,
                    title: 'Work',
                    subtitle: 'Search work',
                    onTap: () => onQuickSearch('work'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _RoutePlannerShortcutChip(
                    icon: CupertinoIcons.building_2_fill,
                    title: 'Market',
                    subtitle: 'Popular',
                    onTap: () => onQuickSearch('Central Market Phnom Penh'),
                  ),
                ),
              ],
            ),
          ],
          if (results.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            ...results.map(
              (place) => _RoutePlannerPlaceTile(
                place: place,
                selected: identical(place, selectedPlace),
                onTap: () => onSelect(place),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoutePlannerShortcutChip extends StatelessWidget {
  const _RoutePlannerShortcutChip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: _kBlue, size: 17),
            const SizedBox(height: 6),
            _SafeText(
              title,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            _SafeText(
              subtitle,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerModeCard extends StatelessWidget {
  const _RoutePlannerModeCard({
    required this.selectedProfile,
    required this.onChanged,
  });

  final _DirectionsProfile selectedProfile;
  final ValueChanged<_DirectionsProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SafeText(
            'Travel mode',
            maxLines: 1,
            style: TextStyle(
              color: _kTextPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 11),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _DirectionsProfile.values.map((profile) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _RoutePlannerModeChip(
                    profile: profile,
                    selected: profile == selectedProfile,
                    onTap: () => onChanged(profile),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePlannerModeChip extends StatelessWidget {
  const _RoutePlannerModeChip({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final _DirectionsProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? _kBlue : _kTextMuted;

    return _PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _kAnimFast,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? _kBlue.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? _kBlue.withValues(alpha: 0.46)
                : Colors.white.withValues(alpha: 0.09),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_profileIcon(profile), color: color, size: 16),
            const SizedBox(width: 7),
            _SafeText(
              _profileShortLabel(profile),
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _profileIcon(_DirectionsProfile profile) {
    switch (profile) {
      case _DirectionsProfile.drivingTraffic:
      case _DirectionsProfile.driving:
        return CupertinoIcons.car_detailed;
      case _DirectionsProfile.walking:
        return CupertinoIcons.person_fill;
      case _DirectionsProfile.cycling:
        return Icons.directions_bike_rounded;
    }
  }

  static String _profileShortLabel(_DirectionsProfile profile) {
    switch (profile) {
      case _DirectionsProfile.drivingTraffic:
        return 'Drive+Traffic';
      case _DirectionsProfile.driving:
        return 'Driving';
      case _DirectionsProfile.walking:
        return 'Walking';
      case _DirectionsProfile.cycling:
        return 'Cycling';
    }
  }
}

class _RoutePlannerSelectCard extends StatelessWidget {
  const _RoutePlannerSelectCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _SafeText(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 3),
          _SafeText(
            subtitle,
            maxLines: 1,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _RoutePlannerSelectButton extends StatelessWidget {
  const _RoutePlannerSelectButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 7),
            Expanded(
              child: _SafeText(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(CupertinoIcons.chevron_down, color: color, size: 12),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerSummaryCard extends StatelessWidget {
  const _RoutePlannerSummaryCard({
    required this.route,
    required this.selectedPlace,
    required this.profile,
    required this.settings,
    required this.onClearRoute,
  });

  final _PlannedRoute? route;
  final _MapboxPlaceResult? selectedPlace;
  final _DirectionsProfile profile;
  final SettingsService settings;
  final VoidCallback? onClearRoute;

  @override
  Widget build(BuildContext context) {
    final bool hasRoute = route != null;

    return _RoutePlannerGlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: _SafeText(
                  'Route summary',
                  maxLines: 1,
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: _kGreen.withValues(alpha: 0.18)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(CupertinoIcons.circle_fill, color: _kGreen, size: 7),
                    SizedBox(width: 5),
                    _SafeText(
                      'Live traffic',
                      maxLines: 1,
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kBlue.withValues(alpha: 0.18),
                        border: Border.all(
                          color: _kBlue.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Icon(
                        _RoutePlannerModeChip._profileIcon(profile),
                        color: _kBlue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: hasRoute
                          ? Row(
                              children: <Widget>[
                                Expanded(
                                  child: _RouteMetric(
                                    value: route!.distanceLabel(settings),
                                    label: 'Distance',
                                  ),
                                ),
                                _MetricDivider(),
                                Expanded(
                                  child: _RouteMetric(
                                    value: route!.durationLabel(),
                                    label: 'Est. time',
                                  ),
                                ),
                              ],
                            )
                          : _SafeText(
                              selectedPlace == null
                                  ? 'Select a destination to preview route.'
                                  : 'Ready to calculate route to ${selectedPlace!.name}.',
                              maxLines: 2,
                              style: const TextStyle(
                                color: _kTextMuted,
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    if (hasRoute) ...<Widget>[
                      _MetricDivider(),
                      Expanded(
                        child: _RouteMetric(
                          value: _RoutePlannerModeChip._profileShortLabel(
                            route!.profile,
                          ),
                          label: 'Mode',
                          color: _kBlue,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 34,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RoutePreviewPainter(
                      active: hasRoute,
                      color: hasRoute ? _kBlue : _kTextMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasRoute && onClearRoute != null) ...<Widget>[
            const SizedBox(height: 10),
            _RoutePlannerSecondaryButton(
              label: 'CLEAR ROUTE',
              icon: CupertinoIcons.trash,
              onTap: onClearRoute!,
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({
    required this.value,
    required this.label,
    this.color = _kTextPrimary,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SafeText(
          value,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        _SafeText(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: _kTextMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 9),
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _RoutePlannerPlanButton extends StatelessWidget {
  const _RoutePlannerPlanButton({
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = enabled ? _kGreen : _kTextMuted;

    return _PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _kAnimFast,
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: enabled
              ? LinearGradient(
                  colors: <Color>[
                    _kGreen.withValues(alpha: 0.86),
                    _kGreen.withValues(alpha: 0.56),
                  ],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled
                ? _kGreen.withValues(alpha: 0.40)
                : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: _kGreen.withValues(alpha: 0.24),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (loading)
              const CupertinoActivityIndicator(color: Colors.white, radius: 10)
            else
              const Icon(
                CupertinoIcons.location_fill,
                color: Colors.white,
                size: 19,
              ),
            const SizedBox(width: 10),
            _SafeText(
              loading ? 'PLANNING ROUTE...' : 'PLAN ROUTE',
              maxLines: 1,
              style: TextStyle(
                color: enabled ? Colors.white : color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerSecondaryButton extends StatelessWidget {
  const _RoutePlannerSecondaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: _kTextMuted, size: 15),
            const SizedBox(width: 8),
            _SafeText(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerGlassCard extends StatelessWidget {
  const _RoutePlannerGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.56),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RoutePlannerGradientButton extends StatelessWidget {
  const _RoutePlannerGradientButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        height: compact ? 44 : 48,
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              color.withValues(alpha: 0.85),
              color.withValues(alpha: 0.42),
            ],
          ),
          borderRadius: BorderRadius.circular(compact ? 17 : 18),
          border: Border.all(color: color.withValues(alpha: 0.36)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white, size: compact ? 13 : 15),
            const SizedBox(width: 7),
            Flexible(
              child: _SafeText(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 10 : 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePlannerTinyButton extends StatelessWidget {
  const _RoutePlannerTinyButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableScale(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _RoutePlannerPlaceTile extends StatelessWidget {
  const _RoutePlannerPlaceTile({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  final _MapboxPlaceResult place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = selected ? _kGreen : _kBlue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: _PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: _kAnimFast,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: selected ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent.withValues(alpha: selected ? 0.34 : 0.16),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.location_solid,
                color: accent,
                size: 17,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SafeText(
                      place.name,
                      maxLines: 1,
                      style: const TextStyle(
                        color: _kTextPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _SafeText(
                      place.address,
                      maxLines: 2,
                      style: const TextStyle(
                        color: _kTextMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
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

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter({
    required this.active,
    required this.color,
  });

  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1.0;

    for (double x = 0; x < size.width; x += 38) {
      canvas.drawLine(Offset(x, 0), Offset(x + 22, size.height), gridPaint);
    }

    final ui.Path path = ui.Path();
    path.moveTo(12, size.height * 0.62);
    path.cubicTo(
      size.width * 0.28,
      size.height * 0.10,
      size.width * 0.38,
      size.height * 0.92,
      size.width * 0.58,
      size.height * 0.42,
    );
    path.cubicTo(
      size.width * 0.78,
      -4,
      size.width * 0.82,
      size.height * 0.88,
      size.width - 14,
      size.height * 0.32,
    );

    final Paint routePaint = Paint()
      ..color = color.withValues(alpha: active ? 0.82 : 0.28)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, routePaint);

    final Paint dotPaint = Paint()
      ..color = color.withValues(alpha: active ? 1.0 : 0.45);
    canvas.drawCircle(Offset(12, size.height * 0.62), 5, dotPaint);
    canvas.drawCircle(Offset(size.width - 14, size.height * 0.32), 6, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.active != active || oldDelegate.color != color;
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
                    isBusy: false,
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

class _LocationPuckMarker extends StatefulWidget {
  const _LocationPuckMarker({
    required this.heading,
  });

  final double heading;

  @override
  State<_LocationPuckMarker> createState() => _LocationPuckMarkerState();
}

class _LocationPuckMarkerState extends State<_LocationPuckMarker>
    with SingleTickerProviderStateMixin {
  static const Color _blue = Color(0xFF2F80FF);
  static const Color _blueDeep = Color(0xFF0B58D8);

  late final AnimationController _controller;
  double _displayHeading = 0.0;

  @override
  void initState() {
    super.initState();

    _displayHeading = _normalizeHeading(widget.heading);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _LocationPuckMarker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final double next = _normalizeHeading(widget.heading);
    double delta = next - _normalizeHeading(_displayHeading);

    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;

    // Ignore tiny GPS heading jitter so the puck stays stable when stopped.
    if (delta.abs() < 1.0) return;

    _displayHeading += delta;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static double _normalizeHeading(double value) {
    if (!value.isFinite) return 0.0;
    final double normalized = value % 360.0;
    return normalized < 0.0 ? normalized + 360.0 : normalized;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final double t = _controller.value;
          final double pulse = Curves.easeOutCubic.transform(t);
          final double breathe = 0.5 + math.sin(t * math.pi * 2.0) * 0.5;

          return SizedBox(
            width: 74,
            height: 74,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Subtle expanding GPS pulse.
                Opacity(
                  opacity: (1.0 - pulse).clamp(0.0, 1.0) * 0.22,
                  child: Container(
                    width: 30 + pulse * 32,
                    height: 30 + pulse * 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1,
                      ),
                    ),
                  ),
                ),

                // Accuracy halo like modern map apps.
                Container(
                  width: 42 + breathe * 3,
                  height: 42 + breathe * 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _blue.withValues(alpha: 0.16),
                    border: Border.all(
                      color: _blue.withValues(alpha: 0.22),
                      width: 1.2,
                    ),
                  ),
                ),

                // Soft ground shadow.
                Transform.translate(
                  offset: const Offset(0, 5),
                  child: Container(
                    width: 34,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.20),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),

                // Small heading nub, matching the reference puck.
                AnimatedRotation(
                  turns: _displayHeading / 360.0,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: Transform.translate(
                    offset: const Offset(0, -18),
                    child: Container(
                      width: 8,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.26),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 4,
                        height: 8,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),

                // White outer puck ring.
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Colors.white,
                        Color(0xFFE9F1FF),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: _blue.withValues(alpha: 0.24),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),

                // Blue center.
                Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-0.25, -0.30),
                      radius: 0.9,
                      colors: <Color>[
                        Color(0xFF6FB2FF),
                        _blue,
                        _blueDeep,
                      ],
                      stops: <double>[0.0, 0.58, 1.0],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.92),
                      width: 1.4,
                    ),
                  ),
                ),

                // Gloss highlight.
                Transform.translate(
                  offset: const Offset(-4, -5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Kept for source compatibility with earlier painter-based puck versions.
class _LocationHeadingConePainter extends CustomPainter {
  const _LocationHeadingConePainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // No-op: the updated puck uses lightweight widgets instead of a cone painter.
  }

  @override
  bool shouldRepaint(covariant _LocationHeadingConePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// Compatibility marker for older mini-map / thumbnail widgets that still
/// reference _LiveMarker.
class _LiveMarker extends StatelessWidget {
  const _LiveMarker();

  @override
  Widget build(BuildContext context) {
    return const _LocationPuckMarker(heading: 0.0);
  }
}

class _NavigationGeoMarker extends StatefulWidget {
  const _NavigationGeoMarker({
    required this.heading,
  });

  final double heading;

  @override
  State<_NavigationGeoMarker> createState() => _NavigationGeoMarkerState();
}

class _NavigationGeoMarkerState extends State<_NavigationGeoMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulse = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double rad = widget.heading * math.pi / 180.0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Opacity(
                opacity: (1.0 - _pulse.value).clamp(0.0, 1.0) * 0.32,
                child: Container(
                  width: 30 + _pulse.value * 34,
                  height: 30 + _pulse.value * 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2A5BFF),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.30),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.90),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: rad,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned(
                      top: 11,
                      child: const CustomPaint(
                        size: Size(34, 44),
                        painter: _NavArrowPainter(
                          fill: Color(0xFF2A5BFF),
                          stroke: Colors.white,
                          shadow: Color(0x442A5BFF),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFFDEE5FF),
                            width: 1.5,
                          ),
                        ),
                      ),
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

class _NavArrowPainter extends CustomPainter {
  const _NavArrowPainter({
    required this.fill,
    required this.stroke,
    required this.shadow,
  });

  final Color fill;
  final Color stroke;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Path path = ui.Path()
      ..moveTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height * 0.70)
      ..lineTo(size.width * 0.57, size.height * 0.62)
      ..lineTo(size.width * 0.52, size.height)
      ..lineTo(size.width * 0.48, size.height)
      ..lineTo(size.width * 0.43, size.height * 0.62)
      ..lineTo(0, size.height * 0.70)
      ..close();

    canvas.drawShadow(path, shadow, 8, false);

    final Paint fillPaint = Paint()..color = fill;
    final Paint strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _NavArrowPainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke ||
        oldDelegate.shadow != shadow;
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
    required this.isBusy,
    required this.onTap,
    required this.timerNotifier,
  });

  final bool isTracking;
  final bool isBusy;
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
    if (!mounted || widget.isBusy || _pressed == value) return;
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
        if (!widget.isBusy) widget.onTap();
      },
      child: AnimatedOpacity(
        duration: _kAnimFast,
        opacity: widget.isBusy ? 0.78 : 1.0,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1.0,
          duration: _kAnimFast,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: _kAnimFast,
            curve: Curves.easeOut,
            height: 48,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _pressed
                    ? <Color>[
                        main.withValues(alpha: 0.72),
                        main.withValues(alpha: 0.55),
                      ]
                    : <Color>[
                        main,
                        main.withValues(alpha: 0.82),
                      ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.13),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: main.withValues(alpha: _pressed ? 0.18 : 0.34),
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
                      scale: Tween<double>(begin: 0.88, end: 1.0)
                          .animate(animation),
                      child: child,
                    ),
                  );
                },
                child: widget.isBusy
                    ? Row(
                        key: const ValueKey<String>('busy'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CupertinoActivityIndicator(
                            radius: 8,
                            color: textColor,
                          ),
                          const SizedBox(width: 8),
                          _SafeText(
                            widget.isTracking ? 'SAVING' : 'STARTING',
                            maxLines: 1,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      )
                    : widget.isTracking
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
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    _SafeText(
                                      _formatSeconds(seconds),
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17,
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
                                const SizedBox(width: 7),
                                _SafeText(
                                  'START',
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
