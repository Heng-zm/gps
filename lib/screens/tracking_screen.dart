import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;

import '../services/services.dart';
import '../models/trip_data.dart';
import '../models/weather_data.dart';
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
const _kBg = Color(0xFF070707); // OLED Black
const _kCard = Color(0xFF111111);
const _kCardBorder = Color(0xFF1A1A1A);

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

  // ── High-Performance Controllers ───────────────────────────────────────────
  final ValueNotifier<int> _tickNotifier = ValueNotifier(0);
  final ValueNotifier<double> _speedNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _headingNotifier = ValueNotifier(0.0);
  final ValueNotifier<int> _signalNotifier = ValueNotifier(0);
  final ValueNotifier<bool> _trackingNotifier = ValueNotifier(false);
  final ValueNotifier<WeatherData?> _weatherNotifier = ValueNotifier(null);
  final ValueNotifier<LatLng?> _positionNotifier = ValueNotifier(null);

  final fm.MapController _mapController = fm.MapController();
  StreamSubscription<TripPoint>? _pointSub;
  Timer? _tickTimer;
  bool _weatherLoading = false;

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
    _tickTimer?.cancel();
    _pointSub?.cancel();
    _tickNotifier.dispose();
    _speedNotifier.dispose();
    _headingNotifier.dispose();
    _signalNotifier.dispose();
    _trackingNotifier.dispose();
    _weatherNotifier.dispose();
    _positionNotifier.dispose();
    _mapController.dispose();
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
        final bearing = const Distance()
            .bearing(pts[pts.length - 2].position, pts.last.position);
        _headingNotifier.value = (bearing + 360) % 360;
      }

      // Signal Strength (0-4 bars based on accuracy)
      _signalNotifier.value =
          ((40 - point.accuracyMeters.clamp(0, 40)) / 40 * 4)
              .round()
              .clamp(0, 4);

      try {
        _mapController.move(point.position, 16);
        if (point.speedMph > 2.0) {
          _mapController.rotate(-_headingNotifier.value);
        }
      } catch (_) {}
    });
  }

  Future<void> _fetchWeather() async {
    if (!_settings.showWeather || _weatherLoading) return;
    _weatherLoading = true;
    try {
      final pos = await _gps.getCurrentLocation();
      if (pos != null && mounted) {
        _weatherNotifier.value =
            await _weather.fetchWeather(pos.latitude, pos.longitude);
      }
    } catch (e) {
      debugPrint("Weather fetch failed: $e");
    } finally {
      if (mounted) _weatherLoading = false;
    }
  }

  Future<void> _handleAction() async {
    if (_trackingNotifier.value) {
      HapticFeedback.heavyImpact();
      final summary = _gps.stopTracking();
      _pointSub?.cancel();
      _trackingNotifier.value = false;
      _speedNotifier.value = 0;
      _headingNotifier.value = 0;

      try {
        _mapController.rotate(0);
      } catch (_) {}

      if (summary != null) {
        if (!mounted) return;
        Navigator.of(context).push(CupertinoPageRoute(
            builder: (_) => SummaryScreen(summary: summary)));
      }
    } else {
      await HapticFeedback.mediumImpact();
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
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.pop(c);
                Geolocator.openAppSettings();
              },
              child: const Text('Settings')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // AnnotatedRegion forces the time/battery text in the phone's status bar to be white
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // MAIN SCROLLABLE CONTENT
            Positioned.fill(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: SafeArea(
                  top: false, // Top is handled by custom spacing
                  bottom: true,
                  child: Column(
                    children: [
                      // Space for the floating glass header
                      SizedBox(height: MediaQuery.of(context).padding.top + 80),
                      _buildSpeedometerSection(),
                      _buildSignalArcs(),
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
            ),

            // FLOATING GLASSMORPHISM HEADER
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
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 10,
              bottom: 15,
              left: 20,
              right: 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            border: Border(
                bottom:
                    BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              _buildCompass(),
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

  Widget _buildCompass() {
    return ValueListenableBuilder<double>(
      valueListenable: _headingNotifier,
      builder: (_, heading, __) => Transform.rotate(
        angle: -heading * (math.pi / 180),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF222222), Color(0xFF111111)],
              ),
              boxShadow: [
                BoxShadow(
                  color: _kGold.withValues(alpha: 0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ],
              border: Border.all(color: _kGold.withValues(alpha: 0.3))),
          child: const Center(
            // UI BUG FIX: location_north_fill points natively at 0 degrees.
            child: Icon(CupertinoIcons.location_north_fill,
                color: _kGoldBright, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderTemp() {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: _weatherNotifier,
      builder: (_, w, __) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(w != null ? '${w.temperature.toInt()}' : '--',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 2),
          const Text('°C',
              style: TextStyle(
                  color: _kRed, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDigitalClock() {
    return ValueListenableBuilder<int>(
      valueListenable: _tickNotifier,
      builder: (_, __, ___) {
        final now = DateTime.now();
        return Text('${now.hour}:${now.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -1));
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

  Widget _buildSignalArcs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 5),
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
              Text("GPS SIGNAL",
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
            ],
          ),
          Column(
            children: [
              const Icon(CupertinoIcons.battery_100, size: 18, color: _kTeal),
              const SizedBox(height: 5),
              Text("POWER 100%",
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return ValueListenableBuilder<int>(
        valueListenable: _tickNotifier,
        builder: (context, _, __) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _StatBox(
                  label: 'DISTANCE',
                  value: _settings.toDisplayDistance(_gps.currentDistanceMiles),
                  isDecimal: true,
                  unit: 'KM',
                  color: _kTeal,
                ),
                const SizedBox(width: 15),
                _StatBox(
                  label: 'AVG SPEED',
                  value: _settings.toDisplaySpeed(_gps.currentAvgSpeedMph),
                  isDecimal: false,
                  unit: 'KM/H',
                  color: _kGold,
                ),
              ],
            ),
          );
        });
  }

  Widget _buildMapPreview() {
    return GestureDetector(
      onTap: _openMap,
      child: Container(
        height: 190,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          // UI BUG FIX: AbsorbPointer prevents flutter_map from swallowing taps,
          // ensuring the GestureDetector always fires reliably.
          child: AbsorbPointer(
            child: fm.FlutterMap(
              mapController: _mapController,
              options: fm.MapOptions(
                  initialCenter: _positionNotifier.value ??
                      const LatLng(11.5564, 104.9282),
                  initialZoom: 16,
                  interactionOptions: const fm.InteractionOptions(
                      flags: fm.InteractiveFlag.none)),
              children: [
                fm.TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'),
                ValueListenableBuilder<LatLng?>(
                  valueListenable: _positionNotifier,
                  builder: (context, pos, _) {
                    if (pos == null) return const SizedBox.shrink();
                    return fm.MarkerLayer(markers: [
                      fm.Marker(
                        point: pos,
                        width: 80,
                        height: 80,
                        alignment: Alignment.center,
                        child: const _PulsingLiveMarker(),
                      )
                    ]);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    return ValueListenableBuilder<WeatherData?>(
      valueListenable: _weatherNotifier,
      builder: (_, w, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: WeatherWidget(
              weather: w, isLoading: w == null, onRetry: _fetchWeather)),
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
              onTap: _openMap),
          const SizedBox(width: 12),
          _SquareActionBtn(
              icon: Icons.auto_awesome_rounded,
              label: 'AI',
              color: _kPurple,
              onTap: _openAiAssistant),
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
    Navigator.of(context).push(CupertinoPageRoute(
        builder: (_) => MapScreen(
            points: _gps.currentPoints, isLive: _trackingNotifier.value)));
  }

  void _openAiAssistant() {
    HapticFeedback.lightImpact();
    final snap = TripSummary(
      id: 'live',
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
      points: _gps.currentPoints,
    );
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AiChatSheet(summary: snap));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PREMIUM WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// Animated 4-bar signal strength indicator
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
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 4,
          height: 8.0 + (index * 3.0), // Bars grow in height (8, 11, 14, 17)
          decoration: BoxDecoration(
            color: isActive ? _kGold : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: _kGold.withValues(alpha: 0.5), blurRadius: 4)
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

/// Smoothly animates numbers when they update
class _StatBox extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _kCardBorder),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: value),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, val, child) {
                    final displayTxt = isDecimal
                        ? val.toStringAsFixed(1)
                        : val.toInt().toString();
                    return Text(displayTxt,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900));
                  },
                ),
                const SizedBox(width: 4),
                Text(unit,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Square Glassmorphic Action Button
class _SquareActionBtn extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 64,
        decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kCardBorder),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4))
            ]),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w900))
        ]),
      ),
    );
  }
}

/// Breathing animation for the main action button
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.2, end: 0.6).animate(
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
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _glowAnimation,
        builder: (context, child) {
          final isT = widget.isTracking;
          final baseColor = isT ? _kRed : _kGold;
          final shadowColor =
              baseColor.withValues(alpha: isT ? _glowAnimation.value : 0.3);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                  colors: isT
                      ? [const Color(0xFFE74C3C), const Color(0xFFC0392B)]
                      : [const Color(0xFFD4A843), const Color(0xFF8B6914)]),
              boxShadow: [
                BoxShadow(
                    color: shadowColor,
                    blurRadius: isT ? 20 : 12,
                    spreadRadius: isT ? 2 : 0,
                    offset: const Offset(0, 6))
              ],
            ),
            child: Center(
              child: Text(isT ? "STOP" : "START",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      fontSize: 18)),
            ),
          );
        },
      ),
    );
  }
}

/// Radar pulsing live location marker
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

    // UI BUG FIX: Replaced linear animation with a smooth curve for better realism
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad),
    );

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
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
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer Radar Pulse
            Container(
              width: 60 * _scaleAnimation.value,
              height: 60 * _scaleAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kRed.withValues(alpha: _opacityAnimation.value),
              ),
            ),
            // Inner Core
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: _kRed.withValues(alpha: 0.8),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
                border: Border.all(color: _kRed, width: 4),
              ),
            ),
            // Directional Chevron
            const Positioned(
              top: 25,
              child: Icon(CupertinoIcons.chevron_up,
                  color: Colors.white, size: 14),
            )
          ],
        );
      },
    );
  }
}
