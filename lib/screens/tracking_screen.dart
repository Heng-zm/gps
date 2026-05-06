import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../services/services.dart';
import '../models/trip_data.dart';
import '../models/weather_data.dart';
import '../widgets/speedometer_widget.dart';
import '../widgets/weather_widget.dart';
import '../widgets/trip_stats_widget.dart';
import '../widgets/ai_chat_sheet.dart';
import 'map_screen.dart';
import 'summary_screen.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  // Services
  final GpsService _gpsService = GpsService();
  final WeatherService _weatherService = WeatherService.instance;
  final SettingsService _settings = SettingsService.instance;

  // Performance Notifiers (Avoids full screen rebuilds)
  final ValueNotifier<int> _tickNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> _speedNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> _signalNotifier = ValueNotifier<int>(0);

  WeatherData? _weather;
  bool _weatherLoading = false;
  bool _isTracking = false;
  double _currentAltitude = 0;
  double _currentHeading = 0.0;

  Timer? _tickerTimer;
  StreamSubscription<TripPoint>? _pointSub;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _fetchWeather();
    _tickerTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _tickNotifier.value++);
  }

  void _onSettingsChanged() => setState(() {});

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _tickerTimer?.cancel();
    _tickNotifier.dispose();
    _speedNotifier.dispose();
    _signalNotifier.dispose();
    _pointSub?.cancel();
    _gpsService.dispose();
    super.dispose();
  }

  /// FEATURE: Live AI Assistant
  /// Provides context-aware analysis of current live stats
  void _openAiAssistant() {
    HapticFeedback.lightImpact();

    // Create a live snapshot for the AI to analyze current progress
    final liveSnapshot = TripSummary(
      id: 'live_session_${DateTime.now().millisecondsSinceEpoch}',
      date: DateTime.now(),
      totalTime: _gpsService.currentTripTime,
      stoppedTime: _gpsService.currentStoppedTime,
      movingTime: _gpsService.currentTripTime - _gpsService.currentStoppedTime,
      maxSpeedMph: _gpsService.currentMaxSpeedMph,
      avgSpeedMph: _gpsService.currentAvgSpeedMph,
      altitudeGainFt: 0,
      maxAltitudeFt: 0,
      minAltitudeFt: 0,
      distanceMiles: _gpsService.currentDistanceMiles,
      points: _gpsService.currentPoints,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AiChatSheet(summary: liveSnapshot),
    );
  }

  Future<void> _fetchWeather() async {
    if (!_settings.showWeather || _weatherLoading) return;
    setState(() => _weatherLoading = true);
    try {
      final position = await _gpsService.getCurrentLocation();
      if (position != null) {
        _weather = await _weatherService.fetchWeather(
            position.latitude, position.longitude);
      }
    } catch (e) {
      debugPrint("Initial weather fetch failed: $e");
    } finally {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  Future<void> _startTracking() async {
    await HapticFeedback.mediumImpact();
    await _gpsService.startTracking();

    if (!_gpsService.isTracking) {
      _showPermissionDialog();
      return;
    }

    _pointSub = _gpsService.pointStream?.listen((point) {
      if (!mounted) return;
      _speedNotifier.value = point.speedMph;
      _currentAltitude = point.altitudeFt;

      // Accuracy 0-20m mapped to 4-bar signal indicator
      int signal = ((20 - point.accuracyMeters.clamp(0, 20)) / 20 * 4).round();
      _signalNotifier.value = signal.clamp(0, 4);

      if (_gpsService.currentPoints.length >= 2) {
        final pts = _gpsService.currentPoints;
        _currentHeading = const Distance()
            .bearing(pts[pts.length - 2].position, pts.last.position);
      }
    });

    setState(() => _isTracking = true);
  }

  void _stopTracking() {
    HapticFeedback.heavyImpact();
    final summary = _gpsService.stopTracking();
    _pointSub?.cancel();

    setState(() {
      _isTracking = false;
      _speedNotifier.value = 0;
      _signalNotifier.value = 0;
    });

    if (summary != null) {
      Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => SummaryScreen(summary: summary)));
    }
  }

  void _openMap() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (_) => MapScreen(
        points: _gpsService.currentPoints,
        isLive: _isTracking,
      ),
    ));
  }

  void _showPermissionDialog() {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Location Required'),
        content: const Text(
            'Please enable location access in system settings to track trips.'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(),

              // Real-time Dashboard (Speed & Signal)
              ValueListenableBuilder<double>(
                valueListenable: _speedNotifier,
                builder: (context, speed, _) {
                  final isOver = _isTracking &&
                      _settings.speedAlertEnabled &&
                      speed > _settings.speedAlertMph;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: SpeedometerWidget(
                            speedMph: speed, isOverLimit: isOver),
                      ),
                      _buildSignalRow(),
                      if (_settings.showHeading) _buildHeadingText(),
                      if (isOver) _buildSpeedAlertBanner(),
                    ],
                  );
                },
              ),

              _buildStatsGrid(),
              const SizedBox(height: 24),
              _buildControlButtons(),

              if (_settings.showWeather)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: WeatherWidget(
                      weather: _weather,
                      isLoading: _weatherLoading,
                      onRetry: _fetchWeather),
                ),

              if (_isTracking)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: TripStatsWidget(
                    points: _gpsService.currentPoints,
                    avgSpeedMph: _gpsService.currentAvgSpeedMph,
                    maxSpeedMph: _gpsService.currentMaxSpeedMph,
                    distanceMiles: _gpsService.currentDistanceMiles,
                    altitudeFt: _currentAltitude,
                    tripTime: _gpsService.currentTripTime,
                    stoppedTime: _gpsService.currentStoppedTime,
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (_weather != null)
            Text('${_weather!.temperature.toInt()}°',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: _openAiAssistant,
            child: Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Color(0xFFA855F7), size: 18),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: _tickNotifier,
            builder: (_, __, ___) {
              final now = DateTime.now();
              return Text(
                  '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSignalRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder(
            valueListenable: _signalNotifier,
            builder: (_, level, __) => _GpsSignalIndicator(level: level),
          ),
          ValueListenableBuilder(
            valueListenable: _signalNotifier,
            builder: (_, level, __) {
              final status = switch (level) {
                4 => 'EXCELLENT',
                3 => 'GOOD',
                2 => 'POOR',
                1 => 'WEAK',
                _ => 'SEARCHING...',
              };
              return Text(status,
                  style: const TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeadingText() {
    final directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final normalizedHeading = (_currentHeading % 360 + 360) % 360;
    final index = ((normalizedHeading + 22.5) % 360 / 45).floor();
    final dir = directions[index % 8];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        _isTracking ? '${normalizedHeading.toInt()}° $dir' : 'HEADING LOCKED',
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return ValueListenableBuilder(
      valueListenable: _tickNotifier,
      builder: (context, _, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Row(children: [
                _StatTile(
                    label: 'AVG SPEED',
                    value: _settings
                        .toDisplaySpeed(_gpsService.currentAvgSpeedMph)
                        .toInt()
                        .toString(),
                    unit: _settings.speedUnit.toUpperCase()),
                const SizedBox(width: 12),
                _StatTile(
                    label: 'TOP SPEED',
                    value: _settings
                        .toDisplaySpeed(_gpsService.currentMaxSpeedMph)
                        .toInt()
                        .toString(),
                    unit: _settings.speedUnit.toUpperCase()),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _StatTile(
                    label: 'DISTANCE',
                    value: _settings
                        .toDisplayDistance(_gpsService.currentDistanceMiles)
                        .toStringAsFixed(1),
                    unit: _settings.distanceUnit.toUpperCase()),
                const SizedBox(width: 12),
                _StatTile(
                    label: 'DURATION',
                    value: _fmt(_isTracking
                        ? _gpsService.currentTripTime
                        : Duration.zero),
                    unit: '',
                    isMono: true),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _SecondaryButton(
                icon: CupertinoIcons.map_fill, label: 'MAP', onTap: _openMap),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SecondaryButton(
                icon: Icons.auto_awesome,
                label: 'AI',
                onTap: _openAiAssistant,
                color: const Color(0xFFA855F7)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _isTracking ? _stopTracking : _startTracking,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 58,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: _isTracking
                          ? [const Color(0xFFE74C3C), const Color(0xFFC0392B)]
                          : [const Color(0xFF4ECDC4), const Color(0xFF2A9D8F)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isTracking
                                ? const Color(0xFFE74C3C)
                                : const Color(0xFF4ECDC4))
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]),
                child: Center(
                  child: Text(_isTracking ? 'STOP' : 'START',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedAlertBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
          color: const Color(0xFFE74C3C).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFE74C3C).withValues(alpha: 0.3))),
      child: const Row(children: [
        Icon(CupertinoIcons.exclamationmark_shield_fill,
            color: Color(0xFFE74C3C), size: 18),
        SizedBox(width: 12),
        Text('SPEED LIMIT EXCEEDED',
            style: TextStyle(
                color: Color(0xFFE74C3C),
                fontSize: 12,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _SecondaryButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color = const Color(0xFF4ECDC4)});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2A2A2A))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value, unit;
  final bool isMono;
  const _StatTile(
      {required this.label,
      required this.value,
      required this.unit,
      this.isMono = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF1F1F1F))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF555555),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: isMono ? 18 : 26,
                        fontWeight: FontWeight.w900,
                        fontFamily: isMono ? 'monospace' : null)),
                if (unit.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(unit,
                          style: const TextStyle(
                              color: Color(0xFF4ECDC4),
                              fontSize: 11,
                              fontWeight: FontWeight.w800))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GpsSignalIndicator extends StatelessWidget {
  final int level;
  const _GpsSignalIndicator({required this.level});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('SIGNAL',
            style: TextStyle(
                color: Color(0xFF555555),
                fontSize: 10,
                fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        ...List.generate(
            4,
            (i) => Container(
                  width: 4,
                  height: 8.0 + (i * 3),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: i < level
                        ? const Color(0xFF4ECDC4)
                        : const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                )),
      ],
    );
  }
}
