// ignore_for_file: unused_element, deprecated_member_use

import 'dart:async';
import 'dart:convert';
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
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../models/trip_data.dart';
import '../utils/smooth_polyline.dart';
import '../config/mapbox_config.dart';


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
const String _kMapboxAccessToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
  defaultValue: MapboxConfig.accessToken,
);

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
    final String token = _kMapboxAccessToken;

    // Mapbox needs an access token. Run with:
    // flutter run --dart-define=MAPBOX_ACCESS_TOKEN=pk.your_token_here
    if (token.isEmpty) {
      debugPrint(
        'MAPBOX_ACCESS_TOKEN is empty. Falling back to ArcGIS tiles.',
      );

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

    final String styleId = switch (this) {
      MapStyle.dark => 'navigation-night-v1',
      MapStyle.light => 'navigation-day-v1',
      MapStyle.satellite => 'satellite-streets-v12',
    };

    return 'https://api.mapbox.com/styles/v1/mapbox/$styleId/'
        'tiles/512/{z}/{x}/{y}@2x?access_token=$token';
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
// MAPBOX FEATURE MODELS
// ─────────────────────────────────────────────────────────────────────────────

enum _MapboxRuntimeMode {
  auto,
  native,
  webFallback,
}

extension _MapboxRuntimeModeUi on _MapboxRuntimeMode {
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
        return 'Native on Android, Apple Maps on iOS, fallback on Web';
      case _MapboxRuntimeMode.native:
        return 'Force native Mapbox where supported';
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

extension _MapboxStandardPresetUi on _MapboxStandardPreset {
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

extension _DirectionsProfileUi on _DirectionsProfile {
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

  String get distanceLabel {
    final double km = distanceMeters / 1000.0;
    return _formatDistance(km);
  }

  String durationLabel() {
    final int total = durationSeconds.round().clamp(0, 1 << 31);
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m';
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

  _MapboxRuntimeMode _mapboxRuntimeMode = _MapboxRuntimeMode.auto;
  _MapboxStandardPreset _mapboxPreset = _MapboxStandardPreset.day;
  _PlannedRoute? _plannedRoute;
  bool _directionsLoading = false;

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
    _hudSpeed.value =
        widget.isLive ? _route.lastSpeedKmh : _speedAtReplayIndex(_replayIndex);

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

  bool get _shouldUseNativeMapbox {
    if (kIsWeb || _isNativeIOS) return false;
    if (_mapboxRuntimeMode == _MapboxRuntimeMode.webFallback) return false;
    return _mapboxRuntimeMode == _MapboxRuntimeMode.auto ||
        _mapboxRuntimeMode == _MapboxRuntimeMode.native;
  }

  LatLng? get _routePlanningStart {
    if (_route.rawPoints.isNotEmpty) {
      if (widget.isLive) return _route.rawPoints.last;
      return _positionAtReplayIndex(_replayIndex) ?? _route.rawPoints.first;
    }
    return null;
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

    if (_shouldUseNativeMapbox) {
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

    if (_shouldUseNativeMapbox) {
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
    if (_mapReady && !_isNativeIOS && !_shouldUseNativeMapbox) {
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

    if (_shouldUseNativeMapbox) {
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

  void _openMapboxControls() {
    HapticFeedback.lightImpact();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MapboxControlsSheet(
        mapboxRuntimeMode: _mapboxRuntimeMode,
        mapboxPreset: _mapboxPreset,
        plannedRoute: _plannedRoute,
        directionsLoading: _directionsLoading,
        onRuntimeChanged: (mode) {
          if (!mounted) return;
          setState(() => _mapboxRuntimeMode = mode);
        },
        onPresetChanged: (preset) {
          if (!mounted) return;
          setState(() => _mapboxPreset = preset);
        },
        onPlanRoute: _planDirectionsRoute,
        onClearRoute: () {
          if (!mounted) return;
          setState(() => _plannedRoute = null);
          Navigator.of(context).maybePop();
        },
      ),
    );
  }

  Future<void> _planDirectionsRoute({
    required double destinationLat,
    required double destinationLng,
    required _DirectionsProfile profile,
  }) async {
    final LatLng? start = _routePlanningStart;
    if (start == null || !_isValidLatLng(start)) {
      _showSnack('Start position is not ready.');
      return;
    }

    final LatLng destination = LatLng(destinationLat, destinationLng);
    if (!_isValidLatLng(destination)) {
      _showSnack('Destination coordinate is invalid.');
      return;
    }

    if (_kMapboxAccessToken.isEmpty) {
      _showSnack('Mapbox token is missing.');
      return;
    }

    setState(() => _directionsLoading = true);

    try {
      final Uri uri = Uri.https(
        'api.mapbox.com',
        '/directions/v5/${profile.apiProfile}/'
            '${start.longitude},${start.latitude};'
            '${destination.longitude},${destination.latitude}',
        <String, String>{
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

      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Mapbox Directions error ${response.statusCode}: '
            '${response.body}');
        _showSnack('Route planning failed (${response.statusCode}).');
        return;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _showSnack('Route response is invalid.');
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
        if (_isValidLatLng(point)) points.add(point);
      }

      if (points.length < 2) {
        _showSnack('Route has no usable geometry.');
        return;
      }

      setState(() {
        _plannedRoute = _PlannedRoute(
          points: List<LatLng>.unmodifiable(points),
          distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0.0,
          durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0.0,
          profile: profile,
        );
      });

      Navigator.of(context).maybePop();
      _showSnack('Route planned.');
    } on TimeoutException {
      if (mounted) _showSnack('Route request timed out.');
    } catch (error, stackTrace) {
      debugPrint('Directions planning error: $error\n$stackTrace');
      if (mounted) _showSnack('Route planning failed.');
    } finally {
      if (mounted) setState(() => _directionsLoading = false);
    }
  }

  void _showSnack(String message) {
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
      final int safeReplayIndex =
          _replayIndex.clamp(0, _route.validPoints.length - 1);
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
      child: const _RouteMarkerDot(
        color: _kTeal,
        icon: CupertinoIcons.flag_fill,
        glowColor: _kTeal,
      ),
    );
  }

  fm.Marker _endMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 42,
      height: 42,
      alignment: Alignment.center,
      child: const _WhiteRouteNode(),
    );
  }

  fm.Marker _replayMarker(LatLng position) {
    final int safeIndex = _replayIndex.clamp(0, _route.validPoints.length - 1);
    final double bearing = safeIndex > 0
        ? _bearingOrZero(
            _route.validPoints[safeIndex - 1].position,
            _route.validPoints[safeIndex].position,
          )
        : _route.currentBearing;

    return fm.Marker(
      point: position,
      width: 96,
      height: 96,
      alignment: Alignment.center,
      child: _MapVehicleMarker(
        bearing: bearing,
        kind: _MapVehicleKind.car,
        pulseController: _markerPulseController,
      ),
    );
  }

  fm.Marker _liveMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 96,
      height: 96,
      alignment: Alignment.center,
      child: _MapLocationPuck(
        bearing: _route.currentBearing,
        pulseController: _markerPulseController,
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
              _EmptyMapState(
                mapStyle: _mapStyle,
                isLive: widget.isLive,
              )
            else if (_shouldUseNativeMapbox)
              _NativeMapboxLayer(
                route: _route,
                plannedRoute: _plannedRoute,
                mapStyle: _mapStyle,
                mapboxPreset: _mapboxPreset,
                followMode: _followMode,
                isLive: widget.isLive,
                replayIndex: _replayIndex,
                onUserDrag: () {
                  if (_followMode) setState(() => _followMode = false);
                },
              )
            else if (_isNativeIOS)
              _AppleMapLayer(
                controller: _appleMapController,
                route: _route,
                plannedRoute: _plannedRoute,
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
                plannedRoute: _plannedRoute,
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
                onTap: _openMapboxControls,
                child: _GlassIconBox(
                  icon: CupertinoIcons.location_north_line_fill,
                  size: 38,
                  active: _plannedRoute != null,
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
                                if (_plannedRoute != null) ...<Widget>[
                                  const SizedBox(height: 10),
                                  _buildPlannedRouteSummaryCard(),
                                ],
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

  Widget _buildPlannedRouteSummaryCard() {
    final _PlannedRoute? route = _plannedRoute;
    if (route == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBlue.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.location_north_line_fill,
            color: _kBlue,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${route.distanceLabel} · ${route.durationLabel()} · ${route.profile.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PressableButton(
            onTap: () => setState(() => _plannedRoute = null),
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: Colors.white54,
              size: 18,
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
            child: const _ActionTile(
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
        const SizedBox(width: 10),
        Expanded(
          child: _PressableButton(
            onTap: _openMapboxControls,
            child: _ActionTile(
              icon: CupertinoIcons.location_north_line_fill,
              label: _plannedRoute == null ? 'ROUTE' : 'PLANNED',
              isActive: _plannedRoute != null,
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
// NATIVE MAPBOX LAYER — Android/mobile only. Web uses flutter_map fallback.
// ─────────────────────────────────────────────────────────────────────────────

class _NativeMapboxLayer extends StatefulWidget {
  const _NativeMapboxLayer({
    required this.route,
    required this.plannedRoute,
    required this.mapStyle,
    required this.mapboxPreset,
    required this.followMode,
    required this.isLive,
    required this.replayIndex,
    required this.onUserDrag,
  });

  final _RouteData route;
  final _PlannedRoute? plannedRoute;
  final MapStyle mapStyle;
  final _MapboxStandardPreset mapboxPreset;
  final bool followMode;
  final bool isLive;
  final int replayIndex;
  final VoidCallback onUserDrag;

  @override
  State<_NativeMapboxLayer> createState() => _NativeMapboxLayerState();
}

class _NativeMapboxLayerState extends State<_NativeMapboxLayer> {
  mb.MapboxMap? _map;
  mb.PolylineAnnotationManager? _routeOuterManager;
  mb.PolylineAnnotationManager? _routeCoreManager;
  mb.PolylineAnnotationManager? _plannedOuterManager;
  mb.PolylineAnnotationManager? _plannedCoreManager;
  bool _styleLoaded = false;

  @override
  void didUpdateWidget(covariant _NativeMapboxLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.mapStyle != widget.mapStyle) {
      unawaited(_loadStyle());
      return;
    }

    if (oldWidget.mapboxPreset != widget.mapboxPreset) {
      unawaited(_configureStandardStyle());
    }

    if (!identical(oldWidget.route, widget.route) ||
        oldWidget.replayIndex != widget.replayIndex ||
        oldWidget.plannedRoute != widget.plannedRoute) {
      unawaited(_rebuildRoutes());
      unawaited(_moveCamera());
    }
  }

  void _onMapCreated(mb.MapboxMap map) {
    _map = map;
    unawaited(_configureMap());
  }

  Future<void> _configureMap() async {
    final mb.MapboxMap? map = _map;
    if (map == null) return;

    try {
      await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
      await map.compass.updateSettings(mb.CompassSettings(enabled: false));
      await map.logo.updateSettings(mb.LogoSettings(enabled: true));
      await map.attribution
          .updateSettings(mb.AttributionSettings(enabled: true));
      await map.location.updateSettings(
        mb.LocationComponentSettings(
          enabled: widget.isLive,
          puckBearingEnabled: true,
          puckBearing: mb.PuckBearing.HEADING,
          pulsingEnabled: widget.isLive,
          pulsingColor: _kBlue.value,
          pulsingMaxRadius: 46,
          showAccuracyRing: widget.isLive,
          accuracyRingColor: _kBlue.withValues(alpha: 0.18).value,
          accuracyRingBorderColor: _kBlue.withValues(alpha: 0.42).value,
        ),
      );
    } catch (error) {
      debugPrint('Native Mapbox map config error: $error');
    }

    await _loadStyle();
  }

  Future<void> _loadStyle() async {
    final mb.MapboxMap? map = _map;
    if (map == null) return;

    _styleLoaded = false;
    try {
      await map.loadStyleURI(_styleUri(widget.mapStyle));
      _styleLoaded = true;
      _routeOuterManager = null;
      _routeCoreManager = null;
      _plannedOuterManager = null;
      _plannedCoreManager = null;
      await _configureStandardStyle();
      await _rebuildRoutes();
      await _moveCamera(force: true);
    } catch (error, stackTrace) {
      debugPrint('Native Mapbox style error: $error\n$stackTrace');
    }
  }

  Future<void> _configureStandardStyle() async {
    final mb.MapboxMap? map = _map;
    if (map == null) return;

    try {
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'lightPreset',
        widget.mapboxPreset.mapboxValue,
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
      debugPrint('Native Mapbox Standard config skipped: $error');
    }
  }

  Future<void> _rebuildRoutes() async {
    final mb.MapboxMap? map = _map;
    if (map == null || !_styleLoaded) return;

    try {
      _plannedOuterManager ??=
          await map.annotations.createPolylineAnnotationManager();
      _plannedCoreManager ??=
          await map.annotations.createPolylineAnnotationManager();
      _routeOuterManager ??=
          await map.annotations.createPolylineAnnotationManager();
      _routeCoreManager ??=
          await map.annotations.createPolylineAnnotationManager();

      await _plannedOuterManager?.deleteAll();
      await _plannedCoreManager?.deleteAll();
      await _routeOuterManager?.deleteAll();
      await _routeCoreManager?.deleteAll();

      final _PlannedRoute? planned = widget.plannedRoute;
      if (planned != null && planned.points.length > 1) {
        await _drawLine(
          outer: _plannedOuterManager,
          core: _plannedCoreManager,
          points: planned.points,
          color: _kBlue,
          outerWidth: 11,
          coreWidth: 5.2,
        );
      }

      if (widget.route.smoothedPoints.length > 1) {
        await _drawLine(
          outer: _routeOuterManager,
          core: _routeCoreManager,
          points: widget.route.smoothedPoints,
          color: const Color(0xFF3B22FF),
          outerWidth: 13,
          coreWidth: 6.5,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Native Mapbox route draw error: $error\n$stackTrace');
    }
  }

  Future<void> _drawLine({
    required mb.PolylineAnnotationManager? outer,
    required mb.PolylineAnnotationManager? core,
    required List<LatLng> points,
    required Color color,
    required double outerWidth,
    required double coreWidth,
  }) async {
    final List<mb.Position> coords = points
        .where(_isValidLatLng)
        .map((LatLng p) => mb.Position(p.longitude, p.latitude))
        .toList(growable: false);

    if (coords.length < 2) return;

    final mb.LineString line = mb.LineString(coordinates: coords);

    await outer?.create(
      mb.PolylineAnnotationOptions(
        geometry: line,
        lineColor: Colors.white.value,
        lineWidth: outerWidth,
        lineOpacity: 0.86,
        lineBorderColor: Colors.black.value,
        lineBorderWidth: 2.0,
        lineJoin: mb.LineJoin.ROUND,
      ),
    );

    await core?.create(
      mb.PolylineAnnotationOptions(
        geometry: line,
        lineColor: color.value,
        lineWidth: coreWidth,
        lineOpacity: 0.96,
        lineJoin: mb.LineJoin.ROUND,
      ),
    );
  }

  Future<void> _moveCamera({bool force = false}) async {
    final mb.MapboxMap? map = _map;
    if (map == null || widget.route.rawPoints.isEmpty) return;

    final LatLng? target = widget.isLive
        ? widget.route.rawPoints.last
        : _positionAtReplayIndex(widget.replayIndex);
    if (target == null || !_isValidLatLng(target)) return;

    try {
      await map.easeTo(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(target.longitude, target.latitude),
          ),
          zoom: _kDefaultZoom,
          pitch: widget.followMode ? 48 : 0,
          bearing: widget.followMode ? -widget.route.currentBearing : 0,
        ),
        mb.MapAnimationOptions(duration: force ? 650 : 420, startDelay: 0),
      );
    } catch (error) {
      debugPrint('Native Mapbox camera error: $error');
    }
  }

  LatLng? _positionAtReplayIndex(int index) {
    if (widget.route.validPoints.isEmpty) return null;
    final int safeIndex = index.clamp(0, widget.route.validPoints.length - 1);
    return widget.route.validPoints[safeIndex].position;
  }

  static String _styleUri(MapStyle style) {
    if (style == MapStyle.satellite) return mb.MapboxStyles.STANDARD_SATELLITE;
    return mb.MapboxStyles.STANDARD;
  }

  @override
  Widget build(BuildContext context) {
    final LatLng center = widget.route.rawPoints.isNotEmpty
        ? widget.route.rawPoints.last
        : const LatLng(11.5564, 104.9282);

    return mb.MapWidget(
      key: ValueKey<String>(
        'mapbox-${widget.mapStyle.name}-${widget.mapboxPreset.name}',
      ),
      styleUri: _styleUri(widget.mapStyle),
      viewport: mb.CameraViewportState(
        center: mb.Point(
          coordinates: mb.Position(center.longitude, center.latitude),
        ),
        zoom: _kDefaultZoom,
        pitch: 0,
        bearing: 0,
      ),
      textureView: true,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: (_) {
        _styleLoaded = true;
        unawaited(_configureStandardStyle());
        unawaited(_rebuildRoutes());
        unawaited(_moveCamera(force: true));
      },
      onScrollListener: (_) => widget.onUserDrag(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLUTTER MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _FlutterMapLayer extends StatelessWidget {
  const _FlutterMapLayer({
    required this.mapController,
    required this.route,
    required this.plannedRoute,
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
  final _PlannedRoute? plannedRoute;
  final List<fm.Marker> allMarkers;
  final bool showSpeedGradient;
  final MapStyle mapStyle;
  final double currentZoom;
  final VoidCallback onMapReady;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onUserDrag;

  Widget _buildPlannedRouteLayer() {
    final _PlannedRoute? route = plannedRoute;
    if (route == null || route.points.length < 2) {
      return const SizedBox.shrink();
    }

    return fm.PolylineLayer(
      polylines: <fm.Polyline>[
        fm.Polyline(
          points: route.points,
          color: Colors.white.withValues(alpha: 0.82),
          strokeWidth: 11.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: route.points,
          color: _kBlue.withValues(alpha: 0.94),
          strokeWidth: 5.4,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }

  Widget _buildSmoothPolylineLayer() {
    return fm.PolylineLayer(
      polylines: <fm.Polyline>[
        fm.Polyline(
          points: route.smoothedPoints,
          color: Colors.black.withValues(alpha: 0.72),
          strokeWidth: 15.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: route.smoothedPoints,
          color: Colors.white.withValues(alpha: 0.96),
          strokeWidth: 13.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: route.smoothedPoints,
          color: const Color(0xFF3B22FF).withValues(alpha: 0.94),
          strokeWidth: 8.8,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: route.smoothedPoints,
          color: const Color(0xFF1600B8).withValues(alpha: 0.95),
          strokeWidth: 5.8,
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
        _buildPlannedRouteLayer(),
        if (route.smoothedPoints.length > 1)
          showSpeedGradient
              ? _buildSpeedGradientLayer()
              : _buildSmoothPolylineLayer(),
        if (allMarkers.isNotEmpty) fm.MarkerLayer(markers: allMarkers),
      ],
    );
  }
}

class _MapLocationPuck extends StatelessWidget {
  const _MapLocationPuck({
    required this.bearing,
    required this.pulseController,
  });

  final double bearing;
  final Animation<double> pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) {
        final double pulse = pulseController.value;
        final double pulseOpacity = (1.0 - pulse).clamp(0.0, 1.0);

        return SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A73FF).withValues(alpha: 0.10),
                  border: Border.all(
                    color: const Color(0xFF1A73FF).withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                ),
              ),
              Opacity(
                opacity: pulseOpacity * 0.34,
                child: Container(
                  width: 24 + pulse * 44,
                  height: 24 + pulse * 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A73FF),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.40),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: bearing * math.pi / 180.0,
                child: CustomPaint(
                  size: const Size(74, 74),
                  painter: _MapLocationConePainter(
                    color: const Color(0xFF1A73FF),
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A73FF),
                  border: Border.all(
                    color: Colors.white,
                    width: 3.2,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF1A73FF).withValues(alpha: 0.45),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: bearing * math.pi / 180.0,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 42),
                  child: Icon(
                    CupertinoIcons.location_fill,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapLocationConePainter extends CustomPainter {
  const _MapLocationConePainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);
    final double radius = size.width * 0.42;

    final ui.Path cone = ui.Path()
      ..moveTo(center.dx, center.dy - radius)
      ..cubicTo(
        center.dx - radius * 0.35,
        center.dy - radius * 0.28,
        center.dx - radius * 0.22,
        center.dy - radius * 0.04,
        center.dx,
        center.dy,
      )
      ..cubicTo(
        center.dx + radius * 0.22,
        center.dy - radius * 0.04,
        center.dx + radius * 0.35,
        center.dy - radius * 0.28,
        center.dx,
        center.dy - radius,
      )
      ..close();

    final Paint paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        <Color>[
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.00),
        ],
        <double>[0.0, 1.0],
      );

    canvas.drawPath(cone, paint);
  }

  @override
  bool shouldRepaint(covariant _MapLocationConePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

enum _MapVehicleKind {
  car,
  motorbike,
}

class _MapVehicleMarker extends StatelessWidget {
  const _MapVehicleMarker({
    required this.bearing,
    required this.kind,
    required this.pulseController,
  });

  final double bearing;
  final _MapVehicleKind kind;
  final Animation<double> pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) {
        final double pulse = pulseController.value;
        final double opacity = (1.0 - pulse).clamp(0.0, 1.0);
        return SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              RepaintBoundary(
                child: Container(
                  width: 32 + pulse * 28,
                  height: 32 + pulse * 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2A5BFF)
                        .withValues(alpha: opacity * 0.18),
                    border: Border.all(
                      color: const Color(0xFF2A5BFF)
                          .withValues(alpha: opacity * 0.34),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.92),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.rotate(
                angle: bearing * math.pi / 180.0,
                child: Transform.translate(
                  offset: const Offset(0, -10),
                  child: kind == _MapVehicleKind.motorbike
                      ? const _MapMiniMotorbike()
                      : const _MapMiniCar(),
                ),
              ),
              Positioned(
                bottom: 18,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapMiniCar extends StatelessWidget {
  const _MapMiniCar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            bottom: 4,
            child: Container(
              width: 38,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            bottom: 13,
            child: Container(
              width: 38,
              height: 43,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.white, Color(0xFFE8EDF6)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(0xFFCAD3DF), width: 1.2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 9,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 16,
            child: Container(
              width: 25,
              height: 14,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF88C7F5), Color(0xFF2E6A99)],
                ),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white, width: 1.0),
              ),
            ),
          ),
          const Positioned(bottom: 20, left: 5, child: _MapVehicleWheel()),
          const Positioned(bottom: 20, right: 5, child: _MapVehicleWheel()),
          const Positioned(bottom: 13, left: 7, child: _MapTailLight()),
          const Positioned(bottom: 13, right: 7, child: _MapTailLight()),
        ],
      ),
    );
  }
}

class _MapMiniMotorbike extends StatelessWidget {
  const _MapMiniMotorbike();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            bottom: 2,
            child: Container(
              width: 40,
              height: 15,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const Positioned(bottom: 10, child: _MapBikeWheel(size: 20)),
          const Positioned(top: 23, child: _MapBikeWheel(size: 18)),
          Positioned(
            top: 31,
            child: Container(
              width: 24,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF1F2329),
                borderRadius: BorderRadius.circular(8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 25,
            child: Container(
              width: 32,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFD8DEE8)),
              ),
            ),
          ),
          Positioned(
            top: 11,
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapVehicleWheel extends StatelessWidget {
  const _MapVehicleWheel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E23),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MapTailLight extends StatelessWidget {
  const _MapTailLight();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MapBikeWheel extends StatelessWidget {
  const _MapBikeWheel({
    required this.size,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF15171B),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF40464F), width: 3),
      ),
    );
  }
}

class _WhiteRouteNode extends StatelessWidget {
  const _WhiteRouteNode();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 31,
      height: 31,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
    required this.plannedRoute,
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
  final _PlannedRoute? plannedRoute;
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
          title:
              'Replay ${safeReplayIndex + 1}/${widget.route.validPoints.length}',
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

class _MapboxControlsSheet extends StatefulWidget {
  const _MapboxControlsSheet({
    required this.mapboxRuntimeMode,
    required this.mapboxPreset,
    required this.plannedRoute,
    required this.directionsLoading,
    required this.onRuntimeChanged,
    required this.onPresetChanged,
    required this.onPlanRoute,
    required this.onClearRoute,
  });

  final _MapboxRuntimeMode mapboxRuntimeMode;
  final _MapboxStandardPreset mapboxPreset;
  final _PlannedRoute? plannedRoute;
  final bool directionsLoading;
  final ValueChanged<_MapboxRuntimeMode> onRuntimeChanged;
  final ValueChanged<_MapboxStandardPreset> onPresetChanged;
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
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  _DirectionsProfile _profile = _DirectionsProfile.drivingTraffic;

  @override
  void initState() {
    super.initState();
    _latCtrl = TextEditingController();
    _lngCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final double? lat = double.tryParse(_latCtrl.text.trim());
    final double? lng = double.tryParse(_lngCtrl.text.trim());

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter destination latitude and longitude.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await widget.onPlanRoute(
      destinationLat: lat,
      destinationLng: lng,
      profile: _profile,
    );
  }

  void _useDemoPoint() {
    _latCtrl.text = '11.5621';
    _lngCtrl.text = '104.8885';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 54),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Row(
                    children: <Widget>[
                      Icon(
                        CupertinoIcons.location_north_line_fill,
                        color: _kBlue,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'MAPBOX CONTROLS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _MapboxControlCard(
                    title: 'Standard preset',
                    subtitle: 'Day, dusk, dawn, night',
                    child: _MapboxInlineButton(
                      label: widget.mapboxPreset.label,
                      icon: CupertinoIcons.sparkles,
                      color: _kGoldSoft,
                      onTap: () =>
                          widget.onPresetChanged(widget.mapboxPreset.next),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MapboxControlCard(
                    title: 'Native / Web fallback',
                    subtitle: widget.mapboxRuntimeMode.description,
                    child: _MapboxInlineButton(
                      label: widget.mapboxRuntimeMode.label,
                      icon: CupertinoIcons.arrow_2_circlepath,
                      color: _kGreen,
                      onTap: () => widget
                          .onRuntimeChanged(widget.mapboxRuntimeMode.next),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MapboxControlCard(
                    title: 'Directions API route planning',
                    subtitle: 'Plan from replay/current point to destination',
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _CoordinateField(
                                controller: _latCtrl,
                                placeholder: 'Lat',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CoordinateField(
                                controller: _lngCtrl,
                                placeholder: 'Lng',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _MapboxInlineButton(
                                label: _profile.label,
                                icon: CupertinoIcons.car_detailed,
                                color: _kBlue,
                                onTap: () {
                                  setState(() => _profile = _profile.next);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 92,
                              child: _MapboxInlineButton(
                                label: 'DEMO',
                                icon: CupertinoIcons.map_pin_ellipse,
                                color: _kGoldSoft,
                                onTap: _useDemoPoint,
                                fullWidth: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _MapboxInlineButton(
                          label: widget.directionsLoading
                              ? 'PLANNING...'
                              : 'PLAN ROUTE',
                          icon: widget.directionsLoading
                              ? CupertinoIcons.hourglass
                              : CupertinoIcons.location_fill,
                          color: _kGreen,
                          onTap: widget.directionsLoading ? () {} : _submit,
                        ),
                      ],
                    ),
                  ),
                  if (widget.plannedRoute != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _MapboxControlCard(
                      title: 'Planned route',
                      subtitle:
                          '${widget.plannedRoute!.distanceLabel} · ${widget.plannedRoute!.durationLabel()} · ${widget.plannedRoute!.profile.label}',
                      child: _MapboxInlineButton(
                        label: 'CLEAR ROUTE',
                        icon: CupertinoIcons.xmark_circle_fill,
                        color: _kRed,
                        onTap: widget.onClearRoute,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapboxControlCard extends StatelessWidget {
  const _MapboxControlCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinateField extends StatelessWidget {
  const _CoordinateField({
    required this.controller,
    required this.placeholder,
  });

  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      placeholderStyle: const TextStyle(
        color: Colors.white38,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
    );
  }
}

class _MapboxInlineButton extends StatelessWidget {
  const _MapboxInlineButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.fullWidth = true,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final Widget content = _PressableButton(
      onTap: onTap,
      child: Container(
        height: 42,
        width: fullWidth ? double.infinity : null,
        constraints: fullWidth
            ? const BoxConstraints.expand(height: 42)
            : const BoxConstraints(
                minWidth: 74,
                maxWidth: 150,
                minHeight: 42,
                maxHeight: 42,
              ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 7),
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, height: 42, child: content);
    }

    return SizedBox(height: 42, child: content);
  }
}

class _EmptyMapState extends StatefulWidget {
  const _EmptyMapState({
    required this.mapStyle,
    required this.isLive,
  });

  final MapStyle mapStyle;
  final bool isLive;

  @override
  State<_EmptyMapState> createState() => _EmptyMapStateState();
}

class _EmptyMapStateState extends State<_EmptyMapState>
    with SingleTickerProviderStateMixin {
  static const LatLng _fallbackCenter = LatLng(11.5564, 104.9282);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  final fm.MapController _emptyMapController = fm.MapController();

  @override
  void dispose() {
    _ctrl.dispose();
    try {
      _emptyMapController.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool retina = MediaQuery.devicePixelRatioOf(context) > 1.0;
    final String title =
        widget.isLive ? 'Waiting for GPS Route' : 'No Saved Route Points';
    final String subtitle = widget.isLive
        ? 'Start tracking and move a short distance\nto draw your live route here.'
        : 'This trip has no saved GPS points.\nSave a trip with route points to replay it.';

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: fm.FlutterMap(
            mapController: _emptyMapController,
            options: const fm.MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 14.5,
              interactionOptions: fm.InteractionOptions(
                flags: fm.InteractiveFlag.drag |
                    fm.InteractiveFlag.pinchZoom |
                    fm.InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: <Widget>[
              fm.TileLayer(
                key: ValueKey<MapStyle>(widget.mapStyle),
                urlTemplate: widget.mapStyle.tileUrlTemplate,
                subdomains: widget.mapStyle.subdomains,
                maxZoom: _kMaxZoom,
                minZoom: _kMinZoom,
                retinaMode: retina,
                userAgentPackageName: 'com.trackpro.ai',
                tileBuilder: (_, Widget tile, __) {
                  if (widget.mapStyle == MapStyle.dark) {
                    return ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.18),
                        BlendMode.darken,
                      ),
                      child: tile,
                    );
                  }
                  return tile;
                },
                errorTileCallback: (
                  fm.TileImage tile,
                  Object error,
                  StackTrace? stackTrace,
                ) {
                  debugPrint('EmptyMap tile error: $error');
                },
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.72),
                  _kBg.withValues(alpha: 0.94),
                ],
                stops: const <double>[0.0, 0.58, 1.0],
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 104,
                  height: 104,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, __) {
                          final double value = _ctrl.value;
                          return Container(
                            width: 54 + value * 38,
                            height: 54 + value * 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _kGold.withValues(
                                alpha: (1.0 - value) * 0.12,
                              ),
                              border: Border.all(
                                color: _kGold.withValues(
                                  alpha: (1.0 - value) * 0.24,
                                ),
                                width: 1.4,
                              ),
                            ),
                          );
                        },
                      ),
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: <Color>[
                              _kGoldSoft.withValues(alpha: 0.35),
                              _kGold.withValues(alpha: 0.16),
                              Colors.black.withValues(alpha: 0.36),
                            ],
                          ),
                          border: Border.all(
                            color: _kGold.withValues(alpha: 0.24),
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: _kGold.withValues(alpha: 0.18),
                              blurRadius: 22,
                            ),
                          ],
                        ),
                        child: const Icon(
                          CupertinoIcons.map,
                          color: _kGoldSoft,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.52),
                    height: 1.48,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.045),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                  child: Text(
                    widget.isLive
                        ? 'Need at least 2 GPS points'
                        : '0 saved route points',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.44),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
