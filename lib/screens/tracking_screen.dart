import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_compass/flutter_compass.dart';

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
const _kRed = Color(0xFFFF3B30);
const _kTeal = Color(0xFF32D74B);
const _kBg = Color(0xFF000000);
const _kCard = Color(0xFF141416);
const _kCardBorder = Color(0xFF222225);

// ─────────────────────────────────────────────────────────────────────────────
// SINGLETON PAINTERS
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
  final GpsService _gps = GpsService.instance;
  final WeatherService _weather = WeatherService.instance;
  final SettingsService _settings = SettingsService.instance;

  final ValueNotifier<int> _tickNotifier = ValueNotifier(0);
  final ValueNotifier<double> _speedNotifier = ValueNotifier(0.0);

  final ValueNotifier<double> _travelHeadingNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _deviceCompassNotifier = ValueNotifier(0.0);

  final ValueNotifier<int> _signalNotifier = ValueNotifier(0);
  final ValueNotifier<bool> _trackingNotifier = ValueNotifier(false);
  final ValueNotifier<WeatherData?> _weatherNotifier = ValueNotifier(null);
  final ValueNotifier<LatLng?> _positionNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _weatherLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<int> _elapsedSecondsNotifier = ValueNotifier(0);

  int _lastPolylinePointCount = 0;
  bool _mapReady = false;

  final ScrollController _scrollController = ScrollController();
  final fm.MapController _mapController = fm.MapController();
  StreamSubscription<TripPoint>? _pointSub;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);

    if (_gps.currentPoints.isNotEmpty) {
      _positionNotifier.value = _gps.currentPoints.last.position;
    }

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _tickNotifier.value++;
        if (_trackingNotifier.value) {
          _elapsedSecondsNotifier.value++;
        }
      }
    });

    _initHardwareCompass();

    _trackingNotifier.value = _gps.isTracking;
    if (_gps.isTracking) _attachGpsStream();
    _fetchWeather();
  }

  void _initHardwareCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (event.heading != null && mounted) {
        final current = _deviceCompassNotifier.value;
        final target = event.heading!;
        double delta = (target - (current % 360));
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        _deviceCompassNotifier.value = current + delta;
      }
    });
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
    _compassSub?.cancel();
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

        final normalised = rawBearing % 360;
        final prev = _travelHeadingNotifier.value % 360;
        double delta = normalised - prev;
        if (delta > 180) delta -= 360;
        if (delta < -180) delta += 360;
        _travelHeadingNotifier.value = _travelHeadingNotifier.value + delta;
      }

      final accuracy = point.accuracyMeters.clamp(5.0, 40.0);
      _signalNotifier.value =
          ((40.0 - accuracy) / 35.0 * 4).round().clamp(0, 4);

      if (_mapReady) {
        try {
          _mapController.move(point.position, _mapController.camera.zoom);
          if (point.speedMph > 2.0) {
            _mapController.rotate(-(_travelHeadingNotifier.value % 360));
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
      _travelHeadingNotifier.value = 0;
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
      _elapsedSecondsNotifier.value = 0;
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

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Column(
          children: [
            _buildMinimalHeader(),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 30),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          _buildSpeedometerSection(),
                          _buildSignalRow(),
                          const SizedBox(height: 24),
                          _buildGridDashboard(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildAnchoredBottomDock(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // THE GRID DASHBOARD (2x2 Layout)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGridDashboard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _tickNotifier,
            builder: (context, _, __) {
              final dist =
                  _settings.toDisplayDistance(_gps.currentDistanceMiles);
              final avg = _settings.toDisplaySpeed(_gps.currentAvgSpeedMph);
              return Row(
                children: [
                  Expanded(
                    child: _WhiteStatCard(
                      label: 'DISTANCE',
                      value: dist,
                      unit: _settings.distanceUnit,
                      isDecimal: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _WhiteStatCard(
                      label: 'AVG SPEED',
                      value: avg,
                      unit: _settings.speedUnit,
                      isDecimal: false,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildSquareMap()),
                const SizedBox(width: 12),
                Expanded(
                  child: _settings.showWeather
                      ? _buildSquareWeather()
                      : Container(
                          decoration: BoxDecoration(
                            color: _kCard,
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSquareMap() {
    return GestureDetector(
      onTap: _openMap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kCardBorder, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
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
                        flags: fm.InteractiveFlag.none),
                    onMapReady: () => _mapReady = true,
                  ),
                  children: [
                    fm.TileLayer(
                      urlTemplate:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.example.app',
                      tileBuilder: (context, tileWidget, tile) {
                        return ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            Colors.black.withValues(alpha: 0.15),
                            BlendMode.darken,
                          ),
                          child: tileWidget,
                        );
                      },
                    ),
                    ValueListenableBuilder<LatLng?>(
                      valueListenable: _positionNotifier,
                      builder: (context, pos, _) {
                        final raw =
                            _gps.currentPoints.map((p) => p.position).toList();
                        if (raw.length < 2) return const SizedBox.shrink();

                        if (raw.length == _lastPolylinePointCount &&
                            _lastPolylinePointCount > 0) {
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
                              color: _kGold,
                              strokeWidth: 4.5,
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
                              child: const _FlatLiveMarker(),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(CupertinoIcons.fullscreen,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSquareWeather() {
    return GestureDetector(
      onTap: _openFullWeather,
      child: Container(
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kCardBorder, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<WeatherData?>(
                  valueListenable: _weatherNotifier,
                  builder: (_, w, __) => ValueListenableBuilder<bool>(
                    valueListenable: _weatherLoadingNotifier,
                    builder: (_, loading, __) {
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 350,
                          child: WeatherWidget(
                            weather: w,
                            isLoading: loading && w == null,
                            onRetry: _fetchWeather,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(CupertinoIcons.fullscreen,
                      size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MODALS & NAVIGATION
  // ─────────────────────────────────────────────────────────────────────────

  void _openFullWeather() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.only(top: 80),
          decoration: const BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  height: 5,
                  width: 45,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'LIVE WEATHER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
                const Divider(color: _kCardBorder, thickness: 1.5),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                  child: ValueListenableBuilder<WeatherData?>(
                    valueListenable: _weatherNotifier,
                    builder: (_, w, __) => ValueListenableBuilder<bool>(
                      valueListenable: _weatherLoadingNotifier,
                      builder: (_, loading, __) => WeatherWidget(
                        weather: w,
                        isLoading: loading && w == null,
                        onRetry: _fetchWeather,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMinimalHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
        child: Row(
          children: [
            _CompassWidget(headingNotifier: _deviceCompassNotifier),
            const SizedBox(width: 20),
            _buildHeaderTemp(),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: _trackingNotifier,
              builder: (context, isTracking, child) {
                return AnimatedOpacity(
                  opacity: isTracking ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: isTracking
                      ? const _LiveRecordingDot()
                      : const SizedBox.shrink(),
                );
              },
            ),
            const SizedBox(width: 12),
            _buildDigitalClock(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnchoredBottomDock() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.05), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, bottomPadding > 0 ? bottomPadding + 10 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _SecondaryBtn(
                  icon: CupertinoIcons.map_fill,
                  label: 'VIEW MAP',
                  onTap: _openMap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SecondaryBtn(
                  icon: Icons.auto_awesome_rounded,
                  label: 'AI ASSIST',
                  onTap: _openAiAssistant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: _trackingNotifier,
            builder: (_, tracking, __) => _PrimaryActionButton(
              isTracking: tracking,
              onTap: _handleAction,
              timerNotifier: _elapsedSecondsNotifier,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTemp() {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: _weatherNotifier,
      builder: (_, w, __) {
        final double? tempC = w != null ? (w.temperature - 32) * 5 / 9 : null;
        final tempStr = tempC != null ? '${tempC.toInt()}' : '--';
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tempStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2, left: 2),
              child: Text(
                '°C',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
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
              const SizedBox(height: 6),
              const Text(
                'GPS SIGNAL',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// WHITE STAT CARD WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class _WhiteStatCard extends StatefulWidget {
  final String label, unit;
  final double value;
  final bool isDecimal;

  const _WhiteStatCard(
      {required this.label,
      required this.value,
      required this.unit,
      required this.isDecimal});

  @override
  State<_WhiteStatCard> createState() => _WhiteStatCardState();
}

class _WhiteStatCardState extends State<_WhiteStatCard> {
  late double _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final double beginValue = _previousValue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
                color: Colors.black54,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: beginValue, end: widget.value),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                onEnd: () => _previousValue = widget.value,
                builder: (context, val, _) {
                  final displayTxt = widget.isDecimal
                      ? val.toStringAsFixed(1)
                      : val.toInt().toString();
                  return Text(
                    displayTxt,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        fontFeatures: [ui.FontFeature.tabularFigures()]),
                  );
                },
              ),
              const SizedBox(width: 4),
              Text(
                widget.unit,
                style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _LiveRecordingDot extends StatefulWidget {
  const _LiveRecordingDot();
  @override
  State<_LiveRecordingDot> createState() => _LiveRecordingDotState();
}

class _LiveRecordingDotState extends State<_LiveRecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kRed.withValues(alpha: 0.5 + (_anim.value * 0.5)),
          ),
        );
      },
    );
  }
}

class _CompassWidget extends StatefulWidget {
  final ValueNotifier<double> headingNotifier;
  const _CompassWidget({required this.headingNotifier});

  @override
  State<_CompassWidget> createState() => _CompassWidgetState();
}

class _CompassWidgetState extends State<_CompassWidget> {
  double _previousRad = 0.0;

  static const List<String> _cardinals = [
    'N',
    'NE',
    'E',
    'SE',
    'S',
    'SW',
    'W',
    'NW'
  ];

  static String _cardinalLabel(double deg) {
    final int index = ((deg + 22.5) / 45).floor() % 8;
    return _cardinals[index];
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
        final double beginRad = _previousRad;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: beginRad, end: targetRad),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          onEnd: () => _previousRad = targetRad,
          builder: (_, animRad, __) {
            return Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _kCard,
                          border: Border.all(color: _kCardBorder),
                        ),
                      ),
                      Transform.rotate(
                        angle: -animRad,
                        child: CustomPaint(
                          size: const Size(36, 36),
                          painter: _kCompassRingPainter,
                        ),
                      ),
                      CustomPaint(
                        size: const Size(36, 36),
                        painter: _kNeedlePainter,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final minorPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    for (int i = 0; i < 12; i++) {
      final double angleDeg = i * 30.0;
      final double rad = angleDeg * (math.pi / 180) - math.pi / 2;
      final Offset outer =
          center + Offset(math.cos(rad) * radius, math.sin(rad) * radius);
      final Offset inner = center +
          Offset(math.cos(rad) * (radius - 3), math.sin(rad) * (radius - 3));
      canvas.drawLine(inner, outer, minorPaint);
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
      ..color = _kRed
      ..style = PaintingStyle.fill;
    final northPath = ui.Path()
      ..moveTo(center.dx, center.dy - 10)
      ..lineTo(center.dx - 2.5, center.dy)
      ..lineTo(center.dx + 2.5, center.dy)
      ..close();

    final pivotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawPath(northPath, northPaint);
    canvas.drawCircle(center, 2, pivotPaint);
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => false;
}

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
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2.0),
          width: 4,
          height: 10.0 + (index * 4.0),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white12,
            borderRadius: BorderRadius.circular(2),
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
    return const Column(
      children: [
        Icon(CupertinoIcons.battery_100, size: 24, color: Colors.white),
        SizedBox(height: 6),
        Text('POWER',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
      ],
    );
  }
}

class _SecondaryBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  State<_SecondaryBtn> createState() => _SecondaryBtnState();
}

class _SecondaryBtnState extends State<_SecondaryBtn> {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 54,
        decoration: BoxDecoration(
          color: _pressed ? Colors.white10 : _kBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kCardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatefulWidget {
  final bool isTracking;
  final VoidCallback onTap;
  final ValueNotifier<int> timerNotifier;

  const _PrimaryActionButton(
      {required this.isTracking,
      required this.onTap,
      required this.timerNotifier});

  @override
  State<_PrimaryActionButton> createState() => _PrimaryActionButtonState();
}

class _PrimaryActionButtonState extends State<_PrimaryActionButton> {
  bool _pressed = false;

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isT = widget.isTracking;
    final bgColor = isT ? _kRed : _kTeal;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _pressed ? bgColor.withValues(alpha: 0.8) : bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isT
                ? ValueListenableBuilder<int>(
                    valueListenable: widget.timerNotifier,
                    builder: (context, seconds, _) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        key: const ValueKey('tracking'),
                        children: [
                          const Icon(CupertinoIcons.stop_fill,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(seconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              letterSpacing: 1.5,
                              fontFeatures: [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : const Text(
                    'START TRACKING',
                    key: ValueKey('stopped'),
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FlatLiveMarker extends StatelessWidget {
  const _FlatLiveMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kTeal,
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
    );
  }
}
