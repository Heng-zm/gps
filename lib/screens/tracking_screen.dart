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

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS — Premium Dark Gold UI
// ─────────────────────────────────────────────────────────────────────────────

const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD86B);
const Color _kRed = Color(0xFFFF3B30);
const Color _kTeal = Color(0xFF32D74B);
const Color _kBg = Color(0xFF000000);
const Color _kCard = Color(0xFF0E0E10);
const Color _kCardBorder = Color(0xFF2C2C30);
const Color _kTextMuted = Color(0x99FFFFFF);

const Duration _kTickDuration = Duration(seconds: 1);
const Duration _kSignalDebounceDuration = Duration(seconds: 2);
const Duration _kBatteryPollDuration = Duration(seconds: 60);
const Duration _kWeatherRefreshGap = Duration(minutes: 10);
const Duration _kMapMoveThrottle = Duration(milliseconds: 550);

const LatLng _kDefaultMapCenter = LatLng(11.5564, 104.9282);
const double _kDefaultMapZoom = 16.0;
const double _kMinHeadingSpeedMph = 2.0;

const _CompassRingPainter _kCompassRingPainter = _CompassRingPainter();
const _NeedlePainter _kNeedlePainter = _NeedlePainter();

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

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

  final ValueNotifier<int> _tickNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> _speedNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _travelHeadingNotifier =
      ValueNotifier<double>(0.0);
  final ValueNotifier<double> _deviceCompassNotifier =
      ValueNotifier<double>(0.0);
  final ValueNotifier<int> _signalNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _trackingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<WeatherData?> _weatherNotifier =
      ValueNotifier<WeatherData?>(null);
  final ValueNotifier<LatLng?> _positionNotifier = ValueNotifier<LatLng?>(null);
  final ValueNotifier<bool> _weatherLoadingNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<int> _elapsedSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int?> _batteryNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<double> _maxSpeedNotifier = ValueNotifier<double>(0.0);

  bool _mapReady = false;
  bool _handlingAction = false;
  bool _disposed = false;

  int _polylinePointCount = 0;
  int _pendingSignal = 0;

  DateTime? _lastWeatherFetch;
  DateTime? _lastMapMoveAt;
  LatLng? _lastMapPosition;

  Timer? _tickTimer;
  Timer? _signalDebounce;

  final fm.MapController _mapController = fm.MapController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<TripPoint>? _pointSub;
  StreamSubscription<CompassEvent>? _compassSub;

  static const MethodChannel _batteryChannel = MethodChannel(
    'trackpro/battery',
  );

  @override
  void initState() {
    super.initState();

    _settings.addListener(_onSettingsChanged);
    _hydrateInitialGpsState();
    _initCompass();
    _startTickTimer();
    unawaited(_pollBattery());

    if (_gps.isTracking) {
      _attachGpsStream();
    }

    unawaited(_fetchWeather(force: true));
  }

  void _hydrateInitialGpsState() {
    final List<TripPoint> points = _gps.currentPoints;

    if (points.isNotEmpty) {
      final TripPoint last = points.last;
      _positionNotifier.value = last.position;
      _speedNotifier.value = _safeSpeed(last.speedMph);
      _polylinePointCount = points.length;
    }

    _trackingNotifier.value = _gps.isTracking;
    _maxSpeedNotifier.value = _safeSpeed(_gps.currentMaxSpeedMph);

    if (_gps.isTracking) {
      _elapsedSecondsNotifier.value = math.max(
        0,
        _gps.currentTripTime.inSeconds,
      );
    }
  }

  void _initCompass() {
    try {
      final Stream<CompassEvent>? events = FlutterCompass.events;
      if (events == null) return;

      _compassSub = events.listen(
        (CompassEvent event) {
          if (!mounted || _disposed) return;

          final double? heading = event.heading;
          if (heading == null || !heading.isFinite) return;

          final double current = _deviceCompassNotifier.value;
          double delta = heading - (current % 360.0);

          if (delta > 180.0) delta -= 360.0;
          if (delta < -180.0) delta += 360.0;

          _setNotifierValue<double>(_deviceCompassNotifier, current + delta);
        },
        onError: (Object e, StackTrace st) {
          debugPrint('Compass stream error: $e\n$st');
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      debugPrint('Compass init failed: $e\n$st');
    }
  }

  void _startTickTimer() {
    _tickTimer?.cancel();

    _tickTimer = Timer.periodic(_kTickDuration, (_) {
      if (!mounted || _disposed) return;

      _tickNotifier.value++;

      if (_trackingNotifier.value) {
        _setNotifierValue<int>(
          _elapsedSecondsNotifier,
          math.max(0, _gps.currentTripTime.inSeconds),
        );
      }

      if (_tickNotifier.value % _kBatteryPollDuration.inSeconds == 0) {
        unawaited(_pollBattery());
      }
    });
  }

  Future<void> _pollBattery() async {
    try {
      final int? level = await _batteryChannel.invokeMethod<int>(
        'getBatteryLevel',
      );

      if (!mounted || _disposed) return;

      _setNotifierValue<int?>(_batteryNotifier, level?.clamp(0, 100).toInt());
    } on MissingPluginException {
      if (mounted && !_disposed) {
        _setNotifierValue<int?>(_batteryNotifier, null);
      }
    } on PlatformException catch (e) {
      debugPrint('Battery platform error: ${e.message}');
      if (mounted && !_disposed) {
        _setNotifierValue<int?>(_batteryNotifier, null);
      }
    } catch (e, st) {
      debugPrint('Battery poll failed: $e\n$st');
      if (mounted && !_disposed) {
        _setNotifierValue<int?>(_batteryNotifier, null);
      }
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

    _tickNotifier.dispose();
    _speedNotifier.dispose();
    _travelHeadingNotifier.dispose();
    _deviceCompassNotifier.dispose();
    _signalNotifier.dispose();
    _trackingNotifier.dispose();
    _weatherNotifier.dispose();
    _positionNotifier.dispose();
    _weatherLoadingNotifier.dispose();
    _elapsedSecondsNotifier.dispose();
    _batteryNotifier.dispose();
    _maxSpeedNotifier.dispose();

    super.dispose();
  }

  void _attachGpsStream() {
    unawaited(_pointSub?.cancel());
    _pointSub = null;

    final Stream<TripPoint>? stream = _gps.pointStream;
    if (stream == null) return;

    _pointSub = stream.listen(
      _onTripPoint,
      onError: (Object e, StackTrace st) {
        debugPrint('GPS point stream error: $e\n$st');
      },
      cancelOnError: false,
    );
  }

  void _onTripPoint(TripPoint point) {
    if (!mounted || _disposed) return;
    if (!_isValidLatLng(point.position)) return;

    final double safeSpeed = _safeSpeed(point.speedMph);

    _setNotifierValue<double>(_speedNotifier, safeSpeed);
    _setNotifierValue<LatLng?>(_positionNotifier, point.position);

    if (safeSpeed > _maxSpeedNotifier.value) {
      _setNotifierValue<double>(_maxSpeedNotifier, safeSpeed);
    }

    _updateTravelHeading(point);
    _updateSignalStrength(point);
    _updateMapCamera(point);

    _polylinePointCount = _gps.currentPoints.length;
  }

  void _updateTravelHeading(TripPoint point) {
    if (point.speedMph <= _kMinHeadingSpeedMph) return;

    final List<TripPoint> points = _gps.currentPoints;
    if (points.length < 2) return;

    final LatLng previous = points[points.length - 2].position;
    final LatLng current = points.last.position;

    if (!_isValidLatLng(previous) || !_isValidLatLng(current)) return;

    final double bearing = const Distance().bearing(previous, current);
    if (!bearing.isFinite) return;

    final double normalized = _normalizeDegrees(bearing);
    final double previousHeading = _normalizeDegrees(
      _travelHeadingNotifier.value,
    );

    double delta = normalized - previousHeading;

    if (delta > 180.0) delta -= 360.0;
    if (delta < -180.0) delta += 360.0;

    _setNotifierValue<double>(
      _travelHeadingNotifier,
      _travelHeadingNotifier.value + delta,
    );
  }

  void _updateSignalStrength(TripPoint point) {
    final double rawAccuracy = point.accuracyMeters;
    final double accuracy =
        rawAccuracy.isFinite ? rawAccuracy.clamp(5.0, 40.0) : 40.0;
    final int newStrength =
        ((40.0 - accuracy) / 35.0 * 4.0).round().clamp(0, 4);

    _pendingSignal = newStrength;

    _signalDebounce?.cancel();
    _signalDebounce = Timer(_kSignalDebounceDuration, () {
      if (!mounted || _disposed) return;
      _setNotifierValue<int>(_signalNotifier, _pendingSignal);
    });
  }

  void _updateMapCamera(TripPoint point) {
    if (!_mapReady || !_isValidLatLng(point.position)) return;

    final DateTime now = DateTime.now();
    final DateTime? lastMove = _lastMapMoveAt;

    if (lastMove != null && now.difference(lastMove) < _kMapMoveThrottle) {
      return;
    }

    final LatLng? previous = _lastMapPosition;
    if (previous != null && _isValidLatLng(previous)) {
      final double meters = const Distance().as(
        LengthUnit.Meter,
        previous,
        point.position,
      );
      if (meters.isFinite &&
          meters < 3.0 &&
          point.speedMph < _kMinHeadingSpeedMph) {
        return;
      }
    }

    _lastMapMoveAt = now;
    _lastMapPosition = point.position;

    try {
      final double zoom = _mapController.camera.zoom.isFinite
          ? _mapController.camera.zoom
          : _kDefaultMapZoom;
      _mapController.move(point.position, zoom);

      if (point.speedMph > _kMinHeadingSpeedMph) {
        _mapController.rotate(-_normalizeDegrees(_travelHeadingNotifier.value));
      }
    } catch (e) {
      debugPrint('Map camera update skipped: $e');
    }
  }

  Future<void> _fetchWeather({bool force = false}) async {
    if (!_settings.showWeather) {
      _setNotifierValue<WeatherData?>(_weatherNotifier, null);
      _setNotifierValue<bool>(_weatherLoadingNotifier, false);
      return;
    }

    if (_weatherLoadingNotifier.value) return;

    final DateTime now = DateTime.now();
    final DateTime? lastFetch = _lastWeatherFetch;
    if (!force &&
        lastFetch != null &&
        now.difference(lastFetch) < _kWeatherRefreshGap &&
        _weatherNotifier.value != null) {
      return;
    }

    _setNotifierValue<bool>(_weatherLoadingNotifier, true);

    try {
      final Position? pos = await _gps.getCurrentLocation();

      if (!mounted || _disposed) return;

      if (pos == null || !pos.latitude.isFinite || !pos.longitude.isFinite) {
        _setNotifierValue<WeatherData?>(_weatherNotifier, null);
        return;
      }

      final WeatherData? data = await _weather.fetchWeather(
        pos.latitude,
        pos.longitude,
      );

      if (!mounted || _disposed) return;

      _lastWeatherFetch = DateTime.now();
      _setNotifierValue<WeatherData?>(_weatherNotifier, data);
    } catch (e, st) {
      debugPrint('Weather fetch failed: $e\n$st');
    } finally {
      if (mounted && !_disposed) {
        _setNotifierValue<bool>(_weatherLoadingNotifier, false);
      }
    }
  }

  Future<void> _handleAction() async {
    if (_handlingAction) return;

    _handlingAction = true;

    try {
      if (_trackingNotifier.value) {
        await _stopTracking();
      } else {
        await _startTracking();
      }
    } finally {
      _handlingAction = false;
    }
  }

  Future<void> _startTracking() async {
    HapticFeedback.mediumImpact();

    _elapsedSecondsNotifier.value = 0;
    _maxSpeedNotifier.value = 0.0;
    _speedNotifier.value = 0.0;
    _signalNotifier.value = 0;
    _travelHeadingNotifier.value = 0.0;
    _polylinePointCount = 0;
    _pendingSignal = 0;
    _lastMapPosition = null;
    _lastMapMoveAt = null;

    try {
      await _gps.startTracking();
    } catch (e, st) {
      debugPrint('GPS start error: $e\n$st');
    }

    if (!mounted || _disposed) return;

    if (_gps.isTracking) {
      _setNotifierValue<bool>(_trackingNotifier, true);
      _attachGpsStream();
      unawaited(_fetchWeather(force: true));
    } else {
      _promptGpsSettings();
    }
  }

  Future<void> _stopTracking() async {
    HapticFeedback.heavyImpact();

    TripSummary? summary;
    try {
      summary = _gps.stopTracking();
    } catch (e, st) {
      debugPrint('GPS stop error: $e\n$st');
    }

    await _pointSub?.cancel();
    _pointSub = null;

    if (!mounted || _disposed) return;

    _setNotifierValue<bool>(_trackingNotifier, false);
    _setNotifierValue<double>(_speedNotifier, 0.0);
    _setNotifierValue<double>(_maxSpeedNotifier, 0.0);
    _setNotifierValue<double>(_travelHeadingNotifier, 0.0);
    _setNotifierValue<int>(_elapsedSecondsNotifier, 0);
    _polylinePointCount = 0;
    _pendingSignal = 0;
    _lastMapPosition = null;
    _lastMapMoveAt = null;

    _signalDebounce?.cancel();
    _setNotifierValue<int>(_signalNotifier, 0);

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
      builder: (BuildContext c) {
        return CupertinoAlertDialog(
          title: const Text('GPS Access Required'),
          content: const Text(
            'Enable high-accuracy location to monitor your trip and live speed.',
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.pop(c);
                Geolocator.openAppSettings();
              },
              child: const Text('Settings'),
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
          isLive: _trackingNotifier.value,
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

    final TripSummary snap = TripSummary(
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
      builder: (_) => AiChatSheet(summary: snap),
    );
  }

  void _openFullWeather() {
    HapticFeedback.lightImpact();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WeatherSheet(
        weatherNotifier: _weatherNotifier,
        loadingNotifier: _weatherLoadingNotifier,
        onRetry: () => unawaited(_fetchWeather(force: true)),
      ),
    );
  }

  void _markMapReady() {
    _mapReady = true;

    final LatLng? position = _positionNotifier.value;
    if (position == null || !_isValidLatLng(position)) return;

    try {
      _mapController.move(position, _kDefaultMapZoom);
    } catch (_) {}
  }

  static void _setNotifierValue<T>(ValueNotifier<T> notifier, T value) {
    if (notifier.value == value) return;
    notifier.value = value;
  }

  static bool _isValidLatLng(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90.0 &&
        point.latitude <= 90.0 &&
        point.longitude >= -180.0 &&
        point.longitude <= 180.0;
  }

  static double _safeSpeed(double value) {
    if (!value.isFinite || value < 0.0) return 0.0;
    return value;
  }

  static double _normalizeDegrees(double degrees) {
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
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.1,
              colors: <Color>[
                Color(0xFF211A0A),
                Color(0xFF080808),
                Color(0xFF000000),
              ],
              stops: <double>[0.0, 0.46, 1.0],
            ),
          ),
          child: Column(
            children: <Widget>[
              _Header(
                compassNotifier: _deviceCompassNotifier,
                weatherNotifier: _weatherNotifier,
                trackingNotifier: _trackingNotifier,
                tickNotifier: _tickNotifier,
                settings: _settings,
              ),
              Expanded(
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  slivers: <Widget>[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Column(
                          children: <Widget>[
                            const SizedBox(height: 4),
                            _SpeedometerSection(
                              speedNotifier: _speedNotifier,
                              trackingNotifier: _trackingNotifier,
                              settings: _settings,
                            ),
                            const SizedBox(height: 10),
                            _StatusRow(
                              signalNotifier: _signalNotifier,
                              batteryNotifier: _batteryNotifier,
                            ),
                            const SizedBox(height: 18),
                            _GridDashboard(
                              tickNotifier: _tickNotifier,
                              positionNotifier: _positionNotifier,
                              weatherNotifier: _weatherNotifier,
                              loadingNotifier: _weatherLoadingNotifier,
                              maxSpeedNotifier: _maxSpeedNotifier,
                              settings: _settings,
                              gps: _gps,
                              mapController: _mapController,
                              polylineCount: () => _polylinePointCount,
                              onMapReady: _markMapReady,
                              onMapTap: _openMap,
                              onWeatherTap: _openFullWeather,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _BottomDock(
                trackingNotifier: _trackingNotifier,
                elapsedNotifier: _elapsedSecondsNotifier,
                onAction: _handleAction,
                onMapTap: _openMap,
                onAiTap: _openAiAssistant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.compassNotifier,
    required this.weatherNotifier,
    required this.trackingNotifier,
    required this.tickNotifier,
    required this.settings,
  });

  final ValueNotifier<double> compassNotifier;
  final ValueNotifier<WeatherData?> weatherNotifier;
  final ValueNotifier<bool> trackingNotifier;
  final ValueNotifier<int> tickNotifier;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: _GlassPanel(
          radius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              _CompassWidget(headingNotifier: compassNotifier),
              const SizedBox(width: 12),
              _TemperatureDisplay(
                weatherNotifier: weatherNotifier,
                settings: settings,
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: trackingNotifier,
                builder: (_, bool tracking, __) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: tracking
                        ? const _LivePill(key: ValueKey<String>('live'))
                        : const _IdlePill(key: ValueKey<String>('idle')),
                  );
                },
              ),
              const SizedBox(width: 10),
              _DigitalClock(tickNotifier: tickNotifier),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TEMPERATURE DISPLAY
// ─────────────────────────────────────────────────────────────────────────────

class _TemperatureDisplay extends StatelessWidget {
  const _TemperatureDisplay({
    required this.weatherNotifier,
    required this.settings,
  });

  final ValueNotifier<WeatherData?> weatherNotifier;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: weatherNotifier,
      builder: (_, WeatherData? weather, __) {
        final bool metric = settings.useKmh;
        final String value;
        final String unit;

        if (weather == null) {
          value = '--';
          unit = metric ? '°C' : '°F';
        } else {
          final double celsius = weather.temperature;
          final double temp = metric ? celsius : (celsius * 9.0 / 5.0) + 32.0;
          value = temp.isFinite ? temp.round().toString() : '--';
          unit = metric ? '°C' : '°F';
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: -0.5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1, left: 2),
              child: Text(
                unit,
                style: const TextStyle(
                  color: _kGoldSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIGITAL CLOCK
// ─────────────────────────────────────────────────────────────────────────────

class _DigitalClock extends StatelessWidget {
  const _DigitalClock({
    required this.tickNotifier,
  });

  final ValueNotifier<int> tickNotifier;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tickNotifier,
      builder: (_, __, ___) {
        final DateTime now = DateTime.now();
        final String h = now.hour.toString().padLeft(2, '0');
        final String m = now.minute.toString().padLeft(2, '0');

        return Text(
          '$h:$m',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPEEDOMETER SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedometerSection extends StatelessWidget {
  const _SpeedometerSection({
    required this.speedNotifier,
    required this.trackingNotifier,
    required this.settings,
  });

  final ValueNotifier<double> speedNotifier;
  final ValueNotifier<bool> trackingNotifier;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: trackingNotifier,
        builder: (_, bool tracking, __) {
          return ValueListenableBuilder<double>(
            valueListenable: speedNotifier,
            builder: (_, double speed, __) {
              final bool isOver = tracking && speed > settings.speedAlertMph;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _GlassPanel(
                  radius: 32,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
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

// ─────────────────────────────────────────────────────────────────────────────
// STATUS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.signalNotifier,
    required this.batteryNotifier,
  });

  final ValueNotifier<int> signalNotifier;
  final ValueNotifier<int?> batteryNotifier;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: signalNotifier,
              builder: (_, int strength, __) {
                final int safeStrength = strength.clamp(0, 4);

                return _StatusChip(
                  label: 'GPS SIGNAL',
                  leading: _SignalBars(strength: safeStrength),
                  value: '$safeStrength/4',
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder<int?>(
              valueListenable: batteryNotifier,
              builder: (_, int? percent, __) {
                return _StatusChip(
                  label: 'BATTERY',
                  leading: _BatteryIcon(percent: percent),
                  value: percent == null ? '--%' : '$percent%',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.leading,
    required this.value,
  });

  final String label;
  final Widget leading;
  final String value;

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
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kTextMuted,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRID DASHBOARD
// ─────────────────────────────────────────────────────────────────────────────

class _GridDashboard extends StatelessWidget {
  const _GridDashboard({
    required this.tickNotifier,
    required this.positionNotifier,
    required this.weatherNotifier,
    required this.loadingNotifier,
    required this.maxSpeedNotifier,
    required this.settings,
    required this.gps,
    required this.mapController,
    required this.polylineCount,
    required this.onMapReady,
    required this.onMapTap,
    required this.onWeatherTap,
  });

  final ValueNotifier<int> tickNotifier;
  final ValueNotifier<LatLng?> positionNotifier;
  final ValueNotifier<WeatherData?> weatherNotifier;
  final ValueNotifier<bool> loadingNotifier;
  final ValueNotifier<double> maxSpeedNotifier;
  final SettingsService settings;
  final GpsService gps;
  final fm.MapController mapController;
  final int Function() polylineCount;
  final VoidCallback onMapReady;
  final VoidCallback onMapTap;
  final VoidCallback onWeatherTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: <Widget>[
          ValueListenableBuilder<int>(
            valueListenable: tickNotifier,
            builder: (_, __, ___) {
              final double distance = settings.toDisplayDistance(
                gps.currentDistanceMiles,
              );
              final double averageSpeed = settings.toDisplaySpeed(
                gps.currentAvgSpeedMph,
              );

              return Row(
                children: <Widget>[
                  Expanded(
                    child: _StatCard(
                      label: 'DISTANCE',
                      value: _safeNumber(distance),
                      unit: settings.distanceUnit,
                      isDecimal: true,
                      icon: CupertinoIcons.location_fill,
                      accent: _kGold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'AVG SPEED',
                      value: _safeNumber(averageSpeed),
                      unit: settings.speedUnit,
                      isDecimal: false,
                      icon: CupertinoIcons.speedometer,
                      accent: _kTeal,
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
                  valueListenable: maxSpeedNotifier,
                  builder: (_, double maxSpeedMph, __) {
                    return _StatCard(
                      label: 'MAX SPEED',
                      value: _safeNumber(settings.toDisplaySpeed(maxSpeedMph)),
                      unit: settings.speedUnit,
                      isDecimal: false,
                      icon: CupertinoIcons.bolt_fill,
                      accent: _kGoldSoft,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickNotifier,
                  builder: (_, __, ___) {
                    final Duration moving = _safeMovingTime(
                      gps.currentTripTime,
                      gps.currentStoppedTime,
                    );

                    return _StatCard(
                      label: 'MOVING TIME',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.timer_fill,
                      accent: _kTeal,
                      overrideText: _formatDuration(moving),
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
                  valueListenable: tickNotifier,
                  builder: (_, __, ___) {
                    return _StatCard(
                      label: 'STOPPED',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.pause_fill,
                      accent: _kRed,
                      overrideText: _formatDuration(gps.currentStoppedTime),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: tickNotifier,
                  builder: (_, __, ___) {
                    return _StatCard(
                      label: 'TOTAL TIME',
                      value: 0.0,
                      unit: '',
                      isDecimal: false,
                      icon: CupertinoIcons.clock_fill,
                      accent: _kGold,
                      overrideText: _formatDuration(gps.currentTripTime),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 178,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _MapThumbnail(
                    positionNotifier: positionNotifier,
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
                          weatherNotifier: weatherNotifier,
                          loadingNotifier: loadingNotifier,
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

  static double _safeNumber(double value) {
    if (!value.isFinite || value < 0.0) return 0.0;
    return value;
  }

  static Duration _safeMovingTime(Duration total, Duration stopped) {
    final Duration moving = total - stopped;
    return moving.isNegative ? Duration.zero : moving;
  }

  static String _formatDuration(Duration duration) {
    final int safeSeconds = math.max(0, duration.inSeconds);
    final int h = safeSeconds ~/ 3600;
    final String m = ((safeSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final String s = (safeSeconds % 60).toString().padLeft(2, '0');

    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────

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

    if (widget.overrideText != null) {
      _previousValue = widget.value;
      return;
    }

    if (oldWidget.overrideText != null) {
      _previousValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double begin = _previousValue;
    final Color accent = widget.accent ?? _kGold;

    return _GlassPanel(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Icon(
                  widget.icon,
                  size: 14,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                ? Text(
                    widget.overrideText!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      fontFeatures: const <ui.FontFeature>[
                        ui.FontFeature.tabularFigures(),
                      ],
                      shadows: <Shadow>[
                        Shadow(
                          color: accent.withValues(alpha: 0.25),
                          blurRadius: 12,
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
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        onEnd: () {
                          _previousValue = widget.value;
                        },
                        builder: (_, double value, __) {
                          return Text(
                            widget.isDecimal
                                ? value.toStringAsFixed(1)
                                : value.round().toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 31,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                              fontFeatures: const <ui.FontFeature>[
                                ui.FontFeature.tabularFigures(),
                              ],
                              shadows: <Shadow>[
                                Shadow(
                                  color: accent.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (widget.unit.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 5),
                        Text(
                          widget.unit,
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

// ─────────────────────────────────────────────────────────────────────────────
// MAP THUMBNAIL
// ─────────────────────────────────────────────────────────────────────────────

class _MapThumbnail extends StatefulWidget {
  const _MapThumbnail({
    required this.positionNotifier,
    required this.mapController,
    required this.gps,
    required this.polylineCount,
    required this.onMapReady,
    required this.onTap,
  });

  final ValueNotifier<LatLng?> positionNotifier;
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
  LatLng? _cachedLastPoint;

  List<LatLng> _getSmoothedPolyline() {
    final int currentCount = widget.polylineCount();
    final LatLng? currentLast = widget.positionNotifier.value;

    if (currentCount == _cachedCount && currentLast == _cachedLastPoint) {
      return _cachedSmooth;
    }

    final List<LatLng> raw = widget.gps.currentPoints
        .map((TripPoint point) => point.position)
        .where(_isValidPoint)
        .toList(growable: false);

    _cachedCount = currentCount;
    _cachedLastPoint = currentLast;

    if (raw.length < 2) {
      _cachedSmooth = const <LatLng>[];
      return _cachedSmooth;
    }

    final List<LatLng> simplified = simplifyPolyline(
      raw,
      epsilon: 0.00004,
    );

    final List<LatLng> smoothed = smoothPolyline(
      simplified,
      tension: 0.5,
      subdivisions: 8,
    );

    final List<LatLng> validPoints = <LatLng>[];

    for (final LatLng point in smoothed) {
      if (!_isValidPoint(point)) continue;

      if (validPoints.isEmpty ||
          validPoints.last.latitude != point.latitude ||
          validPoints.last.longitude != point.longitude) {
        validPoints.add(point);
      }
    }

    _cachedSmooth = List<LatLng>.unmodifiable(validPoints);
    return _cachedSmooth;
  }

  static bool _isValidPoint(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90.0 &&
        point.latitude <= 90.0 &&
        point.longitude >= -180.0 &&
        point.longitude <= 180.0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
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
                      initialCenter:
                          widget.positionNotifier.value ?? _kDefaultMapCenter,
                      initialZoom: _kDefaultMapZoom,
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
                        tileBuilder: (_, Widget tileWidget, __) {
                          return ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              Colors.black.withValues(alpha: 0.25),
                              BlendMode.darken,
                            ),
                            child: tileWidget,
                          );
                        },
                      ),
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: widget.positionNotifier,
                        builder: (_, __, ___) {
                          final List<LatLng> smooth = _getSmoothedPolyline();

                          if (smooth.length < 2) {
                            return const SizedBox.shrink();
                          }

                          return fm.PolylineLayer(
                            polylines: <fm.Polyline>[
                              fm.Polyline(
                                points: smooth,
                                color: _kGoldSoft,
                                strokeWidth: 4.0,
                                strokeCap: StrokeCap.round,
                                strokeJoin: StrokeJoin.round,
                              ),
                            ],
                          );
                        },
                      ),
                      ValueListenableBuilder<LatLng?>(
                        valueListenable: widget.positionNotifier,
                        builder: (_, LatLng? position, __) {
                          if (position == null || !_isValidPoint(position)) {
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
                  child: _SmallOverlayLabel(
                    icon: CupertinoIcons.map_fill,
                    label: 'LIVE MAP',
                  ),
                ),
                const Positioned(
                  top: 12,
                  right: 12,
                  child: _MapExpandIcon(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEATHER THUMBNAIL
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherThumbnail extends StatelessWidget {
  const _WeatherThumbnail({
    required this.weatherNotifier,
    required this.loadingNotifier,
    required this.onTap,
  });

  final ValueNotifier<WeatherData?> weatherNotifier;
  final ValueNotifier<bool> loadingNotifier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
                    valueListenable: weatherNotifier,
                    builder: (_, WeatherData? weather, __) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: loadingNotifier,
                        builder: (_, bool loading, __) {
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 300,
                              height: 210,
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
                  child: _SmallOverlayLabel(
                    icon: CupertinoIcons.cloud_sun_fill,
                    label: 'WEATHER',
                  ),
                ),
                const Positioned(
                  top: 12,
                  right: 12,
                  child: _MapExpandIcon(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEATHER SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherSheet extends StatelessWidget {
  const _WeatherSheet({
    required this.weatherNotifier,
    required this.loadingNotifier,
    required this.onRetry,
  });

  final ValueNotifier<WeatherData?> weatherNotifier;
  final ValueNotifier<bool> loadingNotifier;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 70),
      decoration: const BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 14),
              height: 4,
              width: 44,
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
                    color: _kGoldSoft,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'LIVE WEATHER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: _kCardBorder, thickness: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 38),
              child: ValueListenableBuilder<WeatherData?>(
                valueListenable: weatherNotifier,
                builder: (_, WeatherData? weather, __) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: loadingNotifier,
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

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM DOCK
// ─────────────────────────────────────────────────────────────────────────────

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.trackingNotifier,
    required this.elapsedNotifier,
    required this.onAction,
    required this.onMapTap,
    required this.onAiTap,
  });

  final ValueNotifier<bool> trackingNotifier;
  final ValueNotifier<int> elapsedNotifier;
  final VoidCallback onAction;
  final VoidCallback onMapTap;
  final VoidCallback onAiTap;

  @override
  Widget build(BuildContext context) {
    final double bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: _kCard.withValues(alpha: 0.88),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            bottomPad > 0 ? bottomPad + 8 : 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SecondaryBtn(
                      icon: CupertinoIcons.map_fill,
                      label: 'FULL MAP',
                      onTap: onMapTap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SecondaryBtn(
                      icon: Icons.auto_awesome_rounded,
                      label: 'ASK AI',
                      onTap: onAiTap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<bool>(
                valueListenable: trackingNotifier,
                builder: (_, bool tracking, __) {
                  return _PrimaryActionButton(
                    isTracking: tracking,
                    onTap: onAction,
                    timerNotifier: elapsedNotifier,
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

// ─────────────────────────────────────────────────────────────────────────────
// SHARED UI HELPERS
// ─────────────────────────────────────────────────────────────────────────────

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
            Colors.white.withValues(alpha: 0.045),
            Colors.white.withValues(alpha: 0.025),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SmallOverlayLabel extends StatelessWidget {
  const _SmallOverlayLabel({
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
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: _kGoldSoft, size: 12),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
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
        color: _kRed.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _kRed.withValues(alpha: 0.24)),
      ),
      child: const Row(
        children: <Widget>[
          _LiveDot(),
          SizedBox(width: 7),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
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
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Center(
        child: Text(
          'READY',
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
        child: Icon(
          Icons.cloud_off_rounded,
          color: Colors.white.withValues(alpha: 0.25),
          size: 32,
        ),
      ),
    );
  }
}

class _MapExpandIcon extends StatelessWidget {
  const _MapExpandIcon();

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
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: const Icon(
            CupertinoIcons.fullscreen,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPASS WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class _CompassWidget extends StatefulWidget {
  const _CompassWidget({
    required this.headingNotifier,
  });

  final ValueNotifier<double> headingNotifier;

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
      valueListenable: widget.headingNotifier,
      builder: (_, double unwrapped, __) {
        final double deg = unwrapped % 360.0;
        final double normal = deg < 0.0 ? deg + 360.0 : deg;
        final String label = _cardinal(normal);
        final double targetRad = unwrapped * (math.pi / 180.0);
        final double beginRad = _previousRad;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: beginRad,
            end: targetRad,
          ),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          onEnd: () {
            _previousRad = targetRad;
          },
          builder: (_, double rad, __) {
            return Row(
              children: <Widget>[
                RepaintBoundary(
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.32),
                            border: Border.all(color: Colors.white12),
                          ),
                        ),
                        const CustomPaint(
                          size: Size(38, 38),
                          painter: _kNeedlePainter,
                        ),
                        Transform.rotate(
                          angle: rad,
                          child: CustomPaint(
                            size: const Size(38, 38),
                            painter: _kNeedlePainter,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
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
    final double radius = size.width / 2.0 - 4.0;

    final Paint paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;

    for (int i = 0; i < 12; i++) {
      final double rad = i * 30.0 * (math.pi / 180.0) - math.pi / 2.0;

      final Offset outer = center +
          Offset(
            math.cos(rad) * radius,
            math.sin(rad) * radius,
          );

      final Offset inner = center +
          Offset(
            math.cos(rad) * (radius - 3.0),
            math.sin(rad) * (radius - 3.0),
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

    final Paint northPaint = Paint()
      ..color = _kRed
      ..style = PaintingStyle.fill;

    final Paint southPaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.fill;

    canvas.drawPath(
      ui.Path()
        ..moveTo(center.dx, center.dy - 11.0)
        ..lineTo(center.dx - 3.0, center.dy)
        ..lineTo(center.dx + 3.0, center.dy)
        ..close(),
      northPaint,
    );

    canvas.drawPath(
      ui.Path()
        ..moveTo(center.dx, center.dy + 11.0)
        ..lineTo(center.dx - 3.0, center.dy)
        ..lineTo(center.dx + 3.0, center.dy)
        ..close(),
      southPaint,
    );

    canvas.drawCircle(
      center,
      2.0,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// SIGNAL / BATTERY
// ─────────────────────────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  const _SignalBars({
    required this.strength,
  });

  final int strength;

  @override
  Widget build(BuildContext context) {
    final int safeStrength = strength.clamp(0, 4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List<Widget>.generate(4, (int i) {
        final bool active = i < safeStrength;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 4,
          height: 9.0 + i * 4.0,
          decoration: BoxDecoration(
            color: active ? _kTeal : Colors.white12,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

class _BatteryIcon extends StatelessWidget {
  const _BatteryIcon({
    required this.percent,
  });

  final int? percent;

  Color get _color {
    final int? value = percent;

    if (value == null) return Colors.white38;
    if (value > 40) return _kTeal;
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

// ─────────────────────────────────────────────────────────────────────────────
// LIVE DOT / MARKER
// ─────────────────────────────────────────────────────────────────────────────

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
      duration: const Duration(seconds: 1),
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
            color: _kRed.withValues(alpha: 0.45 + _animation.value * 0.55),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _kRed.withValues(alpha: 0.35),
                blurRadius: 8 + _animation.value * 10,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveMarker extends StatelessWidget {
  const _LiveMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 21,
      height: 21,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kTeal,
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _kTeal.withValues(alpha: 0.55),
            blurRadius: 16,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUTTONS
// ─────────────────────────────────────────────────────────────────────────────

class _SecondaryBtn extends StatefulWidget {
  const _SecondaryBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SecondaryBtn> createState() => _SecondaryBtnState();
}

class _SecondaryBtnState extends State<_SecondaryBtn> {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 50,
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(widget.icon, color: _kGoldSoft, size: 17),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
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
    final int h = safeSeconds ~/ 3600;
    final String m = ((safeSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final String s = (safeSeconds % 60).toString().padLeft(2, '0');

    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor = widget.isTracking ? _kRed : _kTeal;
    final Color textColor = widget.isTracking ? Colors.white : Colors.black;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: 63,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _pressed
                ? <Color>[
                    mainColor.withValues(alpha: 0.74),
                    mainColor.withValues(alpha: 0.58),
                  ]
                : <Color>[
                    mainColor,
                    mainColor.withValues(alpha: 0.78),
                  ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: mainColor.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: widget.isTracking
                ? ValueListenableBuilder<int>(
                    key: const ValueKey<String>('tracking'),
                    valueListenable: widget.timerNotifier,
                    builder: (_, int seconds, __) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            CupertinoIcons.stop_fill,
                            color: Colors.white,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatSeconds(seconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              letterSpacing: 1.5,
                              fontFeatures: <ui.FontFeature>[
                                ui.FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : Row(
                    key: const ValueKey<String>('stopped'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        CupertinoIcons.play_fill,
                        color: textColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'START TRACKING',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                          fontSize: 16,
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
