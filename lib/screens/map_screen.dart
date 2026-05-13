// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as mk;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';

import '../models/trip_data.dart';
import '../utils/smooth_polyline.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EXTENSIONS
// ─────────────────────────────────────────────────────────────────────────────

extension _TripPointUiExt on TripPoint {
  double get speedKmh {
    final double mph = speedMph;
    return (mph.isFinite && mph >= 0.0) ? mph * 1.609344 : 0.0;
  }

  double get altitudeMeters {
    final double ft = altitudeFt;
    return ft.isFinite ? ft / 3.28084 : 0.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD86B);
const Color _kGoldDim = Color(0xFF8A6A1F);
const Color _kRed = Color(0xFFE74C3C);
const Color _kTeal = Color(0xFF4ECDC4);
const Color _kBlue = Color(0xFF3B82F6);
const Color _kGreen = Color(0xFF27AE60);
const Color _kOrange = Color(0xFFE67E22);
const Color _kBg = Color(0xFF060608);
const Color _kCard = Color(0xFF0E0E12);
const Color _kCardBorder = Color(0xFF1E1E24);
const Color _kSurface = Color(0xFF14141A);

const double _kRouteGlowOpacity = 0.18;
const int _kMaxChartSamples = 120;
const int _kMaxMapRenderPoints = 1800;
const double _kDefaultZoom = 16.0;
const double _kMinZoom = 3.0;
const double _kMaxZoom = 19.0;
const double _kCameraMoveMinMeters = 2.0;
const Duration _kCameraMoveThrottle = Duration(milliseconds: 450);
const Duration _kAnimMoveDuration = Duration(milliseconds: 520);

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
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      case MapStyle.light:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      case MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  List<String> get subdomains => const <String>[];

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
      case MapStyle.dark:
      case MapStyle.light:
        return _kGoldSoft;
    }
  }

  MapStyle get next {
    switch (this) {
      case MapStyle.dark:
        return MapStyle.light;
      case MapStyle.light:
        return MapStyle.satellite;
      case MapStyle.satellite:
        return MapStyle.dark;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

bool get _isNativeIOS {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

bool _isValidLatLng(LatLng point) {
  return point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude.abs() <= 90.0 &&
      point.longitude.abs() <= 180.0;
}

/// FIX: Returns null for identical points; uses utils bearing under the hood.
double _bearingOrZero(LatLng from, LatLng to) {
  return calculateBearingDegrees(from, to) ?? 0.0;
}

Color _speedColor(double kmh) {
  if (!kmh.isFinite || kmh <= 0.0) return _kTeal;
  if (kmh < 15) return _kTeal;
  if (kmh < 40) return _kGreen;
  if (kmh < 70) return _kGold;
  if (kmh < 100) return _kOrange;
  return _kRed;
}

String _formatDuration(Duration duration) {
  final Duration safe = duration.isNegative ? Duration.zero : duration;
  final int h = safe.inHours;
  final int m = safe.inMinutes.remainder(60);
  final int s = safe.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

String _formatDistance(double km) {
  if (km >= 1.0) return '${km.toStringAsFixed(2)} km';
  return '${(km * 1000).toStringAsFixed(0)} m';
}

// ─────────────────────────────────────────────────────────────────────────────
// PROCESSED ROUTE DATA (immutable value object to avoid scattered state)
// ─────────────────────────────────────────────────────────────────────────────

class _RouteData {
  const _RouteData({
    required this.validPoints,
    required this.rawPoints,
    required this.smoothedPoints,
    required this.speedSegments,
    required this.speedSamples,
    required this.altSamples,
    required this.distanceKm,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
    required this.maxAltitudeM,
    required this.peakSpeedIndex,
    required this.currentBearing,
    required this.lastSpeedKmh,
  });

  static const _RouteData empty = _RouteData(
    validPoints: <TripPoint>[],
    rawPoints: <LatLng>[],
    smoothedPoints: <LatLng>[],
    speedSegments: <_SpeedSegment>[],
    speedSamples: <double>[],
    altSamples: <double>[],
    distanceKm: 0.0,
    maxSpeedKmh: 0.0,
    avgSpeedKmh: 0.0,
    maxAltitudeM: 0.0,
    peakSpeedIndex: -1,
    currentBearing: 0.0,
    lastSpeedKmh: 0.0,
  );

  final List<TripPoint> validPoints;
  final List<LatLng> rawPoints;
  final List<LatLng> smoothedPoints;
  final List<_SpeedSegment> speedSegments;
  final List<double> speedSamples;
  final List<double> altSamples;
  final double distanceKm;
  final double maxSpeedKmh;
  final double avgSpeedKmh;
  final double maxAltitudeM;
  final int peakSpeedIndex;
  final double currentBearing;
  final double lastSpeedKmh;

  bool get isEmpty => validPoints.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// ROUTE PROCESSOR (static, no setState inside, returns value)
// ─────────────────────────────────────────────────────────────────────────────

class _RouteProcessor {
  static _RouteData process(List<TripPoint> points) {
    final List<TripPoint> valid = points
        .where((TripPoint p) => _isValidLatLng(p.position))
        .toList(growable: false);

    if (valid.isEmpty) return _RouteData.empty;

    final int n = valid.length;
    final List<LatLng> raw =
        List<LatLng>.generate(n, (int i) => valid[i].position);

    // FIX: Use calculatePolylineDistanceMeters from utils — avoids creating a
    // Distance() object per segment inside a loop (was O(n) allocations).
    final double distanceKm = calculatePolylineDistanceMeters(raw) / 1000.0;

    double maxSpeed = 0.0;
    double speedSum = 0.0;
    double maxAlt = 0.0;
    int peakIndex = 0;

    final List<_SpeedSegment> segments = <_SpeedSegment>[];

    for (int i = 0; i < n; i++) {
      final double spd = valid[i].speedKmh;
      final double alt = valid[i].altitudeMeters;

      speedSum += spd;

      if (spd > maxSpeed) {
        maxSpeed = spd;
        peakIndex = i;
      }
      if (alt > maxAlt) maxAlt = alt;

      if (i > 0) {
        final double avg = (valid[i - 1].speedKmh + spd) / 2.0;
        final Color color = _speedColor(avg);

        if (segments.isNotEmpty && segments.last.color == color) {
          segments.last.points.add(valid[i].position);
        } else {
          segments.add(_SpeedSegment(
            points: <LatLng>[valid[i - 1].position, valid[i].position],
            color: color,
          ));
        }
      }
    }

    final double bearing = n >= 2
        ? _bearingOrZero(valid[n - 2].position, valid.last.position)
        : 0.0;

    // FIX: smoothed already guaranteed valid by polyline_utils — no need for
    // the extra .where(_isValidLatLng) filter that was wasting a pass.
    final List<LatLng> smoothed = raw.length > 1
        ? optimizePolylineAdaptive(raw, maxOutputPoints: _kMaxMapRenderPoints)
        : List<LatLng>.from(raw);

    // FIX: Use downsampleValues from utils instead of manual index stepping.
    final List<double> rawSpeeds = valid
        .map((TripPoint p) => p.speedKmh)
        .where((double v) => v.isFinite)
        .toList(growable: false);
    final List<double> rawAlts = valid
        .map((TripPoint p) => p.altitudeMeters)
        .where((double v) => v.isFinite)
        .toList(growable: false);

    return _RouteData(
      validPoints: valid,
      rawPoints: raw,
      smoothedPoints: smoothed,
      speedSegments: segments,
      speedSamples: downsampleValues(rawSpeeds, maxPoints: _kMaxChartSamples),
      altSamples: downsampleValues(rawAlts, maxPoints: _kMaxChartSamples),
      distanceKm: distanceKm.isFinite ? distanceKm : 0.0,
      maxSpeedKmh: maxSpeed,
      avgSpeedKmh: n > 0 ? speedSum / n : 0.0,
      maxAltitudeM: maxAlt,
      peakSpeedIndex: peakIndex,
      currentBearing: bearing,
      lastSpeedKmh: valid.last.speedKmh,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.points,
    required this.isLive,
    this.tripStartTime,
  });

  final List<TripPoint> points;
  final bool isLive;
  final DateTime? tripStartTime;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final fm.MapController _mapController = fm.MapController();
  final _AppleMapController _appleMapController = _AppleMapController();

  _RouteData _route = _RouteData.empty;

  bool _followMode = true;
  bool _showSpeedGradient = false;
  bool _panelExpanded = true;
  bool _stylePickerOpen = false;
  bool _showChart = false;
  bool _mapReady = false;
  bool _replayPlaying = false;

  int _replayIndex = 0;
  double _replaySpeed = 1.0;
  Timer? _replayTimer;

  _ChartMode _chartMode = _ChartMode.speed;
  MapStyle _mapStyle = MapStyle.dark;

  double _currentZoom = _kDefaultZoom;

  // FIX: Use ValueNotifier to avoid setState for high-frequency HUD updates.
  final ValueNotifier<double> _bottomPanelHeight = ValueNotifier<double>(0);
  final ValueNotifier<double> _hudSpeed = ValueNotifier<double>(0);

  // FIX: Shared pulse controller passed down — _PulseDot no longer creates its own.
  late final AnimationController _markerPulseController;
  late final AnimationController _chartRevealController;
  late final AnimationController _panelSlideController;

  // FIX: Keep track of animation to cancel safely on dispose.
  AnimationController? _moveAnimController;
  Animation<LatLng>? _moveAnim;

  // Camera throttle
  DateTime? _lastCameraMoveAt;
  LatLng? _lastCameraDestination;

  // Chart scrub
  final ValueNotifier<int> _chartScrubIndex = ValueNotifier<int>(-1);
  final ValueNotifier<int> _replayIndexNotifier = ValueNotifier<int>(0);

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

    _panelSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1.0,
    );

    _route = _RouteProcessor.process(widget.points);
    _replayIndex = _route.validPoints.isEmpty
        ? 0
        : (widget.isLive ? _route.validPoints.length - 1 : 0);
    _replayIndexNotifier.value = _replayIndex;
    _hudSpeed.value = widget.isLive
        ? _route.lastSpeedKmh
        : _speedAtReplayIndex(_replayIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _route.rawPoints.isEmpty) return;
      if (_route.rawPoints.length > 1 && !widget.isLive) {
        _fitRoute(haptic: false);
      } else {
        _animatedMove(_route.rawPoints.last, _currentZoom);
      }
    });
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool changed = widget.points.length != oldWidget.points.length ||
        !identical(widget.points, oldWidget.points) ||
        widget.isLive != oldWidget.isLive;

    if (!changed) return;

    final _RouteData newRoute = _RouteProcessor.process(widget.points);

    _stopReplayTimer();
    setState(() {
      _route = newRoute;
      _replayPlaying = false;
      _replayIndex = newRoute.validPoints.isEmpty
          ? 0
          : (widget.isLive ? newRoute.validPoints.length - 1 : 0);
    });
    _replayIndexNotifier.value = _replayIndex;
    _hudSpeed.value = widget.isLive
        ? newRoute.lastSpeedKmh
        : _speedAtReplayIndex(_replayIndex);

    if (_followMode && widget.isLive && newRoute.rawPoints.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animatedMove(newRoute.rawPoints.last, _currentZoom);
      });
    }
  }

  @override
  void dispose() {
    // FIX: Cancel move animation before disposing to avoid listener firing
    // after dispose.
    _stopReplayTimer();
    _moveAnimController?.stop();
    _moveAnimController?.dispose();
    _moveAnim = null;

    _markerPulseController.dispose();
    _chartRevealController.dispose();
    _panelSlideController.dispose();
    _bottomPanelHeight.dispose();
    _hudSpeed.dispose();
    _chartScrubIndex.dispose();
    _replayIndexNotifier.dispose();
    _appleMapController.dispose();

    try {
      _mapController.dispose();
    } catch (_) {}

    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CAMERA
  // ───────────────────────────────────────────────────────────────────────────

  void _animatedMove(LatLng destination, double zoom, {bool force = false}) {
    if (!_isValidLatLng(destination)) return;

    final double safeZoom = zoom.clamp(_kMinZoom, _kMaxZoom).toDouble();

    if (!force && _shouldSkipCameraMove(destination)) return;

    _lastCameraMoveAt = DateTime.now();
    _lastCameraDestination = destination;

    if (_isNativeIOS) {
      _appleMapController.animateTo(destination, zoom: safeZoom);
      return;
    }

    if (!_mapReady) {
      try {
        _mapController.move(destination, safeZoom);
      } catch (_) {}
      return;
    }

    // FIX: Remove listener before stopping/disposing to avoid stale callbacks.
    final Animation<LatLng>? oldAnim = _moveAnim;
    _moveAnimController?.stop();
    if (oldAnim != null) {
      _moveAnim = null;
    }
    _moveAnimController?.dispose();
    _moveAnimController = null;

    LatLng start;
    try {
      start = _mapController.camera.center;
    } catch (_) {
      try {
        _mapController.move(destination, safeZoom);
      } catch (_) {}
      return;
    }

    final AnimationController ctrl = AnimationController(
      vsync: this,
      duration: _kAnimMoveDuration,
    );
    _moveAnimController = ctrl;

    final Animation<LatLng> anim = LatLngTween(begin: start, end: destination)
        .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic));
    _moveAnim = anim;

    anim.addListener(() {
      if (!mounted || _moveAnim != anim) return;
      try {
        _mapController.move(anim.value, safeZoom);
      } catch (_) {}
    });

    ctrl.forward().whenComplete(() {
      if (_moveAnimController == ctrl) {
        _moveAnimController = null;
        _moveAnim = null;
      }
    });
  }

  bool _shouldSkipCameraMove(LatLng destination) {
    final DateTime? lastMoveAt = _lastCameraMoveAt;
    final LatLng? lastDest = _lastCameraDestination;
    if (lastMoveAt == null || lastDest == null) return false;

    if (DateTime.now().difference(lastMoveAt) >= _kCameraMoveThrottle) {
      return false;
    }

    // FIX: Use calculateDistanceMeters from utils instead of creating Distance().
    final double meters = calculateDistanceMeters(lastDest, destination);
    return meters.isFinite && meters < _kCameraMoveMinMeters;
  }

  void _fitRoute({bool haptic = true}) {
    if (_route.rawPoints.isEmpty) return;
    if (haptic) HapticFeedback.lightImpact();

    if (_route.rawPoints.length == 1) {
      _animatedMove(_route.rawPoints.first, _currentZoom, force: true);
      return;
    }

    if (_isNativeIOS) {
      _appleMapController.fitPoints(_route.rawPoints);
      if (mounted) setState(() => _followMode = false);
      return;
    }

    final fm.LatLngBounds bounds = fm.LatLngBounds.fromPoints(_route.rawPoints);

    try {
      _mapController.fitCamera(
        fm.CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(72, 120, 72, 240),
        ),
      );
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        setState(() {
          _currentZoom = _mapController.camera.zoom;
        });
      } catch (_) {}
    });

    setState(() => _followMode = false);
  }

  void _toggleFollow() {
    HapticFeedback.lightImpact();
    final bool next = !_followMode;
    setState(() => _followMode = next);
    if (next && _route.rawPoints.isNotEmpty) {
      final LatLng? target = widget.isLive
          ? _route.rawPoints.last
          : _positionAtReplayIndex(_replayIndex);
      if (target != null) _animatedMove(target, _currentZoom, force: true);
    }
  }

  void _selectStyle(MapStyle style) {
    HapticFeedback.selectionClick();
    setState(() {
      _mapStyle = style;
      _stylePickerOpen = false;
    });
    if (_isNativeIOS) _appleMapController.notifyStyleChanged();
  }

  void _cycleMapStyle() {
    HapticFeedback.selectionClick();
    setState(() {
      _mapStyle = _mapStyle.next;
      _stylePickerOpen = false;
    });
    if (_isNativeIOS) _appleMapController.notifyStyleChanged();
  }

  double _speedAtReplayIndex(int index) {
    if (_route.validPoints.isEmpty) return 0.0;
    final int safeIndex = index.clamp(0, _route.validPoints.length - 1);
    return _route.validPoints[safeIndex].speedKmh;
  }

  LatLng? _positionAtReplayIndex(int index) {
    if (_route.validPoints.isEmpty) return null;
    final int safeIndex = index.clamp(0, _route.validPoints.length - 1);
    return _route.validPoints[safeIndex].position;
  }

  void _setReplayIndex(int index, {bool moveCamera = true}) {
    if (_route.validPoints.isEmpty) return;
    final int safeIndex = index.clamp(0, _route.validPoints.length - 1);
    final LatLng position = _route.validPoints[safeIndex].position;

    setState(() => _replayIndex = safeIndex);
    _replayIndexNotifier.value = safeIndex;
    _hudSpeed.value = _speedAtReplayIndex(safeIndex);

    if (moveCamera) {
      _animatedMove(position, _currentZoom, force: true);
    }
  }

  void _startReplay() {
    if (widget.isLive || _route.validPoints.length < 2) return;
    HapticFeedback.selectionClick();

    if (_replayIndex >= _route.validPoints.length - 1) {
      _setReplayIndex(0, moveCamera: true);
    }

    _stopReplayTimer();
    setState(() => _replayPlaying = true);

    final int millis = (430 / _replaySpeed).round().clamp(80, 600);
    _replayTimer = Timer.periodic(Duration(milliseconds: millis), (_) {
      if (!mounted) return;
      if (_replayIndex >= _route.validPoints.length - 1) {
        _stopReplayTimer();
        if (mounted) setState(() => _replayPlaying = false);
        return;
      }
      _setReplayIndex(_replayIndex + 1, moveCamera: _followMode);
    });
  }

  void _pauseReplay() {
    HapticFeedback.selectionClick();
    _stopReplayTimer();
    if (mounted) setState(() => _replayPlaying = false);
  }

  void _resetReplay() {
    HapticFeedback.selectionClick();
    _stopReplayTimer();
    setState(() => _replayPlaying = false);
    _setReplayIndex(0, moveCamera: true);
  }

  void _setReplaySpeed(double speed) {
    HapticFeedback.selectionClick();
    setState(() => _replaySpeed = speed);
    if (_replayPlaying) _startReplay();
  }

  void _stopReplayTimer() {
    _replayTimer?.cancel();
    _replayTimer = null;
  }

  void _doZoom(int delta) {
    HapticFeedback.selectionClick();

    // FIX: Guard _mapController access with _mapReady flag.
    double base = _currentZoom;
    if (_mapReady && !_isNativeIOS) {
      try {
        base = _mapController.camera.zoom;
      } catch (_) {}
    }

    final double nextZoom =
        (base + delta).clamp(_kMinZoom, _kMaxZoom).toDouble();

    setState(() => _currentZoom = nextZoom);

    if (_isNativeIOS) {
      if (_route.rawPoints.isNotEmpty) {
        _appleMapController.animateTo(_route.rawPoints.last, zoom: nextZoom);
      }
      return;
    }

    if (_mapReady) {
      try {
        _mapController.move(_mapController.camera.center, nextZoom);
      } catch (_) {}
    }
  }

  void _toggleChart() {
    HapticFeedback.selectionClick();
    setState(() => _showChart = !_showChart);
    if (_showChart) {
      _chartRevealController.forward(from: 0.0);
    } else {
      _chartRevealController.reverse();
      _chartScrubIndex.value = -1;
    }
  }

  void _togglePanel() {
    HapticFeedback.selectionClick();
    setState(() => _panelExpanded = !_panelExpanded);
    if (_panelExpanded) {
      _panelSlideController.forward();
    } else {
      _panelSlideController.reverse();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MARKERS
  // ───────────────────────────────────────────────────────────────────────────

  List<fm.Marker> _buildMarkers() {
    if (_route.validPoints.isEmpty) return const <fm.Marker>[];

    final List<fm.Marker> markers = <fm.Marker>[
      _startMarker(_route.validPoints.first.position),
    ];

    if (!widget.isLive && _route.validPoints.length > 1) {
      markers.add(_endMarker(_route.validPoints.last.position));
      final int safeReplayIndex = _replayIndex.clamp(0, _route.validPoints.length - 1);
      markers.add(_replayMarker(_route.validPoints[safeReplayIndex].position));
    } else if (widget.isLive) {
      markers.add(_liveMarker(_route.validPoints.last.position));
    }

    if (_showSpeedGradient && _route.validPoints.length > 10) {
      final int step =
          (_route.validPoints.length / 8).ceil().clamp(25, 80).toInt();
      for (int i = step; i < _route.validPoints.length - 2; i += step) {
        markers.add(_speedTagMarker(_route.validPoints[i]));
      }
    }

    if (_route.peakSpeedIndex >= 0 &&
        _route.peakSpeedIndex < _route.validPoints.length &&
        _route.maxSpeedKmh > 5) {
      markers.add(_peakSpeedMarker(_route.validPoints[_route.peakSpeedIndex]));
    }

    return markers;
  }

  fm.Marker _startMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 36,
      height: 36,
      child: _RouteMarkerDot(
        color: _kTeal,
        icon: CupertinoIcons.flag_fill,
        glowColor: _kTeal,
      ),
    );
  }

  fm.Marker _endMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 36,
      height: 36,
      child: _RouteMarkerDot(
        color: _kRed,
        icon: CupertinoIcons.checkmark_alt,
        glowColor: _kRed,
      ),
    );
  }

  fm.Marker _replayMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 62,
      height: 62,
      child: AnimatedBuilder(
        animation: _markerPulseController,
        builder: (_, __) {
          final double pulse = math.sin(_markerPulseController.value * math.pi)
              .clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 46 + pulse * 10,
                height: 46 + pulse * 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGold.withValues(alpha: 0.10),
                  border: Border.all(
                    color: _kGoldSoft.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                ),
              ),
              Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGoldSoft,
                  border: Border.all(color: Colors.black, width: 3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kGoldSoft.withValues(alpha: 0.55),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.play_fill,
                  color: Colors.black,
                  size: 11,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  fm.Marker _liveMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 88,
      height: 88,
      // FIX: RepaintBoundary is OUTSIDE AnimatedBuilder — it only isolates the
      // repaint boundary from siblings, not from the AnimatedBuilder itself.
      // The correct fix is to keep RepaintBoundary as close to the leaf that
      // changes as possible, wrapping the pulsing ring only.
      child: AnimatedBuilder(
        animation: _markerPulseController,
        builder: (_, __) {
          final double scale = _markerPulseController.value;
          final double opacity = (1.0 - scale).clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Pulsing ring — this changes every frame, isolated.
              RepaintBoundary(
                child: Container(
                  width: 66 * scale,
                  height: 66 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kRed.withValues(alpha: opacity * 0.3),
                    border: Border.all(
                      color: _kRed.withValues(alpha: opacity * 0.6),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              // Bearing arrow — only changes when bearing changes.
              Transform.rotate(
                angle: _route.currentBearing * math.pi / 180.0,
                child: CustomPaint(
                  size: const Size(40, 40),
                  painter: _BearingArrowPainter(color: _kRed),
                ),
              ),
              // Inner dot — static.
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: _kRed, width: 3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kRed.withValues(alpha: 0.7),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  fm.Marker _speedTagMarker(TripPoint point) {
    final Color color = _speedColor(point.speedKmh);
    return fm.Marker(
      point: point.position,
      width: 44,
      height: 24,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(
          point.speedKmh.toStringAsFixed(0),
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  fm.Marker _peakSpeedMarker(TripPoint point) {
    return fm.Marker(
      point: point.position,
      width: 78,
      height: 30,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[_kGoldSoft, _kGold],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _kGold.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(CupertinoIcons.bolt_fill, color: Colors.black, size: 10),
            const SizedBox(width: 3),
            Text(
              '${point.speedKmh.toStringAsFixed(0)} peak',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final List<fm.Marker> allMarkers = _buildMarkers();
    final double topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: <Widget>[
            // ── MAP ──────────────────────────────────────────────────────────
            if (_route.isEmpty)
              const _EmptyMapState()
            else if (_isNativeIOS)
              _AppleMapLayer(
                controller: _appleMapController,
                route: _route,
                showSpeedGradient: _showSpeedGradient,
                followMode: _followMode,
                isLive: widget.isLive,
                markerPulseController: _markerPulseController,
                mapStyle: _mapStyle,
                replayIndex: _replayIndex,
                onUserDrag: () {
                  if (_followMode) setState(() => _followMode = false);
                },
              )
            else
              _FlutterMapLayer(
                mapController: _mapController,
                route: _route,
                allMarkers: allMarkers,
                showSpeedGradient: _showSpeedGradient,
                mapStyle: _mapStyle,
                currentZoom: _currentZoom,
                onMapReady: () => _mapReady = true,
                onZoomChanged: (double zoom) => _currentZoom = zoom,
                onUserDrag: () {
                  if (_followMode) setState(() => _followMode = false);
                },
              ),

            // ── HEADER ───────────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(context, topPad),
            ),

            // ── STYLE PICKER SCRIM ───────────────────────────────────────────
            if (_stylePickerOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _stylePickerOpen = false),
                  child: const SizedBox.expand(),
                ),
              ),

            if (_stylePickerOpen)
              Positioned(
                top: topPad + 66,
                right: 16,
                child: _buildStylePicker(),
              ),

            // ── SPEED HUD ────────────────────────────────────────────────────
            if (!_route.isEmpty)
              ValueListenableBuilder<double>(
                valueListenable: _bottomPanelHeight,
                builder: (_, double panelH, __) => Positioned(
                  left: 16,
                  bottom: panelH + 14,
                  child: _buildSpeedHud(),
                ),
              ),

            // ── ZOOM CONTROLS ─────────────────────────────────────────────
            if (!_route.isEmpty)
              ValueListenableBuilder<double>(
                valueListenable: _bottomPanelHeight,
                builder: (_, double panelH, __) => Positioned(
                  right: 16,
                  bottom: panelH + 14,
                  child: _buildZoomControls(),
                ),
              ),

            // ── BOTTOM PANEL ─────────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(context),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HEADER
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, double topPad) {
    final Duration? elapsed = widget.tripStartTime != null
        ? DateTime.now().difference(widget.tripStartTime!)
        : null;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.only(
            top: topPad + 10,
            bottom: 14,
            left: 14,
            right: 14,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.92),
                Colors.black.withValues(alpha: 0.72),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.07),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              _PressableButton(
                onTap: () => Navigator.of(context).pop(),
                child: const _GlassIconBox(
                  icon: CupertinoIcons.chevron_left,
                  size: 38,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (widget.isLive) ...<Widget>[
                          // FIX: Use shared pulse controller instead of
                          // creating a new AnimationController inside _PulseDot.
                          _PulseDot(
                            color: _kRed,
                            controller: _markerPulseController,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          widget.isLive ? 'LIVE TRACKING' : 'TRIP REPLAY',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          _HeaderChip(
                            label: '${_route.validPoints.length} pts',
                            color: Colors.white24,
                          ),
                          if (elapsed != null) ...<Widget>[
                            const SizedBox(width: 5),
                            _HeaderChip(
                              label: _formatDuration(elapsed),
                              color: Colors.white24,
                              icon: CupertinoIcons.timer,
                            ),
                          ],
                          if (_route.distanceKm > 0) ...<Widget>[
                            const SizedBox(width: 5),
                            _HeaderChip(
                              label: _formatDistance(_route.distanceKm),
                              color: _kGoldSoft,
                              icon: CupertinoIcons.map_pin_ellipse,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PressableButton(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showSpeedGradient = !_showSpeedGradient);
                },
                child: _GlassIconBox(
                  icon: Icons.speed_rounded,
                  size: 38,
                  active: _showSpeedGradient,
                  activeColor: _kGold,
                ),
              ),
              const SizedBox(width: 7),
              _PressableButton(
                onTap: _toggleChart,
                child: _GlassIconBox(
                  icon: CupertinoIcons.graph_square,
                  size: 38,
                  active: _showChart,
                  activeColor: _kBlue,
                ),
              ),
              const SizedBox(width: 7),
              _PressableButton(
                onTap: _cycleMapStyle,
                child: _GlassIconBox(
                  icon: _mapStyle.icon,
                  size: 38,
                  active: _stylePickerOpen,
                  activeColor: _kGold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SPEED HUD — instrument cluster style
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildSpeedHud() {
    return ValueListenableBuilder<double>(
      valueListenable: _hudSpeed,
      builder: (_, double speed, __) {
        final Color accent = _speedColor(speed);

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.82),
                    _kCard.withValues(alpha: 0.75),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: accent.withValues(alpha: 0.22),
                  width: 1,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: 0.15),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Label row
                  Row(
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isLive
                              ? _kRed
                              : Colors.white.withValues(alpha: 0.3),
                          boxShadow: widget.isLive
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: _kRed.withValues(alpha: 0.6),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.isLive ? 'LIVE' : 'SPEED',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.38),
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Numeric value
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder:
                            (Widget child, Animation<double> anim) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          speed.toStringAsFixed(0),
                          key: ValueKey<String>(speed.toStringAsFixed(0)),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'km/h',
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'max ${_route.maxSpeedKmh.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  SizedBox(
                    width: 90,
                    child: Stack(
                      children: <Widget>[
                        Container(
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOut,
                          widthFactor:
                              (speed / 160.0).clamp(0.025, 1.0).toDouble(),
                          child: Container(
                            height: 3.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  accent.withValues(alpha: 0.5),
                                  accent,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.7),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
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
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // STYLE PICKER
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildStylePicker() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (_, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -10 * (1 - t)),
          child: child,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _kCard.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 20,
                ),
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: MapStyle.values.map((MapStyle style) {
                  final bool active = _mapStyle == style;
                  return _PressableButton(
                    onTap: () => _selectStyle(style),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: active
                            ? _kGold.withValues(alpha: 0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active
                              ? _kGold.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            style.icon,
                            color: active ? _kGoldSoft : Colors.white54,
                            size: 15,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            style.label,
                            style: TextStyle(
                              color: active ? _kGoldSoft : Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          if (active) ...<Widget>[
                            const SizedBox(width: 10),
                            const Icon(
                              CupertinoIcons.checkmark_alt,
                              color: _kGoldSoft,
                              size: 11,
                            ),
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

  // ───────────────────────────────────────────────────────────────────────────
  // BOTTOM PANEL
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildBottomPanel(BuildContext context) {
    if (_route.isEmpty) return const SizedBox.shrink();

    return MeasureSize(
      onChange: (Size size) => _bottomPanelHeight.value = size.height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.of(context).padding.bottom + 8,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    _kSurface.withValues(alpha: 0.92),
                    Colors.black.withValues(alpha: 0.88),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Drag handle
                  GestureDetector(
                    onTap: _togglePanel,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: _panelExpanded ? 36 : 48,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    child: _panelExpanded
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (_showChart &&
                                    _route.speedSamples.isNotEmpty)
                                  _buildMiniChart(),
                                if (_showSpeedGradient) ...<Widget>[
                                  const SizedBox(height: 10),
                                  _buildSpeedLegend(),
                                  const SizedBox(height: 12),
                                  Divider(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    height: 1,
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _buildCompactRouteSummaryCard(),
                                if (!widget.isLive &&
                                    _route.validPoints.length > 1) ...<Widget>[
                                  const SizedBox(height: 12),
                                  _buildReplayControls(),
                                ],
                                const SizedBox(height: 12),
                                _buildActionRow(),
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


  Widget _buildCompactRouteSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SummaryMiniStat(
              label: 'DISTANCE',
              value: _formatDistance(_route.distanceKm),
              color: _kTeal,
            ),
          ),
          const _ThinDivider(),
          Expanded(
            child: _SummaryMiniStat(
              label: 'MAX SPEED',
              value: '${_route.maxSpeedKmh.toStringAsFixed(0)} km/h',
              color: _kGoldSoft,
            ),
          ),
          const _ThinDivider(),
          Expanded(
            child: _SummaryMiniStat(
              label: 'AVG SPEED',
              value: '${_route.avgSpeedKmh.toStringAsFixed(0)} km/h',
              color: _kGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplayControls() {
    return ValueListenableBuilder<int>(
      valueListenable: _replayIndexNotifier,
      builder: (_, int index, __) {
        final int total = math.max(1, _route.validPoints.length);
        final double progress = total <= 1 ? 0.0 : index / (total - 1);
        final double replaySpeed = _speedAtReplayIndex(index);

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kGold.withValues(alpha: 0.16)),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _PressableButton(
                    onTap: _replayPlaying ? _pauseReplay : _startReplay,
                    child: _ReplayRoundButton(
                      icon: _replayPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      color: _kGoldSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'TRIP REPLAY',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${index + 1}/$total · ${replaySpeed.toStringAsFixed(0)} km/h',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ReplaySpeedChip(
                    label: '${_replaySpeed.toStringAsFixed(0)}x',
                    onTap: () {
                      final double next = _replaySpeed == 1.0
                          ? 2.0
                          : _replaySpeed == 2.0
                              ? 4.0
                              : 1.0;
                      _setReplaySpeed(next);
                    },
                  ),
                  const SizedBox(width: 8),
                  _PressableButton(
                    onTap: _resetReplay,
                    child: const _ReplayRoundButton(
                      icon: CupertinoIcons.arrow_counterclockwise,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  activeColor: _kGoldSoft,
                  inactiveColor: Colors.white.withValues(alpha: 0.13),
                  onChanged: (double value) {
                    final int nextIndex =
                        (value * (total - 1)).round().clamp(0, total - 1);
                    _setReplayIndex(nextIndex, moveCamera: true);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _PressableButton(
            onTap: _fitRoute,
            child: _ActionTile(
              icon: CupertinoIcons.arrow_down_right_arrow_up_left,
              label: 'FIT ROUTE',
              isActive: false,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PressableButton(
            onTap: _toggleFollow,
            child: _ActionTile(
              icon: _followMode
                  ? CupertinoIcons.location_fill
                  : CupertinoIcons.location,
              label: _followMode ? 'FOLLOWING' : 'FOLLOW',
              isActive: _followMode,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    final bool hasAltitude = _route.maxAltitudeM > 0.0;

    return Row(
      children: <Widget>[
        _StatTile(
          label: 'DISTANCE',
          value: _route.distanceKm >= 1
              ? _route.distanceKm.toStringAsFixed(2)
              : (_route.distanceKm * 1000).toStringAsFixed(0),
          unit: _route.distanceKm >= 1 ? 'KM' : 'M',
          color: _kTeal,
          icon: CupertinoIcons.map,
        ),
        _StatTile(
          label: 'MAX SPD',
          value: _route.maxSpeedKmh.toStringAsFixed(0),
          unit: 'KM/H',
          color: _kGoldSoft,
          icon: CupertinoIcons.bolt_fill,
        ),
        _StatTile(
          label: 'AVG SPD',
          value: _route.avgSpeedKmh.toStringAsFixed(0),
          unit: 'KM/H',
          color: _kGreen,
          icon: CupertinoIcons.speedometer,
        ),
        _StatTile(
          label: hasAltitude ? 'MAX ALT' : 'POINTS',
          value: hasAltitude
              ? _route.maxAltitudeM.toStringAsFixed(0)
              : '${_route.validPoints.length}',
          unit: hasAltitude ? 'M' : 'PTS',
          color: _kRed,
          icon: hasAltitude
              ? CupertinoIcons.arrow_up
              : CupertinoIcons.circle_grid_hex,
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MINI CHART with touch scrubbing
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildMiniChart() {
    final bool hasAltitude = _route.altSamples.any((double v) => v > 0.0);
    final List<double> samples = _chartMode == _ChartMode.speed
        ? _route.speedSamples
        : _route.altSamples;
    final Color chartColor =
        _chartMode == _ChartMode.speed ? _kGoldSoft : _kBlue;
    final String unit = _chartMode == _ChartMode.speed ? 'km/h' : 'm';

    return AnimatedBuilder(
      animation: _chartRevealController,
      builder: (_, __) => Opacity(
        opacity: _chartRevealController.value,
        child: SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: _chartRevealController,
            curve: Curves.easeOutCubic,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 6),
              // Tabs
              Row(
                children: <Widget>[
                  _ChartTab(
                    label: 'SPEED',
                    active: _chartMode == _ChartMode.speed,
                    color: _kGoldSoft,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _chartMode = _ChartMode.speed);
                    },
                  ),
                  const SizedBox(width: 7),
                  if (hasAltitude)
                    _ChartTab(
                      label: 'ALTITUDE',
                      active: _chartMode == _ChartMode.altitude,
                      color: _kBlue,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _chartMode = _ChartMode.altitude);
                      },
                    ),
                  const Spacer(),
                  // Scrub value display
                  ValueListenableBuilder<int>(
                    valueListenable: _chartScrubIndex,
                    builder: (_, int idx, __) {
                      final String label = idx >= 0 && idx < samples.length
                          ? '${samples[idx].toStringAsFixed(1)} $unit'
                          : '';
                      return AnimatedOpacity(
                        opacity: label.isNotEmpty ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: chartColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Chart with scrub gesture
              SizedBox(
                height: 76,
                child: ValueListenableBuilder<int>(
                  valueListenable: _chartScrubIndex,
                  builder: (_, int scrubIdx, __) {
                    return GestureDetector(
                      onHorizontalDragUpdate: (DragUpdateDetails details) {
                        final RenderBox? box =
                            context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final double localX =
                            details.localPosition.dx.clamp(0.0, box.size.width);
                        final int idx =
                            ((localX / box.size.width) * (samples.length - 1))
                                .round()
                                .clamp(0, samples.length - 1);
                        _chartScrubIndex.value = idx;
                      },
                      onHorizontalDragEnd: (_) {
                        Future<void>.delayed(
                          const Duration(milliseconds: 1500),
                          () {
                            if (mounted) _chartScrubIndex.value = -1;
                          },
                        );
                      },
                      child: CustomPaint(
                        size: const Size(double.infinity, 76),
                        painter: _MiniChartPainter(
                          samples: samples,
                          color: chartColor,
                          useSpeedColors: _chartMode == _ChartMode.speed,
                          scrubIndex: scrubIdx,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                color: Colors.white.withValues(alpha: 0.06),
                height: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedLegend() {
    const List<({Color color, String label})> items =
        <({Color color, String label})>[
      (color: _kTeal, label: '<15'),
      (color: _kGreen, label: '15–40'),
      (color: _kGold, label: '40–70'),
      (color: _kOrange, label: '70–100'),
      (color: _kRed, label: '100+'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.map((item) {
          return Column(
            children: <Widget>[
              Container(
                width: 26,
                height: 4,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: item.color.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Column(
      children: <Widget>[
        _PressableButton(
          onTap: () => _doZoom(1),
          child: const _ZoomBox(icon: CupertinoIcons.plus),
        ),
        const SizedBox(height: 8),
        _PressableButton(
          onTap: () => _doZoom(-1),
          child: const _ZoomBox(icon: CupertinoIcons.minus),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI CHART PAINTER
// ─────────────────────────────────────────────────────────────────────────────

// FIX: Cache the ParagraphStyle at class level — allocating it on every paint
// call was unnecessary garbage.
final ui.ParagraphStyle _kLabelParaStyle = ui.ParagraphStyle(
  textDirection: ui.TextDirection.ltr,
);

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({
    required this.samples,
    required this.color,
    this.useSpeedColors = false,
    this.scrubIndex = -1,
  });

  final List<double> samples;
  final Color color;
  final bool useSpeedColors;
  final int scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;

    final double maxVal = samples.reduce(math.max).clamp(1.0, double.infinity);
    final double w = size.width;
    final double h = size.height - 4;
    final int len = samples.length;
    final double denom = math.max(1, len - 1).toDouble();

    final List<Offset> pts = List<Offset>.generate(len, (int i) {
      return Offset((i / denom) * w, h - (samples[i] / maxVal) * h);
    });

    // Fill path
    final ui.Path fillPath = ui.Path()
      ..moveTo(pts.first.dx, h + 4)
      ..lineTo(pts.first.dx, pts.first.dy);

    // Line path
    final ui.Path linePath = ui.Path()..moveTo(pts.first.dx, pts.first.dy);

    for (int i = 0; i < len - 1; i++) {
      final Offset p0 = i > 0 ? pts[i - 1] : pts[i];
      final Offset p1 = pts[i];
      final Offset p2 = pts[i + 1];
      final Offset p3 = i + 2 < len ? pts[i + 2] : p2;

      final double cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final double cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final double cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final double cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      linePath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    fillPath
      ..lineTo(pts.last.dx, h + 4)
      ..close();

    // Draw fill
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h + 4)),
    );

    // Grid lines
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 0.5;

    for (int tick = 0; tick <= 2; tick++) {
      final double value = maxVal * tick / 2;
      final double y = h - (value / maxVal) * h;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);

      final ui.ParagraphBuilder builder = ui.ParagraphBuilder(_kLabelParaStyle)
        ..pushStyle(
          ui.TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
          ),
        )
        ..addText(value.toStringAsFixed(0));

      final ui.Paragraph para = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 40));
      canvas.drawParagraph(para, Offset(2, y - 9));
    }

    // Line
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Speed dots
    if (useSpeedColors && len > 4) {
      final int step = (len / 12).ceil().clamp(1, len);
      final Paint dotPaint = Paint()..style = PaintingStyle.fill;
      for (int i = 0; i < pts.length; i += step) {
        dotPaint.color = _speedColor(samples[i]);
        canvas.drawCircle(pts[i], 2.5, dotPaint);
      }
    }

    // Scrub crosshair
    if (scrubIndex >= 0 && scrubIndex < pts.length) {
      final Offset scrubPt = pts[scrubIndex];

      // Vertical line
      canvas.drawLine(
        Offset(scrubPt.dx, 0),
        Offset(scrubPt.dx, h + 4),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );

      // Dot
      canvas.drawCircle(
        scrubPt,
        5,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        scrubPt,
        5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) {
    // FIX: List identity check is correct for immutable lists from utils.
    // Also check scrubIndex for crosshair updates.
    return !identical(oldDelegate.samples, samples) ||
        oldDelegate.color != color ||
        oldDelegate.useSpeedColors != useSpeedColors ||
        oldDelegate.scrubIndex != scrubIndex;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLUTTER MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _FlutterMapLayer extends StatelessWidget {
  const _FlutterMapLayer({
    required this.mapController,
    required this.route,
    required this.allMarkers,
    required this.showSpeedGradient,
    required this.mapStyle,
    required this.currentZoom,
    required this.onMapReady,
    required this.onZoomChanged,
    required this.onUserDrag,
  });

  final fm.MapController mapController;
  final _RouteData route;
  final List<fm.Marker> allMarkers;
  final bool showSpeedGradient;
  final MapStyle mapStyle;
  final double currentZoom;
  final VoidCallback onMapReady;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onUserDrag;

  Widget _buildSmoothPolylineLayer() {
    final Color color = mapStyle.routeColor;

    return fm.PolylineLayer(
      polylines: <fm.Polyline>[
        fm.Polyline(
          points: route.smoothedPoints,
          color: color.withValues(alpha: _kRouteGlowOpacity),
          strokeWidth: 16,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: route.smoothedPoints,
          color: color.withValues(alpha: 0.4),
          strokeWidth: 7,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: route.smoothedPoints,
          color: color,
          strokeWidth: 3.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }

  Widget _buildSpeedGradientLayer() {
    // FIX: Build all polylines in one pass with pre-allocated capacity.
    final List<fm.Polyline> polylines = <fm.Polyline>[];

    for (int i = 0; i < route.speedSegments.length; i++) {
      final _SpeedSegment seg = route.speedSegments[i];
      if (seg.points.length < 2) continue;

      polylines
        ..add(fm.Polyline(
          points: seg.points,
          color: seg.color.withValues(alpha: 0.2),
          strokeWidth: 13,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ))
        ..add(fm.Polyline(
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
    // FIX: Read retinaMode once — no MediaQuery.devicePixelRatioOf inside a
    // builder that could run often.
    final bool retina = MediaQuery.devicePixelRatioOf(context) > 1.0;

    return fm.FlutterMap(
      mapController: mapController,
      options: fm.MapOptions(
        initialCenter: route.rawPoints.isNotEmpty
            ? route.rawPoints.last
            : const LatLng(0, 0),
        initialZoom: currentZoom,
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
        ),
        onMapReady: onMapReady,
        onMapEvent: (fm.MapEvent event) {
          if (event is fm.MapEventMove) {
            onZoomChanged(event.camera.zoom);
          }
          if (event is fm.MapEventMoveStart &&
              event.source != fm.MapEventSource.mapController) {
            onUserDrag();
          }
        },
      ),
      children: <Widget>[
        fm.TileLayer(
          key: ValueKey<MapStyle>(mapStyle),
          urlTemplate: mapStyle.tileUrlTemplate,
          subdomains: mapStyle.subdomains,
          userAgentPackageName: 'com.trackpro.ai',
          retinaMode: retina,
        ),
        if (route.smoothedPoints.length > 1)
          showSpeedGradient
              ? _buildSpeedGradientLayer()
              : _buildSmoothPolylineLayer(),
        if (allMarkers.isNotEmpty) fm.MarkerLayer(markers: allMarkers),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEARING ARROW PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _BearingArrowPainter extends CustomPainter {
  const _BearingArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2.0;
    final double cy = size.height / 2.0;

    canvas.drawPath(
      ui.Path()
        ..moveTo(cx, cy - 16)
        ..lineTo(cx - 6, cy + 2)
        ..lineTo(cx, cy - 2)
        ..lineTo(cx + 6, cy + 2)
        ..close(),
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _BearingArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// LATLNG TWEEN
// ─────────────────────────────────────────────────────────────────────────────

class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    return LatLng(
      begin!.latitude + (end!.latitude - begin!.latitude) * t,
      begin!.longitude + (end!.longitude - begin!.longitude) * t,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEASURE SIZE
// ─────────────────────────────────────────────────────────────────────────────

class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    required Widget child,
  }) : super(child: child);

  final void Function(Size) onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      SizeObserverRenderBox(onChange: onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant SizeObserverRenderBox renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class SizeObserverRenderBox extends RenderProxyBox {
  SizeObserverRenderBox({required this.onChange});

  void Function(Size) onChange;
  Size? _previousSize;

  @override
  void performLayout() {
    super.performLayout();
    final Size newSize = child?.size ?? Size.zero;
    final Size? prev = _previousSize;
    if (prev == null ||
        (prev.width - newSize.width).abs() > 0.5 ||
        (prev.height - newSize.height).abs() > 0.5) {
      _previousSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // FIX: Check attached before calling onChange to avoid calling a
        // potentially stale closure after unmount.
        if (attached) onChange(newSize);
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASSES
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedSegment {
  _SpeedSegment({required this.points, required this.color});

  final List<LatLng> points;
  final Color color;
}

enum _ChartMode { speed, altitude }

// ─────────────────────────────────────────────────────────────────────────────
// APPLE MAP CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────

class _AppleMapController {
  _AppleMapLayerState? _state;

  void _attach(_AppleMapLayerState state) => _state = state;
  void _detach() => _state = null;

  // FIX: All public methods null-check _state — concurrent detach-then-call is safe.
  void animateTo(LatLng position, {double zoom = 16.0}) =>
      _state?._animateTo(position, zoom: zoom);

  void fitPoints(List<LatLng> points) => _state?._fitPoints(points);

  void notifyStyleChanged() => _state?._onStyleChanged();

  void dispose() => _detach();
}

// ─────────────────────────────────────────────────────────────────────────────
// APPLE MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _AppleMapLayer extends StatefulWidget {
  const _AppleMapLayer({
    required this.controller,
    required this.route,
    required this.showSpeedGradient,
    required this.followMode,
    required this.isLive,
    required this.markerPulseController,
    required this.mapStyle,
    required this.replayIndex,
    required this.onUserDrag,
  });

  final _AppleMapController controller;
  final _RouteData route;
  final bool showSpeedGradient;
  final bool followMode;
  final bool isLive;
  final AnimationController markerPulseController;
  final MapStyle mapStyle;
  final int replayIndex;
  final VoidCallback onUserDrag;

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
  void didUpdateWidget(covariant _AppleMapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach();
      widget.controller._attach(this);
    }

    final bool pointChanged =
        oldWidget.route.validPoints.length != widget.route.validPoints.length ||
            !identical(oldWidget.route, widget.route);

    if (pointChanged &&
        widget.followMode &&
        widget.isLive &&
        widget.route.rawPoints.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _animateTo(widget.route.rawPoints.last);
      });
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  void _animateTo(LatLng position, {double zoom = 16.0}) {
    if (!_isValidLatLng(position)) return;
    _mkController?.animateCamera(
      mk.CameraUpdate.newCameraPosition(
        mk.CameraPosition(
          target: mk.LatLng(position.latitude, position.longitude),
          zoom: zoom,
        ),
      ),
    );
  }

  void _fitPoints(List<LatLng> points) {
    final List<LatLng> valid =
        points.where(_isValidLatLng).toList(growable: false);
    if (valid.isEmpty) return;

    // FIX: Use calculatePolylineBounds from utils instead of manual min/max loop.
    final LatLngBoundsLite? bounds = calculatePolylineBounds(valid);
    if (bounds == null) return;

    _mkController?.animateCamera(
      mk.CameraUpdate.newLatLngBounds(
        mk.LatLngBounds(
          southwest:
              mk.LatLng(bounds.southWest.latitude, bounds.southWest.longitude),
          northeast:
              mk.LatLng(bounds.northEast.latitude, bounds.northEast.longitude),
        ),
        80,
      ),
    );
  }

  void _onStyleChanged() {
    if (mounted) setState(() {});
  }

  Set<mk.Polyline> _buildPolylines() {
    final Set<mk.Polyline> polylines = <mk.Polyline>{};
    int id = 0;

    final Color routeColor = widget.mapStyle.routeColor;

    if (widget.showSpeedGradient) {
      for (final _SpeedSegment seg in widget.route.speedSegments) {
        if (seg.points.length < 2) continue;
        final List<mk.LatLng> pts = seg.points
            .where(_isValidLatLng)
            .map((LatLng p) => mk.LatLng(p.latitude, p.longitude))
            .toList(growable: false);
        if (pts.length < 2) continue;

        polylines.add(mk.Polyline(
          polylineId: mk.PolylineId('seg_${id++}'),
          points: pts,
          color: seg.color,
          width: 5,
        ));
      }
    } else if (widget.route.smoothedPoints.length > 1) {
      final List<mk.LatLng> pts = widget.route.smoothedPoints
          .where(_isValidLatLng)
          .map((LatLng p) => mk.LatLng(p.latitude, p.longitude))
          .toList(growable: false);

      if (pts.length > 1) {
        polylines
          ..add(mk.Polyline(
            polylineId: mk.PolylineId('route_glow'),
            points: pts,
            color: routeColor.withValues(alpha: 0.18),
            width: 12,
          ))
          ..add(mk.Polyline(
            polylineId: mk.PolylineId('route_mid'),
            points: pts,
            color: routeColor.withValues(alpha: 0.42),
            width: 7,
          ))
          ..add(mk.Polyline(
            polylineId: mk.PolylineId('route_solid'),
            points: pts,
            color: routeColor,
            width: 4,
          ));
      }
    }

    return polylines;
  }

  Set<mk.Annotation> _buildAnnotations() {
    final Set<mk.Annotation> annotations = <mk.Annotation>{};
    if (widget.route.validPoints.isEmpty) return annotations;

    annotations.add(mk.Annotation(
      annotationId: mk.AnnotationId('start'),
      position: mk.LatLng(
        widget.route.validPoints.first.position.latitude,
        widget.route.validPoints.first.position.longitude,
      ),
      infoWindow: mk.InfoWindow(title: 'Start'),
      icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
          mk.BitmapDescriptor.hueCyan),
    ));

    if (!widget.isLive && widget.route.validPoints.length > 1) {
      annotations.add(mk.Annotation(
        annotationId: mk.AnnotationId('end'),
        position: mk.LatLng(
          widget.route.validPoints.last.position.latitude,
          widget.route.validPoints.last.position.longitude,
        ),
        infoWindow: mk.InfoWindow(title: 'End'),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueRed),
      ));
      final int safeReplayIndex = widget.replayIndex.clamp(
        0,
        widget.route.validPoints.length - 1,
      );
      final TripPoint replayPoint = widget.route.validPoints[safeReplayIndex];
      annotations.add(mk.Annotation(
        annotationId: mk.AnnotationId('replay'),
        position: mk.LatLng(
          replayPoint.position.latitude,
          replayPoint.position.longitude,
        ),
        infoWindow: mk.InfoWindow(
          title: 'Replay ${safeReplayIndex + 1}/${widget.route.validPoints.length}',
        ),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
          mk.BitmapDescriptor.hueYellow,
        ),
      ));
    } else if (widget.isLive) {
      annotations.add(mk.Annotation(
        annotationId: mk.AnnotationId('live'),
        position: mk.LatLng(
          widget.route.validPoints.last.position.latitude,
          widget.route.validPoints.last.position.longitude,
        ),
        infoWindow: mk.InfoWindow(title: 'Live'),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueRed),
      ));
    }

    if (widget.route.peakSpeedIndex >= 0 &&
        widget.route.peakSpeedIndex < widget.route.validPoints.length) {
      final TripPoint peak =
          widget.route.validPoints[widget.route.peakSpeedIndex];
      annotations.add(mk.Annotation(
        annotationId: mk.AnnotationId('peak'),
        position: mk.LatLng(peak.position.latitude, peak.position.longitude),
        infoWindow: mk.InfoWindow(
          title: '⚡ ${peak.speedKmh.toStringAsFixed(0)} km/h peak',
        ),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueYellow),
      ));
    }

    return annotations;
  }

  @override
  Widget build(BuildContext context) {
    final mk.LatLng target = widget.route.rawPoints.isNotEmpty
        ? mk.LatLng(
            widget.route.rawPoints.last.latitude,
            widget.route.rawPoints.last.longitude,
          )
        : mk.LatLng(0, 0);

    return mk.AppleMap(
      initialCameraPosition:
          mk.CameraPosition(target: target, zoom: _kDefaultZoom),
      mapType: widget.mapStyle.appleMapType,
      rotateGesturesEnabled: false,
      polylines: _buildPolylines(),
      annotations: _buildAnnotations(),
      onMapCreated: (mk.AppleMapController controller) {
        _mkController = controller;
        if (widget.route.rawPoints.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _animateTo(widget.route.rawPoints.last);
          });
        }
      },
      onCameraMoveStarted: widget.onUserDrag,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL UI COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

/// Pressable wrapper that scales down on tap for tactile feedback.
class _PressableButton extends StatefulWidget {
  const _PressableButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 180),
    value: 1.0,
    lowerBound: 0.88,
    upperBound: 1.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _ctrl.reverse().then((_) => _ctrl.forward());
        widget.onTap();
      },
      onTapDown: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.forward(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, Widget? child) =>
            Transform.scale(scale: _ctrl.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class _GlassIconBox extends StatelessWidget {
  const _GlassIconBox({
    required this.icon,
    required this.size,
    this.active = false,
    this.activeColor = _kGold,
  });

  final IconData icon;
  final double size;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active
            ? activeColor.withValues(alpha: 0.14)
            : _kCard.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? activeColor.withValues(alpha: 0.5) : _kCardBorder,
          width: active ? 1.5 : 1,
        ),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.2),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        color: active ? activeColor : Colors.white54,
        size: 17,
      ),
    );
  }
}

/// Header route-info chip.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: color, size: 9),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Round marker dot used for start/end.
class _RouteMarkerDot extends StatelessWidget {
  const _RouteMarkerDot({
    required this.color,
    required this.icon,
    required this.glowColor,
  });

  final Color color;
  final IconData icon;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: glowColor.withValues(alpha: 0.55),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 13),
    );
  }
}

/// FIX: Accepts a shared AnimationController instead of creating its own,
/// eliminating the extra controller per live-update cycle.
class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color, required this.controller});

  final Color color;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Map 0→1 repeat to a pulse (0→1→0) via sin.
        final double t = math.sin(controller.value * math.pi).clamp(0.0, 1.0);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.5 + t * 0.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: t * 0.65),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}


class _SummaryMiniStat extends StatelessWidget {
  const _SummaryMiniStat({
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _ReplayRoundButton extends StatelessWidget {
  const _ReplayRoundButton({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }
}

class _ReplaySpeedChip extends StatelessWidget {
  const _ReplaySpeedChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _kGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kGold.withValues(alpha: 0.20)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _kGoldSoft,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color.withValues(alpha: 0.8), size: 11),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              unit,
              style: TextStyle(
                color: color.withValues(alpha: 0.5),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartTab extends StatelessWidget {
  const _ChartTab({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: isActive
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  _kGold.withValues(alpha: 0.18),
                  _kGoldDim.withValues(alpha: 0.08),
                ],
              )
            : null,
        color: isActive ? null : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? _kGold.withValues(alpha: 0.45) : _kCardBorder,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 15, color: isActive ? _kGoldSoft : Colors.white60),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? _kGoldSoft : Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomBox extends StatelessWidget {
  const _ZoomBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: _kCardBorder),
          ),
          child: Icon(icon, color: Colors.white70, size: 19),
        ),
      ),
    );
  }
}

class _EmptyMapState extends StatefulWidget {
  const _EmptyMapState();

  @override
  State<_EmptyMapState> createState() => _EmptyMapStateState();
}

class _EmptyMapStateState extends State<_EmptyMapState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Animated scanning ring
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) {
                    return Transform.rotate(
                      angle: _ctrl.value * 2 * math.pi,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.transparent,
                          ),
                          gradient: SweepGradient(
                            colors: <Color>[
                              _kGold.withValues(alpha: 0.0),
                              _kGold.withValues(alpha: 0.5),
                              _kGold.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kGold.withValues(alpha: 0.07),
                    border: Border.all(
                      color: _kGold.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    CupertinoIcons.map,
                    color: _kGoldSoft,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'No Route Data',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start tracking to see your route,\nspeed graph, and live map here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              height: 1.55,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
