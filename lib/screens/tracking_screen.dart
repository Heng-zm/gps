import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;

import '../services/services.dart';
import '../models/trip_data.dart';
import '../models/weather_data.dart';
import '../utils/smooth_polyline.dart';
import '../widgets/speedometer_widget.dart';
import '../widgets/weather_widget.dart';
import '../widgets/ai_chat_sheet.dart';
import 'map_screen.dart';
import 'summary_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
const _kGold = Color(0xFFD4A843);
const _kGoldBright = Color(0xFFEDD068);
const _kPurple = Color(0xFFA855F7);
const _kRed = Color(0xFFE74C3C);
const _kTeal = Color(0xFF4ECDC4);
const _kBg = Color(0xFF070707);
const _kCard = Color(0xFF111111);
const _kCardBorder = Color(0xFF1E1E1E);

// ─────────────────────────────────────────────────────────────────────────────
// SINGLETON PAINTERS (avoids re-instantiation on every build)
// ─────────────────────────────────────────────────────────────────────────────
const _kCompassRingPainter = _CompassRingPainter();
const _kNeedlePainter = _NeedlePainter();

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin {
  // ── Services ───────────────────────────────────────────────────────────────
  final GpsService _gps = GpsService.instance;
  final WeatherService _weather = WeatherService.instance;
  final SettingsService _settings = SettingsService.instance;

  // ── High-Performance Notifiers ─────────────────────────────────────────────
  final ValueNotifier<int> _tickNotifier = ValueNotifier(0);
  final ValueNotifier<double> _speedNotifier = ValueNotifier(0.0);

  // COMPASS FIX: Store heading as an unwrapped (cumulative) angle to avoid
  // the 0°/360° shortest-path wrap-around bug during animation.
  final ValueNotifier<double> _headingNotifier = ValueNotifier(0.0);

  final ValueNotifier<int> _signalNotifier = ValueNotifier(0);
  final ValueNotifier<bool> _trackingNotifier = ValueNotifier(false);
  final ValueNotifier<WeatherData?> _weatherNotifier = ValueNotifier(null);
  final ValueNotifier<LatLng?> _positionNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _weatherLoadingNotifier = ValueNotifier(false);

  // FIX: Track polyline point count to avoid redundant polyline rebuilds.
  int _lastPolylinePointCount = 0;

  // FIX: Guard map interactions until the map controller is fully initialised.
  bool _mapReady = false;

  final ScrollController _scrollController = ScrollController();
  final fm.MapController _mapController = fm.MapController();
  StreamSubscription<TripPoint>? _pointSub;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);

    if (_gps.currentPoints.isNotEmpty) {
      _positionNotifier.value = _gps.currentPoints.last.position;
    }

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _tickNotifier.value++;
    });

    _trackingNotifier.value = _gps.isTracking;
    if (_gps.isTracking) _attachGpsStream();
    _fetchWeather();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    _tickTimer?.cancel();
    _pointSub?.cancel();
    _tickNotifier.dispose();
    _speedNotifier.dispose();
    _headingNotifier.dispose();
    _signalNotifier.dispose();
    _trackingNotifier.dispose();
    _weatherNotifier.dispose();
    _positionNotifier.dispose();
    // FIX: was missing from original dispose(), causing a memory leak.
    _weatherLoadingNotifier.dispose();
    try {
      _mapController.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _attachGpsStream() {
    _pointSub?.cancel();
    _pointSub = _gps.pointStream?.listen((point) {
      if (!mounted) return;
      _speedNotifier.value = point.speedMph;
      _positionNotifier.value = point.position;

      if (point.speedMph > 2.0 && _gps.currentPoints.length >= 2) {
        final pts = _gps.currentPoints;
        final rawBearing = const Distance()
            .bearing(pts[pts.length - 2].position, pts.last.position);

        // COMPASS FIX: Compute the shortest angular delta from the previous
        // heading so the notifier value never "jumps" across the 0/360 seam.
        final normalised = rawBearing % 360;
        final prev = _headingNotifier.value % 360;
        double delta = normalised - prev;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        _headingNotifier.value = _headingNotifier.value + delta;
      }

      final accuracy = point.accuracyMeters.clamp(5.0, 40.0);
      _signalNotifier.value =
          ((40.0 - accuracy) / 35.0 * 4).round().clamp(0, 4);

      // FIX: Only interact with _mapController after the map is ready.
      if (_mapReady) {
        try {
          _mapController.move(point.position, _mapController.camera.zoom);
          if (point.speedMph > 2.0) {
            _mapController.rotate(-(_headingNotifier.value % 360));
          }
        } catch (_) {}
      }
    });
  }

  Future<void> _fetchWeather() async {
    if (!_settings.showWeather || _weatherLoadingNotifier.value) return;
    _weatherLoadingNotifier.value = true;
    try {
      final pos = await _gps.getCurrentLocation();
      if (pos != null && mounted) {
        final data = await _weather.fetchWeather(pos.latitude, pos.longitude);
        if (mounted) _weatherNotifier.value = data;
      }
    } catch (e) {
      debugPrint('Weather fetch failed: $e');
    } finally {
      if (mounted) _weatherLoadingNotifier.value = false;
    }
  }

  Future<void> _handleAction() async {
    if (_trackingNotifier.value) {
      HapticFeedback.heavyImpact();
      final summary = _gps.stopTracking();
      await _pointSub?.cancel();
      _pointSub = null;
      _trackingNotifier.value = false;
      _speedNotifier.value = 0;
      _headingNotifier.value = 0;
      _lastPolylinePointCount = 0;

      if (_mapReady) {
        try {
          _mapController.rotate(0);
        } catch (_) {}
      }

      if (summary != null && mounted) {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => SummaryScreen(summary: summary),
          ),
        );
      }
    } else {
      HapticFeedback.mediumImpact();
      await _gps.startTracking();

      if (!mounted) return;

      if (_gps.isTracking) {
        _attachGpsStream();
        _trackingNotifier.value = true;
      } else {
        _promptGPS();
      }
    }
  }

  void _promptGPS() {
    showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('GPS Access Required'),
        content: const Text(
            'Enable high-accuracy location tracking to monitor your trip and live speed.'),
        actions: [
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
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      top: false,
                      bottom: true,
                      child: Column(
                        children: [
                          SizedBox(
                              height: MediaQuery.of(context).padding.top + 80),
                          _buildSpeedometerSection(),
                          _buildSignalRow(),
                          const SizedBox(height: 12),
                          _buildStatsGrid(),
                          const SizedBox(height: 16),
                          _buildMapPreview(),
                          const SizedBox(height: 16),
                          if (_settings.showWeather) _buildWeatherCard(),
                          const SizedBox(height: 25),
                          _buildControlPill(),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 10,
            bottom: 15,
            left: 20,
            right: 20,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              _CompassWidget(headingNotifier: _headingNotifier),
              const SizedBox(width: 15),
              _buildHeaderTemp(),
              const Spacer(),
              _buildDigitalClock(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderTemp() {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: _weatherNotifier,
      builder: (_, w, __) {
        // WeatherService returns °F — convert to °C for display.
        final double? tempC = w != null ? (w.temperature - 32) * 5 / 9 : null;
        final tempStr = tempC != null ? '${tempC.toInt()}' : '--';
        const unitLabel = '°C';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tempStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                unitLabel,
                style: const TextStyle(
                  color: _kRed,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDigitalClock() {
    return ValueListenableBuilder<int>(
      valueListenable: _tickNotifier,
      builder: (_, __, ___) {
        final now = DateTime.now();
        final h = now.hour.toString().padLeft(2, '0');
        final m = now.minute.toString().padLeft(2, '0');
        return Text(
          '$h:$m',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }

  Widget _buildSpeedometerSection() {
    return ValueListenableBuilder<double>(
      valueListenable: _speedNotifier,
      builder: (context, speed, _) {
        final isOver =
            _trackingNotifier.value && speed > _settings.speedAlertMph;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SpeedometerWidget(speedMph: speed, isOverLimit: isOver),
        );
      },
    );
  }

  Widget _buildSignalRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _signalNotifier,
                builder: (_, strength, __) => _SignalBars(strength: strength),
              ),
              const SizedBox(height: 5),
              Text(
                'GPS SIGNAL',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const _BatteryIndicator(),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return ValueListenableBuilder<int>(
      valueListenable: _tickNotifier,
      builder: (context, _, __) {
        final dist = _settings.toDisplayDistance(_gps.currentDistanceMiles);
        final avg = _settings.toDisplaySpeed(_gps.currentAvgSpeedMph);
        final distUnit = _settings.distanceUnit;
        final speedUnit = _settings.speedUnit;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _StatBox(
                label: 'DISTANCE',
                value: dist,
                isDecimal: true,
                unit: distUnit,
                color: _kTeal,
              ),
              const SizedBox(width: 15),
              _StatBox(
                label: 'AVG SPEED',
                value: avg,
                isDecimal: false,
                unit: speedUnit,
                color: _kGold,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapPreview() {
    return GestureDetector(
      onTap: _openMap,
      child: Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              AbsorbPointer(
                child: fm.FlutterMap(
                  mapController: _mapController,
                  options: fm.MapOptions(
                    initialCenter: _positionNotifier.value ??
                        const LatLng(11.5564, 104.9282),
                    initialZoom: 16,
                    interactionOptions: const fm.InteractionOptions(
                      flags: fm.InteractiveFlag.none,
                    ),
                    // FIX: Mark map as ready before allowing controller calls.
                    onMapReady: () => _mapReady = true,
                  ),
                  children: [
                    fm.TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.example.app',
                    ),
                    // FIX: Only rebuild polyline when point count changes, not
                    // on every position update.
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: _positionNotifier,
                      builder: (context, pos, _) {
                        final raw =
                            _gps.currentPoints.map((p) => p.position).toList();
                        if (raw.length < 2) return const SizedBox.shrink();

                        // Skip expensive simplify/smooth when no new points.
                        if (raw.length == _lastPolylinePointCount &&
                            _lastPolylinePointCount > 0) {
                          // Still need to return something valid; use cached
                          // via the existing polyline layer (no-op rebuild).
                          return const SizedBox.shrink();
                        }
                        _lastPolylinePointCount = raw.length;

                        final simplified =
                            simplifyPolyline(raw, epsilon: 0.00004);
                        final smooth = smoothPolyline(simplified,
                            tension: 0.5, subdivisions: 8);
                        return fm.PolylineLayer(
                          polylines: [
                            fm.Polyline(
                              points: smooth,
                              color: _kGold.withValues(alpha: 0.22),
                              strokeWidth: 8,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                            fm.Polyline(
                              points: smooth,
                              color: _kGold,
                              strokeWidth: 3.5,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                          ],
                        );
                      },
                    ),
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: _positionNotifier,
                      builder: (context, pos, _) {
                        if (pos == null) return const SizedBox.shrink();
                        return fm.MarkerLayer(
                          markers: [
                            fm.Marker(
                              point: pos,
                              width: 80,
                              height: 80,
                              alignment: Alignment.center,
                              child: const _PulsingLiveMarker(),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 10,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.fullscreen,
                          size: 11, color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(
                        'EXPAND',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: _weatherNotifier,
      builder: (_, w, __) => ValueListenableBuilder<bool>(
        valueListenable: _weatherLoadingNotifier,
        builder: (_, loading, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: WeatherWidget(
            weather: w,
            isLoading: loading && w == null,
            onRetry: _fetchWeather,
          ),
        ),
      ),
    );
  }

  Widget _buildControlPill() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _SquareActionBtn(
            icon: CupertinoIcons.map_fill,
            label: 'MAP',
            color: _kTeal,
            onTap: _openMap,
          ),
          const SizedBox(width: 12),
          _SquareActionBtn(
            icon: Icons.auto_awesome_rounded,
            label: 'AI',
            color: _kPurple,
            onTap: _openAiAssistant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _trackingNotifier,
              builder: (_, tracking, __) => _BreathingButton(
                isTracking: tracking,
                onTap: _handleAction,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openMap() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => MapScreen(
          points: _gps.currentPoints,
          isLive: _trackingNotifier.value,
        ),
      ),
    );
  }

  void _openAiAssistant() {
    HapticFeedback.lightImpact();
    final snap = TripSummary(
      id: 'live_${DateTime.now().millisecondsSinceEpoch}',
      date: DateTime.now(),
      totalTime: _gps.currentTripTime,
      stoppedTime: _gps.currentStoppedTime,
      movingTime: _gps.currentTripTime - _gps.currentStoppedTime,
      maxSpeedMph: _gps.currentMaxSpeedMph,
      avgSpeedMph: _gps.currentAvgSpeedMph,
      altitudeGainFt: 0,
      maxAltitudeFt: 0,
      minAltitudeFt: 0,
      distanceMiles: _gps.currentDistanceMiles,
      points: List.unmodifiable(_gps.currentPoints),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => AiChatSheet(summary: snap),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPASS WIDGET
// ─────────────────────────────────────────────────────────────────────────────

/// A self-contained compass that:
/// - Reads an *unwrapped* heading from [headingNotifier] (may exceed 360 or
///   go negative) so animation never takes the long way round the dial.
/// - Uses [TweenAnimationBuilder] with a properly tracked `begin` for smooth
///   interpolation between heading updates.
/// - Derives the cardinal label (N / NE / E … NW) from the normalised angle.
/// - Rotates the *ring* of tick-marks; the gold North needle stays fixed.
class _CompassWidget extends StatefulWidget {
  final ValueNotifier<double> headingNotifier;

  const _CompassWidget({required this.headingNotifier});

  @override
  State<_CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<_CompassWidget> {
  // FIX: Track the previous animated value so TweenAnimationBuilder always
  // animates FROM the last rendered angle rather than from an arbitrary start.
  double _previousRad = 0.0;

  static const List<_CardinalMark> _cardinals = [
    _CardinalMark(label: 'N', angle: 0),
    _CardinalMark(label: 'NE', angle: 45),
    _CardinalMark(label: 'E', angle: 90),
    _CardinalMark(label: 'SE', angle: 135),
    _CardinalMark(label: 'S', angle: 180),
    _CardinalMark(label: 'SW', angle: 225),
    _CardinalMark(label: 'W', angle: 270),
    _CardinalMark(label: 'NW', angle: 315),
  ];

  static String _cardinalLabel(double deg) {
    final int index = ((deg + 22.5) / 45).floor() % 8;
    return _cardinals[index].label;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.headingNotifier,
      builder: (_, unwrappedHeading, __) {
        final double displayDeg = unwrappedHeading % 360;
        final double normalised =
            displayDeg < 0 ? displayDeg + 360 : displayDeg;
        final String label = _cardinalLabel(normalised);

        final double targetRad = unwrappedHeading * (math.pi / 180);
        // FIX: Capture begin BEFORE updating _previousRad so the tween
        // animates from the last known position.
        final double beginRad = _previousRad;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: beginRad, end: targetRad),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          onEnd: () => _previousRad = targetRad,
          builder: (_, animRad, __) {
            return SizedBox(
              width: 50,
              height: 56,
              child: Column(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer bezel
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFF252525), Color(0xFF111111)],
                            ),
                            border: Border.all(
                              color: _kGold.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _kGold.withValues(alpha: 0.18),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),

                        // Rotating tick ring — uses singleton painter.
                        Transform.rotate(
                          angle: -animRad,
                          child: CustomPaint(
                            size: const Size(44, 44),
                            painter: _kCompassRingPainter,
                          ),
                        ),

                        // Static gold North needle — uses singleton painter.
                        CustomPaint(
                          size: const Size(44, 44),
                          painter: _kNeedlePainter,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: _kGoldBright,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      height: 1.0,
                      shadows: [
                        Shadow(
                          color: _kGold.withValues(alpha: 0.6),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Paints the rotating compass ring: 8 major tick-marks and 16 minor ticks.
class _CompassRingPainter extends CustomPainter {
  const _CompassRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    final majorPaint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final minorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 24; i++) {
      final double angleDeg = i * 15.0;
      final double rad = angleDeg * (math.pi / 180) - math.pi / 2;
      final bool isMajor = i % 3 == 0;
      final bool isNorth = i == 0;

      if (isMajor) {
        final double tickLen = isNorth ? 7.0 : 5.0;
        majorPaint.color =
            isNorth ? _kGoldBright : Colors.white.withValues(alpha: 0.55);
        final Offset outer =
            center + Offset(math.cos(rad) * radius, math.sin(rad) * radius);
        final Offset inner = center +
            Offset(math.cos(rad) * (radius - tickLen),
                math.sin(rad) * (radius - tickLen));
        canvas.drawLine(inner, outer, majorPaint);
      } else {
        final Offset outer =
            center + Offset(math.cos(rad) * radius, math.sin(rad) * radius);
        final Offset inner = center +
            Offset(math.cos(rad) * (radius - 3), math.sin(rad) * (radius - 3));
        canvas.drawLine(inner, outer, minorPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_CompassRingPainter old) => false;
}

class _NeedlePainter extends CustomPainter {
  const _NeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final northPaint = Paint()
      ..color = _kGoldBright
      ..style = PaintingStyle.fill;
    final northShadow = Paint()
      ..color = _kGold.withValues(alpha: 0.55)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);

    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - 13)
      ..lineTo(center.dx - 3, center.dy)
      ..lineTo(center.dx + 3, center.dy)
      ..close();

    final southPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final southPath = ui.Path()
      ..moveTo(center.dx, center.dy + 13)
      ..lineTo(center.dx - 3, center.dy)
      ..lineTo(center.dx + 3, center.dy)
      ..close();

    final pivotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(northPath, northShadow);
    canvas.drawPath(southPath, southPaint);
    canvas.drawPath(northPath, northPaint);
    canvas.drawCircle(center, 2.5, pivotPaint);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => false;
}

class _CardinalMark {
  final String label;
  final double angle;
  const _CardinalMark({required this.label, required this.angle});
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPPORTING WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  final int strength;
  const _SignalBars({required this.strength});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final isActive = index < strength;
        final Color activeColor = index >= 3
            ? _kTeal
            : index == 2
                ? _kGold
                : _kGold.withValues(alpha: 0.7);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 4,
          height: 8.0 + (index * 3.5),
          decoration: BoxDecoration(
            color:
                isActive ? activeColor : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(2),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.45),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  const _BatteryIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(CupertinoIcons.battery_100, size: 20, color: _kTeal),
        const SizedBox(height: 5),
        Text(
          'POWER',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// FIX: _StatBox is now a StatefulWidget so it can track the previously
/// displayed value and pass it as `begin` to the tween, avoiding the
/// "always animates from 0" bug that occurred when the widget rebuilt.
class _StatBox extends StatefulWidget {
  final String label, unit;
  final double value;
  final Color color;
  final bool isDecimal;

  const _StatBox({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.isDecimal,
  });

  @override
  State<_StatBox> createState() => _StatBoxState();
}

class _StatBoxState extends State<_StatBox> {
  // Tracks the value from the previous build so tween begins there.
  late double _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final double beginValue = _previousValue;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kCardBorder, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white30,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                TweenAnimationBuilder<double>(
                  // FIX: begin is now the previous value, not always 0.
                  tween: Tween<double>(begin: beginValue, end: widget.value),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  onEnd: () => _previousValue = widget.value,
                  builder: (context, val, _) {
                    final displayTxt = widget.isDecimal
                        ? val.toStringAsFixed(1)
                        : val.toInt().toString();
                    return Text(
                      displayTxt,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 5),
                Text(
                  widget.unit,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SquareActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_SquareActionBtn> createState() => _SquareActionBtnState();
}

class _SquareActionBtnState extends State<_SquareActionBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 68,
          height: 64,
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kCardBorder, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _pressed ? 0.05 : 0.2),
                blurRadius: _pressed ? 4 : 10,
                offset: Offset(0, _pressed ? 2 : 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: widget.color, size: 22),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreathingButton extends StatefulWidget {
  final bool isTracking;
  final VoidCallback onTap;

  const _BreathingButton({required this.isTracking, required this.onTap});

  @override
  State<_BreathingButton> createState() => _BreathingButtonState();
}

class _BreathingButtonState extends State<_BreathingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.2, end: 0.65).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: _glowAnimation,
          builder: (context, child) {
            final isT = widget.isTracking;
            final baseColor = isT ? _kRed : _kGold;
            // FIX: Both tracking AND idle states now use _glowAnimation so
            // the START button breathes just like the STOP button.
            final shadowColor =
                baseColor.withValues(alpha: _glowAnimation.value);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isT
                      ? [const Color(0xFFE74C3C), const Color(0xFFC0392B)]
                      : [const Color(0xFFD4A843), const Color(0xFF8B6914)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: isT ? 22 : 14,
                    spreadRadius: isT ? 2 : 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    isT ? 'STOP' : 'START',
                    key: ValueKey(isT),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PulsingLiveMarker extends StatefulWidget {
  const _PulsingLiveMarker();

  @override
  State<_PulsingLiveMarker> createState() => _PulsingLiveMarkerState();
}

class _PulsingLiveMarkerState extends State<_PulsingLiveMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad),
    );
    _opacityAnimation = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad),
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
      animation: _controller,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing ring
            Container(
              width: 60 * _scaleAnimation.value,
              height: 60 * _scaleAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kRed.withValues(alpha: _opacityAnimation.value * 0.5),
                border: Border.all(
                  color: _kRed.withValues(alpha: _opacityAnimation.value * 0.8),
                  width: 1.2,
                ),
              ),
            ),
            // White dot with red border
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: _kRed.withValues(alpha: 0.8),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
                border: Border.all(color: _kRed, width: 3.5),
              ),
            ),
            // FIX: Direction chevron was at `top: 22` which placed it BELOW
            // the dot centre in an 80×80 marker. Use Align so it sits flush
            // above the dot at the visual top of the marker.
            const Positioned(
              top: 16,
              child: Icon(
                CupertinoIcons.chevron_up,
                color: Colors.white,
                size: 14,
              ),
            ),
          ],
        );
      },
    );
  }
}
