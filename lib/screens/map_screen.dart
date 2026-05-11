import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as mk;

import '../models/trip_data.dart';
import '../utils/smooth_polyline.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EXTENSIONS
// ─────────────────────────────────────────────────────────────────────────────

extension _TripPointKmh on TripPoint {
  double get speedKmh => speedMph * 1.609344;
}

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

const _kGold = Color(0xFFD4A843);
const _kRed = Color(0xFFE74C3C);
const _kTeal = Color(0xFF4ECDC4);
const _kBlue = Color(0xFF3B82F6);
const _kBg = Color(0xFF070707);
const _kCard = Color(0xFF111111);
const _kCardBorder = Color(0xFF1E1E1E);

// Gradient for route glow
const _kRouteGlowOpacity = 0.18;

// ─────────────────────────────────────────────────────────────────────────────
// MAP STYLE ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum MapStyle {
  dark,
  light,
  satellite;

  String get label {
    switch (this) {
      case MapStyle.dark:
        return 'DARK';
      case MapStyle.light:
        return 'LIGHT';
      case MapStyle.satellite:
        return 'SAT';
    }
  }

  IconData get icon {
    switch (this) {
      case MapStyle.dark:
        return CupertinoIcons.moon_fill;
      case MapStyle.light:
        return CupertinoIcons.sun_max_fill;
      case MapStyle.satellite:
        return CupertinoIcons.globe;
    }
  }

  String get tileUrlTemplate {
    switch (this) {
      case MapStyle.dark:
        return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
      case MapStyle.light:
        return 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
      case MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  List<String> get subdomains => const ['a', 'b', 'c', 'd'];

  mk.MapType get appleMapType {
    switch (this) {
      case MapStyle.dark:
      case MapStyle.light:
        return mk.MapType.standard;
      case MapStyle.satellite:
        return mk.MapType.satellite;
    }
  }

  Color get routeColor {
    switch (this) {
      case MapStyle.satellite:
        return Colors.white;
      default:
        return _kGold;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLATFORM HELPER
// ─────────────────────────────────────────────────────────────────────────────

bool get _isNativeIOS {
  if (kIsWeb) return false;
  try {
    return Platform.isIOS;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEARING HELPER
// ─────────────────────────────────────────────────────────────────────────────

double _bearing(LatLng from, LatLng to) {
  final lat1 = from.latitudeInRad;
  final lat2 = to.latitudeInRad;
  final dLng = to.longitudeInRad - from.longitudeInRad;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

// ─────────────────────────────────────────────────────────────────────────────
// SPEED COLOR
// ─────────────────────────────────────────────────────────────────────────────

Color _speedColor(double kmh) {
  if (kmh < 15) return const Color(0xFF4ECDC4);
  if (kmh < 40) return const Color(0xFF27AE60);
  if (kmh < 70) return const Color(0xFFD4A843);
  if (kmh < 100) return const Color(0xFFE67E22);
  return const Color(0xFFE74C3C);
}

// ─────────────────────────────────────────────────────────────────────────────
// DURATION FORMATTER
// ─────────────────────────────────────────────────────────────────────────────

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  final List<TripPoint> points;
  final bool isLive;

  /// Optional trip start time for elapsed duration display.
  final DateTime? tripStartTime;

  const MapScreen({
    super.key,
    required this.points,
    required this.isLive,
    this.tripStartTime,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final fm.MapController _mapController = fm.MapController();
  final _AppleMapController _appleMapController = _AppleMapController();

  List<LatLng> _smoothedPoints = [];
  List<LatLng> _rawPoints = [];
  List<_SpeedSegment> _speedSegments = [];
  List<double> _speedSamples = [];
  List<double> _altSamples = [];

  bool _followMode = true;
  bool _showSpeedGradient = false;
  bool _panelExpanded = true;
  bool _stylePickerOpen = false;
  bool _showChart = false;
  _ChartMode _chartMode = _ChartMode.speed;

  double _currentZoom = 16.0;
  double _calculatedDistance = 0.0;
  double _calculatedMaxSpeed = 0.0;
  double _calculatedAvgSpeed = 0.0;
  double _calculatedMaxAltitude = 0.0;
  int _peakSpeedIndex = -1;
  double _currentBearing = 0.0;

  MapStyle _mapStyle = MapStyle.dark;

  final ValueNotifier<double> _bottomPanelHeight = ValueNotifier(0);
  final ValueNotifier<double> _hudSpeed = ValueNotifier(0);

  late AnimationController _markerPulseController;
  late AnimationController _chartRevealController;
  AnimationController? _moveAnimController;
  Animation<LatLng>? _moveAnim;

  @override
  void initState() {
    super.initState();
    _markerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _chartRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _processPoints();
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points != oldWidget.points ||
        widget.points.length != oldWidget.points.length) {
      _processPoints();
      if (_followMode && widget.isLive && widget.points.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _animatedMove(widget.points.last.position, _currentZoom);
        });
      }
    }
  }

  @override
  void dispose() {
    _markerPulseController.dispose();
    _chartRevealController.dispose();
    _moveAnimController?.dispose();
    _bottomPanelHeight.dispose();
    _hudSpeed.dispose();
    _appleMapController.dispose();
    try {
      _mapController.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ── Camera animation ───────────────────────────────────────────────────────

  void _animatedMove(LatLng dest, double zoom) {
    if (_isNativeIOS) {
      _appleMapController.animateTo(dest, zoom: zoom);
      return;
    }
    _moveAnimController?.stop();
    _moveAnimController?.dispose();
    _moveAnimController = null;

    LatLng start;
    try {
      start = _mapController.camera.center;
    } catch (_) {
      try {
        _mapController.move(dest, zoom);
      } catch (_) {}
      return;
    }

    _moveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _moveAnim = LatLngTween(begin: start, end: dest).animate(
      CurvedAnimation(
          parent: _moveAnimController!, curve: Curves.easeInOutCubic),
    );
    _moveAnim!.addListener(() {
      if (_moveAnim != null && mounted) {
        try {
          _mapController.move(_moveAnim!.value, zoom);
        } catch (_) {}
      }
    });
    _moveAnimController!.forward();
  }

  // ── Stats + route — single pass ────────────────────────────────────────────

  void _processPoints() {
    if (widget.points.isEmpty) {
      if (mounted) {
        setState(() {
          _calculatedDistance = 0;
          _calculatedMaxSpeed = 0;
          _calculatedAvgSpeed = 0;
          _calculatedMaxAltitude = 0;
          _peakSpeedIndex = -1;
          _currentBearing = 0;
          _smoothedPoints = [];
          _rawPoints = [];
          _speedSegments = [];
          _speedSamples = [];
          _altSamples = [];
        });
      }
      _hudSpeed.value = 0;
      return;
    }

    double dist = 0;
    double maxS = 0;
    double sumS = 0;
    double maxAlt = 0;
    int maxIdx = 0;
    const Distance distCalc = Distance();

    final rawPoints = <LatLng>[];
    final segments = <_SpeedSegment>[];

    for (int i = 0; i < widget.points.length; i++) {
      final pt = widget.points[i];
      rawPoints.add(pt.position);

      if (pt.speedKmh > maxS) {
        maxS = pt.speedKmh;
        maxIdx = i;
      }
      sumS += pt.speedKmh;

      double altM = 0;
      try {
        altM = (pt as dynamic).altitudeM as double? ?? 0.0;
      } catch (_) {}
      if (altM > maxAlt) maxAlt = altM;

      if (i > 0) {
        final prevPt = widget.points[i - 1];
        dist += distCalc.as(LengthUnit.Kilometer, prevPt.position, pt.position);

        final double avgSpeed = (prevPt.speedKmh + pt.speedKmh) / 2;
        final Color c = _speedColor(avgSpeed);
        if (segments.isNotEmpty && segments.last.color == c) {
          segments.last.points.add(pt.position);
        } else {
          segments.add(
              _SpeedSegment(points: [prevPt.position, pt.position], color: c));
        }
      }
    }

    double bearing = 0;
    if (widget.points.length >= 2) {
      bearing = _bearing(
        widget.points[widget.points.length - 2].position,
        widget.points.last.position,
      );
    }

    final simplified = rawPoints.length > 2
        ? simplifyPolyline(rawPoints, epsilon: 0.000035)
        : rawPoints;
    final smoothed = simplified.length > 1
        ? smoothPolyline(simplified, tension: 0.5, subdivisions: 10)
        : simplified;

    final int n = widget.points.length;
    const int maxSamples = 120;
    final int step = (n / maxSamples).ceil().clamp(1, n);
    final speedSamples = <double>[];
    final altSamples = <double>[];
    for (int i = 0; i < n; i += step) {
      speedSamples.add(widget.points[i].speedKmh);
      double altM = 0;
      try {
        altM = (widget.points[i] as dynamic).altitudeM as double? ?? 0.0;
      } catch (_) {}
      altSamples.add(altM);
    }

    _hudSpeed.value = widget.points.last.speedKmh;

    if (mounted) {
      setState(() {
        _calculatedDistance = dist;
        _calculatedMaxSpeed = maxS;
        _calculatedAvgSpeed = n > 0 ? sumS / n : 0;
        _calculatedMaxAltitude = maxAlt;
        _peakSpeedIndex = maxIdx;
        _currentBearing = bearing;
        _rawPoints = rawPoints;
        _smoothedPoints = smoothed;
        _speedSegments = segments;
        _speedSamples = speedSamples;
        _altSamples = altSamples;
      });
    }
  }

  // ── Fit bounds ─────────────────────────────────────────────────────────────

  void _fitRoute() {
    if (_rawPoints.isEmpty) return;
    if (_rawPoints.length == 1) {
      _animatedMove(_rawPoints.first, _currentZoom);
      return;
    }
    if (_isNativeIOS) {
      _appleMapController.fitPoints(_rawPoints);
      setState(() => _followMode = false);
      return;
    }
    final bounds = fm.LatLngBounds.fromPoints(_rawPoints);
    try {
      _mapController.fitCamera(
        fm.CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(72)),
      );
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          setState(() => _currentZoom = _mapController.camera.zoom);
        } catch (_) {}
      }
    });
    setState(() => _followMode = false);
  }

  void _toggleFollow() {
    final newFollow = !_followMode;
    setState(() => _followMode = newFollow);
    if (newFollow && widget.points.isNotEmpty) {
      _animatedMove(widget.points.last.position, _currentZoom);
    }
  }

  // ── Map style ──────────────────────────────────────────────────────────────

  void _selectStyle(MapStyle style) {
    if (style == _mapStyle) {
      setState(() => _stylePickerOpen = false);
      return;
    }
    setState(() {
      _mapStyle = style;
      _stylePickerOpen = false;
    });
    if (_isNativeIOS) _appleMapController.notifyStyleChanged();
  }

  // ── Zoom helper ────────────────────────────────────────────────────────────

  void _doZoom(int delta) {
    double z;
    try {
      z = (_mapController.camera.zoom + delta).clamp(3.0, 19.0);
    } catch (_) {
      z = (_currentZoom + delta).clamp(3.0, 19.0);
    }
    setState(() => _currentZoom = z);
    try {
      _mapController.move(_mapController.camera.center, z);
    } catch (_) {}
  }

  // ── Chart toggle ───────────────────────────────────────────────────────────

  void _toggleChart() {
    setState(() => _showChart = !_showChart);
    if (_showChart) {
      _chartRevealController.forward(from: 0);
    } else {
      _chartRevealController.reverse();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final allMarkers = _buildMarkers();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            // ── Map layer ────────────────────────────────────────────────────
            if (_isNativeIOS)
              _AppleMapLayer(
                controller: _appleMapController,
                points: widget.points,
                smoothedPoints: _smoothedPoints,
                speedSegments: _speedSegments,
                showSpeedGradient: _showSpeedGradient,
                followMode: _followMode,
                isLive: widget.isLive,
                peakSpeedIndex: _peakSpeedIndex,
                currentBearing: _currentBearing,
                markerPulseController: _markerPulseController,
                mapStyle: _mapStyle,
                onUserDrag: () {
                  if (_followMode) setState(() => _followMode = false);
                },
              )
            else
              _FlutterMapLayer(
                mapController: _mapController,
                points: widget.points,
                smoothedPoints: _smoothedPoints,
                speedSegments: _speedSegments,
                allMarkers: allMarkers,
                showSpeedGradient: _showSpeedGradient,
                mapStyle: _mapStyle,
                currentZoom: _currentZoom,
                onZoomChanged: (z) => _currentZoom = z,
                onUserDrag: () {
                  if (_followMode) setState(() => _followMode = false);
                },
              ),

            // ── Header ───────────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(context),
            ),

            // ── Style picker scrim ───────────────────────────────────────────
            if (_stylePickerOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _stylePickerOpen = false),
                  child: const SizedBox.expand(),
                ),
              ),

            // ── Style picker popover ─────────────────────────────────────────
            if (_stylePickerOpen)
              Positioned(
                top: MediaQuery.of(context).padding.top + 62,
                right: 16,
                child: _buildStylePicker(),
              ),

            // ── Live Speed HUD ───────────────────────────────────────────────
            if (widget.points.isNotEmpty)
              ValueListenableBuilder<double>(
                valueListenable: _bottomPanelHeight,
                builder: (_, panelH, __) => Positioned(
                  left: 16,
                  bottom: panelH + 12,
                  child: _buildLiveSpeedHUD(),
                ),
              ),

            // ── Zoom controls ────────────────────────────────────────────────
            ValueListenableBuilder<double>(
              valueListenable: _bottomPanelHeight,
              builder: (_, panelH, __) => Positioned(
                right: 16,
                bottom: panelH + 12,
                child: _buildZoomControls(),
              ),
            ),

            // ── Bottom panel ─────────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  List<fm.Marker> _buildMarkers() {
    if (widget.points.isEmpty) return const [];
    final markers = <fm.Marker>[_startMarker(widget.points.first.position)];

    if (!widget.isLive && widget.points.length > 1) {
      markers.add(_endMarker(widget.points.last.position));
    } else if (widget.isLive) {
      markers.add(_liveMarker(widget.points.last.position));
    }

    if (_showSpeedGradient && widget.points.length > 10) {
      for (int i = 20; i < widget.points.length - 10; i += 40) {
        markers.add(_speedTagMarker(widget.points[i]));
      }
    }

    if (_peakSpeedIndex != -1 && _calculatedMaxSpeed > 5) {
      markers.add(_peakSpeedMarker(widget.points[_peakSpeedIndex]));
    }
    return markers;
  }

  fm.Marker _startMarker(LatLng pos) => fm.Marker(
        point: pos,
        width: 32,
        height: 32,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kTeal,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                  color: _kTeal.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1)
            ],
          ),
          child: const Icon(CupertinoIcons.flag_fill,
              color: Colors.white, size: 13),
        ),
      );

  fm.Marker _endMarker(LatLng pos) => fm.Marker(
        point: pos,
        width: 32,
        height: 32,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kRed,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                  color: _kRed.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1)
            ],
          ),
          child: const Icon(CupertinoIcons.checkmark_alt,
              color: Colors.white, size: 13),
        ),
      );

  fm.Marker _liveMarker(LatLng pos) => fm.Marker(
        point: pos,
        width: 88,
        height: 88,
        child: AnimatedBuilder(
          animation: _markerPulseController,
          builder: (_, __) {
            final double scale = _markerPulseController.value;
            final double opacity = (1.0 - scale).clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 66 * scale,
                  height: 66 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kRed.withValues(alpha: opacity * 0.35),
                    border: Border.all(
                        color: _kRed.withValues(alpha: opacity * 0.65),
                        width: 1.2),
                  ),
                ),
                Transform.rotate(
                  angle: _currentBearing * math.pi / 180,
                  child: CustomPaint(
                    size: const Size(40, 40),
                    painter: _BearingArrowPainter(color: _kRed),
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: _kRed, width: 3),
                    boxShadow: [
                      BoxShadow(
                          color: _kRed.withValues(alpha: 0.75),
                          blurRadius: 12,
                          spreadRadius: 2)
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

  fm.Marker _speedTagMarker(TripPoint point) => fm.Marker(
        point: point.position,
        width: 40,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: _speedColor(point.speedKmh).withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: Text(point.speedKmh.toStringAsFixed(0),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ),
      );

  fm.Marker _peakSpeedMarker(TripPoint point) => fm.Marker(
        point: point.position,
        width: 68,
        height: 28,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFD4A843), Color(0xFFB8892C)]),
            borderRadius: BorderRadius.circular(7),
            boxShadow: [
              BoxShadow(
                  color: _kGold.withValues(alpha: 0.45),
                  blurRadius: 6,
                  spreadRadius: 0)
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.bolt_fill,
                  color: Colors.black, size: 10),
              const SizedBox(width: 3),
              Text(
                '${point.speedKmh.toStringAsFixed(0)} peak',
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      );

  // ── Live Speed HUD ─────────────────────────────────────────────────────────

  Widget _buildLiveSpeedHUD() {
    if (widget.points.isEmpty) return const SizedBox.shrink();
    return ValueListenableBuilder<double>(
      valueListenable: _hudSpeed,
      builder: (_, speed, __) {
        final Color accent = _speedColor(speed);
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kCardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isLive ? _kRed : Colors.white24,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.isLive ? 'LIVE' : 'SPEED',
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                                    begin: const Offset(0, 0.25),
                                    end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          speed.toStringAsFixed(0),
                          key: ValueKey(speed.toStringAsFixed(0)),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              height: 1,
                              letterSpacing: -1),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('km/h',
                          style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Stack(
                    children: [
                      Container(
                        height: 3,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        height: 3,
                        width: (speed / 160).clamp(0.03, 1.0) * 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accent.withValues(alpha: 0.6), accent],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                                color: accent.withValues(alpha: 0.6),
                                blurRadius: 4)
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final Duration? elapsed = widget.tripStartTime != null
        ? DateTime.now().difference(widget.tripStartTime!)
        : null;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            bottom: 12,
            left: 16,
            right: 16,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            border: Border(
              bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: _GlassButton(
                  child: const Icon(CupertinoIcons.chevron_left,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.isLive) ...[
                          _PulseDot(color: _kRed),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          widget.isLive ? 'LIVE TRACKING' : 'TRIP REPLAY',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${widget.points.length} pts',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 11),
                        ),
                        if (elapsed != null) ...[
                          Text('  ·  ',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  fontSize: 11)),
                          Text(
                            _formatDuration(elapsed),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11),
                          ),
                        ],
                        if (_calculatedDistance > 0) ...[
                          Text('  ·  ',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  fontSize: 11)),
                          Text(
                            '${_calculatedDistance.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: _kGold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _showSpeedGradient = !_showSpeedGradient),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _showSpeedGradient
                        ? _kGold.withValues(alpha: 0.15)
                        : _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _showSpeedGradient ? _kGold : _kCardBorder),
                  ),
                  child: Icon(Icons.speed_rounded,
                      color: _showSpeedGradient ? _kGold : Colors.white54,
                      size: 17),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleChart,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _showChart ? _kBlue.withValues(alpha: 0.15) : _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: _showChart ? _kBlue : _kCardBorder),
                  ),
                  child: Icon(CupertinoIcons.graph_square,
                      color: _showChart ? _kBlue : Colors.white54, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () =>
                    setState(() => _stylePickerOpen = !_stylePickerOpen),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _stylePickerOpen
                        ? _kGold.withValues(alpha: 0.15)
                        : _kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _stylePickerOpen ? _kGold : _kCardBorder),
                  ),
                  child: Icon(_mapStyle.icon,
                      color: _stylePickerOpen ? _kGold : Colors.white54,
                      size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Style Picker ───────────────────────────────────────────────────────────

  Widget _buildStylePicker() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, -8 * (1 - t)), child: child),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kCardBorder),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55), blurRadius: 18)
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: MapStyle.values.map((style) {
                  final bool isActive = _mapStyle == style;
                  return GestureDetector(
                    onTap: () => _selectStyle(style),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? _kGold.withValues(alpha: 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? _kGold.withValues(alpha: 0.45)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(style.icon,
                              color: isActive ? _kGold : Colors.white60,
                              size: 15),
                          const SizedBox(width: 10),
                          Text(style.label,
                              style: TextStyle(
                                  color: isActive ? _kGold : Colors.white60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8)),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            const Icon(CupertinoIcons.checkmark_alt,
                                color: _kGold, size: 11),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom panel ───────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    if (widget.points.isEmpty) return const SizedBox.shrink();

    return MeasureSize(
      onChange: (size) => _bottomPanelHeight.value = size.height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _kCardBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, -8))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _panelExpanded = !_panelExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(
                        width: 36,
                        height: 3.5,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    child: _panelExpanded
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_showChart && _speedSamples.isNotEmpty)
                                  _buildMiniChart(),
                                if (_showSpeedGradient) ...[
                                  const SizedBox(height: 10),
                                  _buildSpeedLegend(),
                                  const SizedBox(height: 10),
                                  Divider(
                                      color:
                                          Colors.white.withValues(alpha: 0.07),
                                      height: 1),
                                ],
                                const SizedBox(height: 14),
                                _buildStatsGrid(),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _MapActionButton(
                                        icon: CupertinoIcons
                                            .arrow_down_right_arrow_up_left,
                                        label: 'FIT ROUTE',
                                        onTap: _fitRoute,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _MapActionButton(
                                        icon: _followMode
                                            ? CupertinoIcons.location_fill
                                            : CupertinoIcons.location,
                                        label: _followMode
                                            ? 'FOLLOWING'
                                            : 'FOLLOW',
                                        isActive: _followMode,
                                        onTap: _toggleFollow,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Stats Grid ─────────────────────────────────────────────────────────────

  Widget _buildStatsGrid() {
    final bool hasAlt = _calculatedMaxAltitude > 0;
    return Row(
      children: [
        _StatTile(
          label: 'DISTANCE',
          value: _calculatedDistance >= 1
              ? _calculatedDistance.toStringAsFixed(2)
              : (_calculatedDistance * 1000).toStringAsFixed(0),
          unit: _calculatedDistance >= 1 ? 'KM' : 'M',
          color: _kTeal,
          icon: CupertinoIcons.map,
        ),
        _StatTile(
          label: 'MAX SPEED',
          value: _calculatedMaxSpeed.toStringAsFixed(0),
          unit: 'KM/H',
          color: _kGold,
          icon: CupertinoIcons.bolt_fill,
        ),
        _StatTile(
          label: 'AVG SPEED',
          value: _calculatedAvgSpeed.toStringAsFixed(0),
          unit: 'KM/H',
          color: const Color(0xFF27AE60),
          icon: CupertinoIcons.speedometer,
        ),
        _StatTile(
          label: hasAlt ? 'MAX ALT' : 'POINTS',
          value: hasAlt
              ? _calculatedMaxAltitude.toStringAsFixed(0)
              : '${widget.points.length}',
          unit: hasAlt ? 'M' : 'PTS',
          color: _kRed,
          icon:
              hasAlt ? CupertinoIcons.arrow_up : CupertinoIcons.circle_grid_hex,
        ),
      ],
    );
  }

  // ── Mini Chart ─────────────────────────────────────────────────────────────

  Widget _buildMiniChart() {
    return AnimatedBuilder(
      animation: _chartRevealController,
      builder: (_, __) {
        return Opacity(
          opacity: _chartRevealController.value,
          child: SizeTransition(
            sizeFactor: CurvedAnimation(
                parent: _chartRevealController, curve: Curves.easeOutCubic),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    _ChartTab(
                      label: 'SPEED',
                      active: _chartMode == _ChartMode.speed,
                      color: _kGold,
                      onTap: () =>
                          setState(() => _chartMode = _ChartMode.speed),
                    ),
                    const SizedBox(width: 8),
                    if (_altSamples.any((a) => a > 0))
                      _ChartTab(
                        label: 'ALTITUDE',
                        active: _chartMode == _ChartMode.altitude,
                        color: _kBlue,
                        onTap: () =>
                            setState(() => _chartMode = _ChartMode.altitude),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: CustomPaint(
                    size: const Size(double.infinity, 72),
                    painter: _MiniChartPainter(
                      samples: _chartMode == _ChartMode.speed
                          ? _speedSamples
                          : _altSamples,
                      color: _chartMode == _ChartMode.speed ? _kGold : _kBlue,
                      useSpeedColors: _chartMode == _ChartMode.speed,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Speed Legend ───────────────────────────────────────────────────────────

  Widget _buildSpeedLegend() {
    const items = [
      _LegendItem(color: Color(0xFF4ECDC4), label: '<15'),
      _LegendItem(color: Color(0xFF27AE60), label: '15–40'),
      _LegendItem(color: Color(0xFFD4A843), label: '40–70'),
      _LegendItem(color: Color(0xFFE67E22), label: '70–100'),
      _LegendItem(color: Color(0xFFE74C3C), label: '100+'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 4,
              decoration: BoxDecoration(
                  color: item.color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 4),
            Text(item.label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ],
        );
      }).toList(),
    );
  }

  // ── Zoom controls ──────────────────────────────────────────────────────────

  Widget _buildZoomControls() => Column(
        children: [
          _ZoomButton(icon: CupertinoIcons.plus, onTap: () => _doZoom(1)),
          const SizedBox(height: 8),
          _ZoomButton(icon: CupertinoIcons.minus, onTap: () => _doZoom(-1)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI CHART PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _MiniChartPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  final bool useSpeedColors;

  const _MiniChartPainter({
    required this.samples,
    required this.color,
    this.useSpeedColors = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final double maxVal = samples.reduce(math.max).clamp(1, double.infinity);
    final double w = size.width;
    final double h = size.height - 4;

    final path = ui.Path();
    final fillPath = ui.Path();
    final points = <Offset>[];

    for (int i = 0; i < samples.length; i++) {
      final double x = (i / (samples.length - 1).clamp(1, samples.length)) * w;
      final double y = h - (samples[i] / maxVal) * h;
      points.add(Offset(x, y));
    }

    path.moveTo(points.first.dx, points.first.dy);
    fillPath.moveTo(points.first.dx, h + 4);
    fillPath.lineTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1] : points[i];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = i + 2 < points.length ? points[i + 2] : p2;

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    fillPath.lineTo(points.last.dx, h + 4);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, w, h + 4));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    if (useSpeedColors && samples.length > 4) {
      final int dotStep = (samples.length / 12).ceil().clamp(1, samples.length);
      for (int i = 0; i < points.length; i += dotStep) {
        final dotPaint = Paint()
          ..color = _speedColor(samples[i])
          ..style = PaintingStyle.fill;
        canvas.drawCircle(points[i], 2.5, dotPaint);
      }
    }

    final labelStyle = ui.ParagraphStyle(textDirection: ui.TextDirection.ltr);
    for (int t = 0; t <= 2; t++) {
      final v = (maxVal * t / 2).round();
      final y = h - (v / maxVal) * h;
      final tickPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 0.5;
      canvas.drawLine(Offset(0, y), Offset(w, y), tickPaint);

      final pb = ui.ParagraphBuilder(labelStyle)
        ..pushStyle(ui.TextStyle(
            color: Colors.white.withValues(alpha: 0.28),
            fontSize: 8,
            fontWeight: FontWeight.bold))
        ..addText(v.toString());
      final para = pb.build()..layout(const ui.ParagraphConstraints(width: 40));
      canvas.drawParagraph(para, Offset(2, y - 9));
    }
  }

  @override
  bool shouldRepaint(_MiniChartPainter old) =>
      old.samples != samples || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// FLUTTER MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _FlutterMapLayer extends StatelessWidget {
  final fm.MapController mapController;
  final List<TripPoint> points;
  final List<LatLng> smoothedPoints;
  final List<_SpeedSegment> speedSegments;
  final List<fm.Marker> allMarkers;
  final bool showSpeedGradient;
  final MapStyle mapStyle;
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onUserDrag;

  const _FlutterMapLayer({
    required this.mapController,
    required this.points,
    required this.smoothedPoints,
    required this.speedSegments,
    required this.allMarkers,
    required this.showSpeedGradient,
    required this.mapStyle,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.onUserDrag,
  });

  Widget _buildSmoothPolylineLayer() {
    final color = mapStyle.routeColor;
    return fm.PolylineLayer(
      polylines: [
        fm.Polyline(
          points: smoothedPoints,
          color: color.withValues(alpha: _kRouteGlowOpacity),
          strokeWidth: 14,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: smoothedPoints,
          color: color.withValues(alpha: 0.45),
          strokeWidth: 7,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: smoothedPoints,
          color: color,
          strokeWidth: 3.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }

  Widget _buildSpeedGradientLayer() {
    final polylines = <fm.Polyline>[];
    for (final seg in speedSegments) {
      polylines.add(fm.Polyline(
        points: seg.points,
        color: seg.color.withValues(alpha: 0.22),
        strokeWidth: 12,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));
      polylines.add(fm.Polyline(
        points: seg.points,
        color: seg.color,
        strokeWidth: 4,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));
    }
    return fm.PolylineLayer(polylines: polylines);
  }

  @override
  Widget build(BuildContext context) {
    return fm.FlutterMap(
      mapController: mapController,
      options: fm.MapOptions(
        initialCenter:
            points.isNotEmpty ? points.last.position : const LatLng(0, 0),
        initialZoom: currentZoom,
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
        ),
        onMapEvent: (event) {
          if (event is fm.MapEventMove) {
            onZoomChanged(event.camera.zoom);
          }
          if (event is fm.MapEventMoveStart &&
              event.source != fm.MapEventSource.mapController) {
            onUserDrag();
          }
        },
      ),
      children: [
        fm.TileLayer(
          key: ValueKey(mapStyle),
          urlTemplate: mapStyle.tileUrlTemplate,
          subdomains: mapStyle.subdomains,
          userAgentPackageName: 'com.rideai.app',
          retinaMode: MediaQuery.devicePixelRatioOf(context) > 1,
        ),
        if (smoothedPoints.isNotEmpty)
          showSpeedGradient
              ? _buildSpeedGradientLayer()
              : _buildSmoothPolylineLayer(),
        fm.MarkerLayer(markers: allMarkers),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEARING ARROW PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _BearingArrowPainter extends CustomPainter {
  final Color color;
  const _BearingArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(cx, cy - 16)
      ..lineTo(cx - 6, cy + 2)
      ..lineTo(cx, cy - 2)
      ..lineTo(cx + 6, cy + 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BearingArrowPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// LATLNG TWEEN
// ─────────────────────────────────────────────────────────────────────────────

class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MEASURE SIZE
// ─────────────────────────────────────────────────────────────────────────────

class MeasureSize extends SingleChildRenderObjectWidget {
  final void Function(Size) onChange;

  const MeasureSize({
    super.key,
    required this.onChange,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      SizeObserverRenderBox(onChange: onChange);

  @override
  void updateRenderObject(
      BuildContext context, covariant SizeObserverRenderBox renderObject) {
    renderObject.onChange = onChange;
  }
}

class SizeObserverRenderBox extends RenderProxyBox {
  void Function(Size) onChange;
  Size? _previousSize;
  SizeObserverRenderBox({required this.onChange});

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    final prev = _previousSize;
    if (prev == null ||
        (prev.width - newSize.width).abs() > 0.5 ||
        (prev.height - newSize.height).abs() > 0.5) {
      _previousSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASSES
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedSegment {
  final List<LatLng> points;
  final Color color;
  _SpeedSegment({required this.points, required this.color});
}

class _LegendItem {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});
}

enum _ChartMode { speed, altitude }

// ─────────────────────────────────────────────────────────────────────────────
// SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  final Widget child;
  const _GlassButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _kCard.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kCardBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.5 + _ctrl.value * 0.5),
            boxShadow: [
              BoxShadow(
                  color: widget.color.withValues(alpha: _ctrl.value * 0.6),
                  blurRadius: 4,
                  spreadRadius: 1)
            ],
          ),
        ),
      );
}

class _StatTile extends StatelessWidget {
  final String label, value, unit;
  final Color color;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color.withValues(alpha: 0.7), size: 11),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5)),
            Text(unit,
                style: TextStyle(
                    color: color.withValues(alpha: 0.55),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _ChartTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _ChartTab({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? color.withValues(alpha: 0.5) : Colors.white12),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? color : Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8)),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  const _MapActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: isActive
              ? _kGold.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isActive ? _kGold.withValues(alpha: 0.5) : _kCardBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: isActive ? _kGold : Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: isActive ? _kGold : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kCardBorder),
            ),
            child: Icon(icon, color: Colors.white70, size: 18),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPLE MAP CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────

class _AppleMapController {
  _AppleMapLayerState? _state;

  void _attach(_AppleMapLayerState s) => _state = s;
  void _detach() => _state = null;

  void animateTo(LatLng position, {double zoom = 16}) =>
      _state?._animateTo(position, zoom: zoom);

  void fitPoints(List<LatLng> points) => _state?._fitPoints(points);
  void notifyStyleChanged() => _state?._onStyleChanged();
  void dispose() => _detach();
}

// ─────────────────────────────────────────────────────────────────────────────
// APPLE MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _AppleMapLayer extends StatefulWidget {
  final _AppleMapController controller;
  final List<TripPoint> points;
  final List<LatLng> smoothedPoints;
  final List<_SpeedSegment> speedSegments;
  final bool showSpeedGradient;
  final bool followMode;
  final bool isLive;
  final int peakSpeedIndex;
  final double currentBearing;
  final AnimationController markerPulseController;
  final MapStyle mapStyle;
  final VoidCallback onUserDrag;

  const _AppleMapLayer({
    required this.controller,
    required this.points,
    required this.smoothedPoints,
    required this.speedSegments,
    required this.showSpeedGradient,
    required this.followMode,
    required this.isLive,
    required this.peakSpeedIndex,
    required this.currentBearing,
    required this.markerPulseController,
    required this.mapStyle,
    required this.onUserDrag,
  });

  @override
  State<_AppleMapLayer> createState() => _AppleMapLayerState();
}

class _AppleMapLayerState extends State<_AppleMapLayer> {
  mk.AppleMapController? _mkController;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
  }

  @override
  void didUpdateWidget(_AppleMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach();
      widget.controller._attach(this);
    }
    if (widget.followMode && widget.isLive && widget.points.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(widget.points.last.position);
      });
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  void _animateTo(LatLng pos, {double zoom = 16}) {
    _mkController?.animateCamera(
      mk.CameraUpdate.newCameraPosition(
        mk.CameraPosition(
            target: mk.LatLng(pos.latitude, pos.longitude), zoom: zoom),
      ),
    );
  }

  void _fitPoints(List<LatLng> pts) {
    if (pts.isEmpty) return;
    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLng = pts.first.longitude;
    double maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mkController?.animateCamera(
      mk.CameraUpdate.newLatLngBounds(
        mk.LatLngBounds(
            southwest: mk.LatLng(minLat, minLng),
            northeast: mk.LatLng(maxLat, maxLng)),
        64,
      ),
    );
  }

  void _onStyleChanged() {
    if (mounted) setState(() {});
  }

  Set<mk.Polyline> _buildPolylines() {
    final polys = <mk.Polyline>{};
    int id = 0;
    final routeColor = widget.mapStyle.routeColor;

    if (widget.showSpeedGradient) {
      for (final seg in widget.speedSegments) {
        polys.add(mk.Polyline(
          polylineId: mk.PolylineId('seg_${id++}'),
          points: seg.points
              .map((p) => mk.LatLng(p.latitude, p.longitude))
              .toList(),
          color: seg.color,
          width: 5,
        ));
      }
    } else if (widget.smoothedPoints.isNotEmpty) {
      final mkPoints = widget.smoothedPoints
          .map((p) => mk.LatLng(p.latitude, p.longitude))
          .toList();
      polys.add(mk.Polyline(
        polylineId: mk.PolylineId('route_glow'),
        points: mkPoints,
        color: routeColor.withValues(alpha: 0.18),
        width: 12,
      ));
      polys.add(mk.Polyline(
        polylineId: mk.PolylineId('route_mid'),
        points: mkPoints,
        color: routeColor.withValues(alpha: 0.45),
        width: 7,
      ));
      polys.add(mk.Polyline(
        polylineId: mk.PolylineId('route_solid'),
        points: mkPoints,
        color: routeColor,
        width: 4,
      ));
    }
    return polys;
  }

  Set<mk.Annotation> _buildAnnotations() {
    final annotations = <mk.Annotation>{};
    if (widget.points.isEmpty) return annotations;

    annotations.add(mk.Annotation(
      annotationId: mk.AnnotationId('start'),
      position: mk.LatLng(widget.points.first.position.latitude,
          widget.points.first.position.longitude),
      infoWindow: const mk.InfoWindow(title: 'Start'),
      icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
          mk.BitmapDescriptor.hueCyan),
    ));

    if (!widget.isLive && widget.points.length > 1) {
      annotations.add(mk.Annotation(
        annotationId: mk.AnnotationId('end'),
        position: mk.LatLng(widget.points.last.position.latitude,
            widget.points.last.position.longitude),
        infoWindow: const mk.InfoWindow(title: 'End'),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueRed),
      ));
    } else if (widget.isLive) {
      annotations.add(mk.Annotation(
        annotationId: mk.AnnotationId('live'),
        position: mk.LatLng(widget.points.last.position.latitude,
            widget.points.last.position.longitude),
        infoWindow: const mk.InfoWindow(title: 'Live'),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueRed),
      ));
    }

    if (widget.peakSpeedIndex >= 0 &&
        widget.peakSpeedIndex < widget.points.length) {
      final peak = widget.points[widget.peakSpeedIndex];
      annotations.add(mk.Annotation(
        annotationId: mk.AnnotationId('peak'),
        position: mk.LatLng(peak.position.latitude, peak.position.longitude),
        infoWindow: mk.InfoWindow(
            title: '⚡ ${peak.speedKmh.toStringAsFixed(0)} km/h peak'),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueYellow),
      ));
    }
    return annotations;
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.points.isNotEmpty
        ? mk.LatLng(widget.points.last.position.latitude,
            widget.points.last.position.longitude)
        : const mk.LatLng(0, 0);

    return mk.AppleMap(
      initialCameraPosition: mk.CameraPosition(target: initialTarget, zoom: 16),
      mapType: widget.mapStyle.appleMapType,
      rotateGesturesEnabled: false,
      polylines: _buildPolylines(),
      annotations: _buildAnnotations(),
      onMapCreated: (ctrl) {
        _mkController = ctrl;
        if (widget.points.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _animateTo(widget.points.last.position);
          });
        }
      },
      onCameraMove: (_) {},
      onCameraMoveStarted: widget.onUserDrag,
    );
  }
}
