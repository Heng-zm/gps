// ignore_for_file: unused_element, deprecated_member_use, prefer_const_constructors

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../../models/trip_data.dart';
import '../../models/mapbox_route_models.dart';
import '../../models/weather_data.dart';
import '../../services/services.dart';
import '../../services/mapbox_directions_service.dart';
import '../../utils/smooth_polyline.dart';
import '../../config/mapbox_config.dart';
import '../../widgets/ai_chat_sheet.dart';
import '../../widgets/speedometer_widget.dart';
import '../../widgets/weather_widget.dart';
import '../map/map_screen.dart';
import '../summary_screen.dart';
import 'tracking_ar_camera_screen.dart';
import '../../widgets/route_planner_sheet.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_action_button.dart';
import '../../widgets/common/app_glass_card.dart';
import '../../widgets/common/app_metric_card.dart';
import '../../widgets/common/app_status_pill.dart';

part 'tracking_map_layer.dart';
part 'tracking_top_hud.dart';
part 'tracking_bottom_dock.dart';
part 'tracking_models.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TRACKING SCREEN
// Split into part files under lib/screens/tracking/ for cleaner maintenance.
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// TRACKING SCREEN — Premium Black / White / Blue UI
// UI/UX enhanced + performance optimized + Flutter Web text hit-test safe
// ═══════════════════════════════════════════════════════════════════════════════

// ── Colors ───────────────────────────────────────────────────────────────────
const Color _kBlue = AppColors.blue;
const Color _kBlueSoft = AppColors.blueSoft;
const Color _kBlueDeep = AppColors.blueDeep;
const Color _kRed = AppColors.red;
const Color _kRedGlow = Color(0x33FF453A);
const Color _kGreen = AppColors.green;
const Color _kBg = AppColors.black;
const Color _kSurface = AppColors.surface;
const Color _kBorder = AppColors.border;
const Color _kTextPrimary = AppColors.white;
const Color _kTextMuted = AppColors.white70;
const LinearGradient _kBlueGlassGradient = AppColors.blueGlassGradient;

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
        return 'COMPASS';
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
        return 'Hybrid heading';
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


enum _TrackingPerformanceMode {
  battery,
  balanced,
  performance,
}

extension _TrackingPerformanceModeX on _TrackingPerformanceMode {
  String get label {
    switch (this) {
      case _TrackingPerformanceMode.battery:
        return 'BATTERY';
      case _TrackingPerformanceMode.balanced:
        return 'BALANCED';
      case _TrackingPerformanceMode.performance:
        return 'PERFORMANCE';
    }
  }

  IconData get icon {
    switch (this) {
      case _TrackingPerformanceMode.battery:
        return CupertinoIcons.battery_25;
      case _TrackingPerformanceMode.balanced:
        return CupertinoIcons.speedometer;
      case _TrackingPerformanceMode.performance:
        return CupertinoIcons.bolt_fill;
    }
  }

  Duration get cameraThrottle {
    switch (this) {
      case _TrackingPerformanceMode.battery:
        return const Duration(milliseconds: 900);
      case _TrackingPerformanceMode.balanced:
        return const Duration(milliseconds: 520);
      case _TrackingPerformanceMode.performance:
        return const Duration(milliseconds: 260);
    }
  }

  int get routeRenderLimit {
    switch (this) {
      case _TrackingPerformanceMode.battery:
        return 420;
      case _TrackingPerformanceMode.balanced:
        return 900;
      case _TrackingPerformanceMode.performance:
        return 1600;
    }
  }

  _TrackingPerformanceMode get next {
    switch (this) {
      case _TrackingPerformanceMode.battery:
        return _TrackingPerformanceMode.balanced;
      case _TrackingPerformanceMode.balanced:
        return _TrackingPerformanceMode.performance;
      case _TrackingPerformanceMode.performance:
        return _TrackingPerformanceMode.battery;
    }
  }
}



extension _TrackingPerformanceModeUxX on _TrackingPerformanceMode {
  String get shortLabel {
    switch (this) {
      case _TrackingPerformanceMode.battery:
        return 'Battery';
      case _TrackingPerformanceMode.balanced:
        return 'Balanced';
      case _TrackingPerformanceMode.performance:
        return 'Fast';
    }
  }

  String get description {
    switch (this) {
      case _TrackingPerformanceMode.battery:
        return 'Lower map refresh rate for longer trips';
      case _TrackingPerformanceMode.balanced:
        return 'Smooth tracking with moderate battery use';
      case _TrackingPerformanceMode.performance:
        return 'Fastest camera and route updates';
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
  final Battery _battery = Battery();

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
  final ValueNotifier<BatteryState?> _batteryStateN =
      ValueNotifier<BatteryState?>(null);
  final ValueNotifier<double> _maxSpeedN = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _accuracyN = ValueNotifier<double>(40.0);
  final ValueNotifier<_MapFollowMode> _followModeN =
      ValueNotifier<_MapFollowMode>(_MapFollowMode.followMe);
  final ValueNotifier<bool> _autoPausedN = ValueNotifier<bool>(false);
  final ValueNotifier<int> _autoPauseStoppedN = ValueNotifier<int>(0);
  final ValueNotifier<bool> _actionBusyN = ValueNotifier<bool>(false);
  final ValueNotifier<MapboxStandardPreset> _mapPresetN =
      ValueNotifier<MapboxStandardPreset>(MapboxStandardPreset.day);
  final ValueNotifier<MapboxRuntimeMode> _mapRuntimeModeN =
      ValueNotifier<MapboxRuntimeMode>(MapboxRuntimeMode.auto);
  final ValueNotifier<PlannedRoute?> _plannedRouteN =
      ValueNotifier<PlannedRoute?>(null);
  final ValueNotifier<bool> _directionsLoadingN = ValueNotifier<bool>(false);
  final ValueNotifier<_TrackingPerformanceMode> _performanceModeN =
      ValueNotifier<_TrackingPerformanceMode>(_TrackingPerformanceMode.balanced);
  final ValueNotifier<String> _coachTipN = ValueNotifier<String>('Ready');

  bool _mapReady = false;
  bool _handlingAction = false;
  bool _disposed = false;

  int _polylinePointCount = 0;
  int _pendingSignal = 0;
  DateTime? _lastWeatherFetch;
  DateTime? _lastActionAt;
  DateTime? _lastMapMoveAt;
  LatLng? _lastMapPos;
  double _hybridHeadingDeg = 0.0;
  double _lastCompassRawDeg = 0.0;
  int _compassJumpCount = 0;
  DateTime? _lastCompassWarningAt;
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
  StreamSubscription<BatteryState>? _batteryStateSub;

  @override
  void initState() {
    super.initState();
    _mapController = fm.MapController();
    _scrollController = ScrollController();

    _settings.addListener(_onSettingsChanged);
    _hydrateInitialGpsState();
    _initCompass();
    _startTickTimer();
    _initBatteryPlus();

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

  double _normHeading(double value) {
    if (!value.isFinite) return 0.0;
    final double normalized = value % 360.0;
    return normalized < 0.0 ? normalized + 360.0 : normalized;
  }

  double _headingDelta(double from, double to) {
    double delta = _normHeading(to) - _normHeading(from);
    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;
    return delta;
  }

  double _lerpHeading(double from, double to, double t) {
    final double safeT = t.clamp(0.0, 1.0).toDouble();
    return _normHeading(_normHeading(from) + _headingDelta(from, to) * safeT);
  }

  double _smoothHeading({
    required double current,
    required double target,
    double factor = 0.18,
  }) {
    return _lerpHeading(current, target, factor);
  }

  bool _isCompassUnstable({
    required double previous,
    required double current,
  }) {
    if (!previous.isFinite || !current.isFinite) return false;
    return _headingDelta(previous, current).abs() > 48.0;
  }

  double _hybridHeading({
    required double compassHeading,
    required double travelHeading,
    required double speedMph,
  }) {
    final double safeCompass = _normHeading(compassHeading);
    final double safeTravel = _normHeading(travelHeading);
    final double safeSpeed = _safeSpeed(speedMph);

    // Low speed: compass is better because GPS course is noisy.
    if (safeSpeed < 2.0) return safeCompass;

    // Walking/slow moto: blend compass and GPS course.
    if (safeSpeed < 6.0) {
      final double t = ((safeSpeed - 2.0) / 4.0).clamp(0.0, 1.0).toDouble();
      return _lerpHeading(safeCompass, safeTravel, 0.35 + t * 0.35);
    }

    // Riding/driving: GPS travel heading is more stable than magnetometer.
    return safeTravel;
  }

  void _updateHybridHeading({double? speedMph}) {
    final double next = _hybridHeading(
      compassHeading: _compassN.value,
      travelHeading: _travelHdgN.value,
      speedMph: speedMph ?? _speedN.value,
    );

    final double smoothed = _smoothHeading(
      current: _hybridHeadingDeg,
      target: next,
      factor: _safeSpeed(speedMph ?? _speedN.value) < 2.0 ? 0.14 : 0.24,
    );

    _hybridHeadingDeg = smoothed;
    _setN(_travelHdgN, smoothed);
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

          final double normalizedHeading = _normHeading(heading);
          final bool unstable = _isCompassUnstable(
            previous: _lastCompassRawDeg,
            current: normalizedHeading,
          );
          _lastCompassRawDeg = normalizedHeading;

          if (unstable) {
            _compassJumpCount++;
            final DateTime now = DateTime.now();
            final DateTime? lastWarning = _lastCompassWarningAt;
            if (_compassJumpCount >= 3 &&
                (lastWarning == null ||
                    now.difference(lastWarning) > const Duration(seconds: 12))) {
              _lastCompassWarningAt = now;
              _setN(_coachTipN, 'Compass unstable · move phone in figure-8');
            }
          } else {
            _compassJumpCount = math.max(0, _compassJumpCount - 1);
          }

          final double current = _compassN.value;
          final double smoothedCompass = _smoothHeading(
            current: current,
            target: normalizedHeading,
            factor: 0.22,
          );

          _setN(_compassN, smoothedCompass);
          _updateHybridHeading();
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


  void _initBatteryPlus() {
    unawaited(_batteryStateSub?.cancel());

    try {
      _batteryStateSub = _battery.onBatteryStateChanged.listen(
        (BatteryState state) {
          if (!mounted || _disposed) return;
          _setN(_batteryStateN, state);
          unawaited(_pollBattery());
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Battery state stream error: $error\n$stackTrace');
        },
        cancelOnError: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Battery state stream init failed: $error\n$stackTrace');
    }
  }

  Future<void> _pollBattery() async {
    if (!mounted || _disposed) return;

    try {
      final int level = await _battery.batteryLevel;
      if (!mounted || _disposed) return;

      _setN(_batteryN, level.clamp(0, 100).toInt());

      try {
        final BatteryState state = await _battery.batteryState;
        if (!mounted || _disposed) return;
        _setN(_batteryStateN, state);
      } catch (_) {
        // Some platforms support level but may not return state reliably.
      }
    } on PlatformException catch (error) {
      debugPrint('battery_plus platform error: ${error.message}');
      if (mounted && !_disposed) {
        _setN(_batteryN, null);
        _setN(_batteryStateN, null);
      }
    } catch (error, stackTrace) {
      debugPrint('battery_plus poll error: $error\n$stackTrace');
      if (mounted && !_disposed) {
        _setN(_batteryN, null);
        _setN(_batteryStateN, null);
      }
    }
  }

  void _cyclePerformanceMode() {
    HapticFeedback.selectionClick();
    final _TrackingPerformanceMode next = _performanceModeN.value.next;
    _setN(_performanceModeN, next);
    _setN(_coachTipN, 'Map mode: ${next.label}');
  }

  void _updateCoachTip({
    required double speedMph,
    required double accuracy,
    required bool autoPaused,
  }) {
    String next = 'Route ready';

    if (autoPaused) {
      next = 'Auto paused · move to resume';
    } else if (!accuracy.isFinite || accuracy >= 35.0) {
      next = 'Weak GPS · move outdoors';
    } else if (speedMph > _settings.speedAlertMph) {
      next = 'Speed alert · slow down';
    } else if (_trackingN.value && speedMph < 1.0) {
      next = 'Standing by · GPS stable';
    } else if (_trackingN.value) {
      next = 'Tracking smoothly';
    }

    if (_coachTipN.value != next) {
      _setN(_coachTipN, next);
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
    unawaited(_batteryStateSub?.cancel());

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
    _batteryStateN.dispose();
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
    _performanceModeN.dispose();
    _coachTipN.dispose();

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
    _updateCoachTip(
      speedMph: speed,
      accuracy: _accuracyN.value,
      autoPaused: _autoPausedN.value,
    );
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
    final LatLng? previous = _lastMapPos;
    if (previous != null && _isValidLL(previous)) {
      final double distance = _distanceCalc.as(
        LengthUnit.Meter,
        previous,
        point.position,
      );

      if (distance >= _kMapMoveDist) {
        final double rawBearing = _distanceCalc.bearing(previous, point.position);
        final double smoothedTravel = _smoothHeading(
          current: _travelHdgN.value,
          target: rawBearing,
          factor: _safeSpeed(point.speedMph) < 6.0 ? 0.18 : 0.32,
        );
        _setN(_travelHdgN, smoothedTravel);
      }
    }

    _updateHybridHeading(speedMph: point.speedMph);
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

    final String tip = switch (next) {
      _MapFollowMode.followMe => 'Follow mode · centered on you',
      _MapFollowMode.headingUp => 'Heading mode · travel direction up',
      _MapFollowMode.northUp => 'Compass mode · hybrid heading',
      _MapFollowMode.freeView => 'Free view · move map by hand',
    };
    _setN(_coachTipN, tip);
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

  void _openArRouteCamera() {
    HapticFeedback.mediumImpact();

    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => TrackingArCameraScreen(
          speedN: _speedN,
          compassN: _compassN,
          headingN: _travelHdgN,
          accuracyN: _accuracyN,
          batteryN: _batteryN,
          batteryStateN: _batteryStateN,
          coachTipN: _coachTipN,
          posN: _posN,
          plannedRouteN: _plannedRouteN,
          settings: _settings,
        ),
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
      builder: (_) {
        final PlannedRoute? plannedRoute = _plannedRouteN.value;

        return RoutePlannerSheet<DirectionsProfile, MapboxStandardPreset,
            MapboxRuntimeMode>(
          mapboxAccessToken: _kMapboxAccessToken,
          initialProfile: DirectionsProfile.drivingTraffic,
          profileOptions: <RoutePlannerOption<DirectionsProfile>>[
            RoutePlannerOption<DirectionsProfile>(
              value: DirectionsProfile.drivingTraffic,
              label: DirectionsProfile.drivingTraffic.label,
              shortLabel: 'Drive+Traffic',
              icon: CupertinoIcons.car_detailed,
            ),
            RoutePlannerOption<DirectionsProfile>(
              value: DirectionsProfile.driving,
              label: DirectionsProfile.driving.label,
              shortLabel: 'Driving',
              icon: CupertinoIcons.car_detailed,
            ),
            RoutePlannerOption<DirectionsProfile>(
              value: DirectionsProfile.walking,
              label: DirectionsProfile.walking.label,
              shortLabel: 'Walking',
              icon: CupertinoIcons.person_fill,
            ),
            RoutePlannerOption<DirectionsProfile>(
              value: DirectionsProfile.cycling,
              label: DirectionsProfile.cycling.label,
              shortLabel: 'Cycling',
              icon: Icons.directions_bike_rounded,
            ),
          ],
          initialPreset: _mapPresetN.value,
          presetOptions: <RoutePlannerOption<MapboxStandardPreset>>[
            RoutePlannerOption<MapboxStandardPreset>(
              value: MapboxStandardPreset.day,
              label: MapboxStandardPreset.day.label,
              icon: CupertinoIcons.sun_max_fill,
            ),
            RoutePlannerOption<MapboxStandardPreset>(
              value: MapboxStandardPreset.dusk,
              label: MapboxStandardPreset.dusk.label,
              icon: CupertinoIcons.sunset_fill,
            ),
            RoutePlannerOption<MapboxStandardPreset>(
              value: MapboxStandardPreset.dawn,
              label: MapboxStandardPreset.dawn.label,
              icon: CupertinoIcons.sunrise_fill,
            ),
            RoutePlannerOption<MapboxStandardPreset>(
              value: MapboxStandardPreset.night,
              label: MapboxStandardPreset.night.label,
              icon: CupertinoIcons.moon_stars_fill,
            ),
          ],
          initialRuntime: _mapRuntimeModeN.value,
          runtimeOptions: <RoutePlannerOption<MapboxRuntimeMode>>[
            RoutePlannerOption<MapboxRuntimeMode>(
              value: MapboxRuntimeMode.auto,
              label: MapboxRuntimeMode.auto.label,
              icon: CupertinoIcons.sparkles,
            ),
            RoutePlannerOption<MapboxRuntimeMode>(
              value: MapboxRuntimeMode.native,
              label: MapboxRuntimeMode.native.label,
              icon: CupertinoIcons.device_phone_portrait,
            ),
            RoutePlannerOption<MapboxRuntimeMode>(
              value: MapboxRuntimeMode.webFallback,
              label: MapboxRuntimeMode.webFallback.label,
              icon: CupertinoIcons.globe,
            ),
          ],
          directionsLoading: _directionsLoadingN.value,
          plannedRoute: plannedRoute == null
              ? null
              : PlannedRouteSummary.fromRoute(
                  plannedRoute,
                  settings: _settings,
                ),
          currentPositionProvider: () => _posN.value,
          onPresetChanged: (preset) => _setN(_mapPresetN, preset),
          onRuntimeChanged: (mode) => _setN(_mapRuntimeModeN, mode),
          onPlanRoute: _planDirectionsRoute,
          onClearRoute: () {
            _setN(_plannedRouteN, null);
            Navigator.of(context).maybePop();
          },
        );
      },
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
    required DirectionsProfile profile,
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

    _setN(_directionsLoadingN, true);

    try {
      final MapboxDirectionsService service = MapboxDirectionsService(
        accessToken: _kMapboxAccessToken,
      );

      final PlannedRoute route = await service.planRoute(
        start: start,
        destination: destination,
        profile: profile,
      );

      if (!mounted || _disposed) return;

      _setN(_plannedRouteN, route);

      Navigator.of(context).maybePop();
      _showSnack('Route planned successfully.');
    } on MapboxDirectionsException catch (error) {
      if (mounted && !_disposed) _showSnack(error.message);
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
    return kIsWeb || _mapRuntimeModeN.value == MapboxRuntimeMode.webFallback;
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
                performanceModeN: _performanceModeN,
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
              batteryStateN: _batteryStateN,
              accuracyN: _accuracyN,
              autoPausedN: _autoPausedN,
              performanceModeN: _performanceModeN,
              coachTipN: _coachTipN,
              onPerformanceTap: _cyclePerformanceMode,
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
              onArTap: _openArRouteCamera,
              onWeatherTap: _openFullWeather,
              onMapboxTap: _openMapboxControls,
              onFollowModeTap: _cycleMapFollowMode,
              performanceModeN: _performanceModeN,
              onPerformanceTap: _cyclePerformanceMode,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
