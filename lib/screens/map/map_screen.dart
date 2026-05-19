// ignore_for_file: unused_element, deprecated_member_use, prefer_final_fields, prefer_const_constructors

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../../models/trip_data.dart';
import '../../models/mapbox_route_models.dart';
import '../../utils/smooth_polyline.dart';
import '../../services/mapbox_directions_service.dart';
import '../../config/mapbox_config.dart';

import '../../widgets/route_planner_sheet.dart';
import '../../theme/app_theme.dart';

part 'map_native_layer.dart';
part 'map_fallback_layer.dart';
part 'map_markers.dart';
part 'map_bottom_panel.dart';
part 'map_replay_controls.dart';



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

const Color _kBlue = AppColors.blue;
const Color _kBlueSoft = AppColors.blueSoft;
const Color _kBlueDeep = AppColors.blueDeep;
const Color _kRed = AppColors.red;
const Color _kGreen = AppColors.green;
const Color _kBg = AppColors.black;
const Color _kCard = AppColors.surface;
const Color _kCardBorder = AppColors.border;
const Color _kSurface = AppColors.card;
const Color _kWhiteText = AppColors.white;
const Color _kMutedWhite = AppColors.white70;
const LinearGradient _kBlueGlassGradient = AppColors.blueGlassGradient;

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
  standard,
  standardSatellite,
  streets,
  outdoors,
  light,
  dark,
  satellite,
  satelliteStreets,
  navigationDay,
  navigationNight;

  String get label {
    switch (this) {
      case MapStyle.standard:
        return 'STANDARD';
      case MapStyle.standardSatellite:
        return 'STD SAT';
      case MapStyle.streets:
        return 'STREETS';
      case MapStyle.outdoors:
        return 'OUTDOOR';
      case MapStyle.light:
        return 'LIGHT';
      case MapStyle.dark:
        return 'DARK';
      case MapStyle.satellite:
        return 'SAT';
      case MapStyle.satelliteStreets:
        return 'SAT ROAD';
      case MapStyle.navigationDay:
        return 'NAV DAY';
      case MapStyle.navigationNight:
        return 'NAV NIGHT';
    }
  }

  String get fullLabel {
    switch (this) {
      case MapStyle.standard:
        return 'Mapbox Standard';
      case MapStyle.standardSatellite:
        return 'Standard Satellite';
      case MapStyle.streets:
        return 'Streets';
      case MapStyle.outdoors:
        return 'Outdoors';
      case MapStyle.light:
        return 'Light';
      case MapStyle.dark:
        return 'Dark';
      case MapStyle.satellite:
        return 'Satellite';
      case MapStyle.satelliteStreets:
        return 'Satellite Streets';
      case MapStyle.navigationDay:
        return 'Navigation Day';
      case MapStyle.navigationNight:
        return 'Navigation Night';
    }
  }

  String get description {
    switch (this) {
      case MapStyle.standard:
        return 'Default configurable basemap with modern 3D elements.';
      case MapStyle.standardSatellite:
        return 'Satellite imagery blended with Standard 3D layers.';
      case MapStyle.streets:
        return 'General-purpose road and transit readability.';
      case MapStyle.outdoors:
        return 'Best for hiking, biking and fitness tracking.';
      case MapStyle.light:
        return 'Subtle grayscale map for bright overlays.';
      case MapStyle.dark:
        return 'Dark map for night use and dark UI.';
      case MapStyle.satellite:
        return 'Pure aerial imagery without roads or labels.';
      case MapStyle.satelliteStreets:
        return 'Satellite imagery with roads and labels.';
      case MapStyle.navigationDay:
        return 'High-contrast daytime driving style.';
      case MapStyle.navigationNight:
        return 'Dark dashboard navigation style.';
    }
  }

  IconData get icon {
    switch (this) {
      case MapStyle.standard:
        return CupertinoIcons.cube_box_fill;
      case MapStyle.standardSatellite:
        return CupertinoIcons.globe;
      case MapStyle.streets:
        return CupertinoIcons.map_fill;
      case MapStyle.outdoors:
        return CupertinoIcons.tree;
      case MapStyle.light:
        return CupertinoIcons.sun_max_fill;
      case MapStyle.dark:
        return CupertinoIcons.moon_fill;
      case MapStyle.satellite:
        return CupertinoIcons.photo_fill;
      case MapStyle.satelliteStreets:
        return CupertinoIcons.map_pin_ellipse;
      case MapStyle.navigationDay:
        return CupertinoIcons.car_detailed;
      case MapStyle.navigationNight:
        return CupertinoIcons.car_detailed;
    }
  }

  String get mapboxStyleId {
    switch (this) {
      case MapStyle.standard:
        return 'standard';
      case MapStyle.standardSatellite:
        return 'standard-satellite';
      case MapStyle.streets:
        return 'streets-v12';
      case MapStyle.outdoors:
        return 'outdoors-v12';
      case MapStyle.light:
        return 'light-v11';
      case MapStyle.dark:
        return 'dark-v11';
      case MapStyle.satellite:
        return 'satellite-v9';
      case MapStyle.satelliteStreets:
        return 'satellite-streets-v12';
      case MapStyle.navigationDay:
        return 'navigation-day-v1';
      case MapStyle.navigationNight:
        return 'navigation-night-v1';
    }
  }

  String get styleUri => 'mapbox://styles/mapbox/$mapboxStyleId';

  String get tileUrlTemplate {
    final String token = _kMapboxAccessToken;

    if (token.isEmpty) {
      debugPrint(
        'MAPBOX_ACCESS_TOKEN is empty. Falling back to ArcGIS tiles.',
      );

      switch (this) {
        case MapStyle.light:
        case MapStyle.standard:
        case MapStyle.streets:
        case MapStyle.outdoors:
        case MapStyle.navigationDay:
          return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
              'Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
        case MapStyle.satellite:
        case MapStyle.satelliteStreets:
        case MapStyle.standardSatellite:
          return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
              'World_Imagery/MapServer/tile/{z}/{y}/{x}';
        case MapStyle.dark:
        case MapStyle.navigationNight:
          return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
              'Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      }
    }

    return 'https://api.mapbox.com/styles/v1/mapbox/$mapboxStyleId/'
        'tiles/512/{z}/{x}/{y}@2x?access_token=$token';
  }

  List<String> get subdomains => const <String>[];

  bool get isDark {
    switch (this) {
      case MapStyle.dark:
      case MapStyle.navigationNight:
        return true;
      default:
        return false;
    }
  }

  bool get isSatellite {
    switch (this) {
      case MapStyle.satellite:
      case MapStyle.satelliteStreets:
      case MapStyle.standardSatellite:
        return true;
      default:
        return false;
    }
  }

  bool get isStandardFamily {
    switch (this) {
      case MapStyle.standard:
      case MapStyle.standardSatellite:
        return true;
      default:
        return false;
    }
  }

  Color get routeColor {
    if (isSatellite) return Colors.white;
    if (this == MapStyle.outdoors) return _kGreen;
    if (this == MapStyle.navigationDay) return _kBlue;
    if (this == MapStyle.navigationNight) return _kBlueSoft;
    return _kBlue;
  }

  MapStyle get next {
    final List<MapStyle> styles = MapStyle.values;
    final int nextIndex = (index + 1) % styles.length;
    return styles[nextIndex];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAPBOX FEATURE MODELS
// ─────────────────────────────────────────────────────────────────────────────







// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

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
  if (!kmh.isFinite || kmh <= 0.0) return _kBlueSoft;
  if (kmh < 15) return _kBlueSoft;
  if (kmh < 40) return _kBlue;
  if (kmh < 70) return Colors.white;
  if (kmh < 100) return _kBlueDeep;
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
// PREMIUM MAP UX FEATURE MODES
// ─────────────────────────────────────────────────────────────────────────────

enum _PanelDockMode {
  mini,
  compact,
  expanded,
}

enum _ReplayCameraMode {
  follow,
  cinematic,
  orbit,
  free,
}

enum _QuickActionMenuState {
  closed,
  open,
}

extension _PanelDockModeX on _PanelDockMode {
  String get label {
    switch (this) {
      case _PanelDockMode.mini:
        return 'MINI';
      case _PanelDockMode.compact:
        return 'COMPACT';
      case _PanelDockMode.expanded:
        return 'FULL';
    }
  }

  bool get isExpanded => this == _PanelDockMode.expanded;
  bool get isCompact => this == _PanelDockMode.compact;
  bool get isMini => this == _PanelDockMode.mini;
}

extension _ReplayCameraModeX on _ReplayCameraMode {
  String get label {
    switch (this) {
      case _ReplayCameraMode.follow:
        return 'FOLLOW';
      case _ReplayCameraMode.cinematic:
        return 'CINEMA';
      case _ReplayCameraMode.orbit:
        return 'ORBIT';
      case _ReplayCameraMode.free:
        return 'FREE';
    }
  }

  IconData get icon {
    switch (this) {
      case _ReplayCameraMode.follow:
        return CupertinoIcons.location_fill;
      case _ReplayCameraMode.cinematic:
        return CupertinoIcons.film_fill;
      case _ReplayCameraMode.orbit:
        return CupertinoIcons.rotate_right;
      case _ReplayCameraMode.free:
        return CupertinoIcons.hand_draw_fill;
    }
  }

  _ReplayCameraMode get next {
    switch (this) {
      case _ReplayCameraMode.follow:
        return _ReplayCameraMode.cinematic;
      case _ReplayCameraMode.cinematic:
        return _ReplayCameraMode.orbit;
      case _ReplayCameraMode.orbit:
        return _ReplayCameraMode.free;
      case _ReplayCameraMode.free:
        return _ReplayCameraMode.follow;
    }
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
  _RouteData _route = _RouteData.empty;

  bool _followMode = true;
  bool _showSpeedGradient = false;
  bool _panelExpanded = true;

  // PREMIUM FEATURE STATE
  _PanelDockMode _panelDockMode = _PanelDockMode.expanded;
  _ReplayCameraMode _replayCameraMode = _ReplayCameraMode.follow;
  _QuickActionMenuState _quickActionMenuState = _QuickActionMenuState.closed;
  bool _floatingHudMini = false;
  bool _floatingHudLocked = false;
  Offset _floatingHudOffset = const Offset(16, 132);
  double _cinematicOrbitAngle = 0.0;
  bool _stylePickerOpen = false;
  bool _showChart = false;
  bool _mapReady = false;
  bool _replayPlaying = false;

  MapboxRuntimeMode _mapboxRuntimeMode = MapboxRuntimeMode.auto;
  MapboxStandardPreset _mapboxPreset = MapboxStandardPreset.day;
  PlannedRoute? _plannedRoute;
  bool _directionsLoading = false;

  int _replayIndex = 0;
  double _replaySpeed = 1.0;
  Timer? _replayTimer;

  _ChartMode _chartMode = _ChartMode.speed;
  MapStyle _mapStyle = MapStyle.standard;

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
        if (mounted) {
          _animatedMove(
            newRoute.rawPoints.last,
            _appleMapsZoomForSpeed(newRoute.lastSpeedKmh),
          );
        }
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
    try {
      _mapController.dispose();
    } catch (_) {}

    super.dispose();
  }

  bool get _shouldUseNativeMapbox {
    if (kIsWeb) return false;

    // Trip Replay needs a replay puck that follows `_replayIndex`.
    // Native Mapbox location puck follows the real device location only,
    // so replay mode uses the flutter_map layer with our custom replay marker.
    if (!widget.isLive) return false;

    if (_mapboxRuntimeMode == MapboxRuntimeMode.webFallback) return false;
    return _mapboxRuntimeMode == MapboxRuntimeMode.auto ||
        _mapboxRuntimeMode == MapboxRuntimeMode.native;
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
      _premiumFollowLatest();
    }
  }

  void _selectStyle(MapStyle style) {
    HapticFeedback.selectionClick();
    setState(() {
      _mapStyle = style;
      _stylePickerOpen = false;
      _quickActionMenuState = _QuickActionMenuState.closed;
    });
  }

  void _cycleMapStyle() {
    HapticFeedback.selectionClick();
    setState(() {
      _mapStyle = _mapStyle.next;
      _stylePickerOpen = false;
      _quickActionMenuState = _QuickActionMenuState.closed;
    });
  }

  double _speedAtReplayIndex(int index) {
    if (_route.validPoints.isEmpty) return 0.0;
    final int safeIndex = index.clamp(0, _route.validPoints.length - 1).toInt();
    return _route.validPoints[safeIndex].speedKmh;
  }

  LatLng? _positionAtReplayIndex(int index) {
    if (_route.validPoints.isEmpty) return null;
    final int safeIndex = index.clamp(0, _route.validPoints.length - 1).toInt();
    return _route.validPoints[safeIndex].position;
  }

  void _setReplayIndex(int index, {bool moveCamera = true}) {
    if (_route.validPoints.isEmpty) return;
    final int safeIndex = index.clamp(0, _route.validPoints.length - 1).toInt();
    final LatLng position = _route.validPoints[safeIndex].position;

    setState(() => _replayIndex = safeIndex);
    _replayIndexNotifier.value = safeIndex;
    _hudSpeed.value = _speedAtReplayIndex(safeIndex);

    if (moveCamera) {
      if (widget.isLive) {
        _animatedMove(position, _appleMapsZoomForSpeed(_speedAtReplayIndex(safeIndex)), force: true);
      } else {
        _moveReplayCamera(position, force: true);
      }
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

    final int millis = (430 / _replaySpeed).round().clamp(80, 600).toInt();
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
    final double safeSpeed = speed.clamp(0.5, 4.0).toDouble();
    if (_replaySpeed == safeSpeed) return;

    final bool wasPlaying = _replayPlaying;
    HapticFeedback.selectionClick();

    _stopReplayTimer();
    setState(() {
      _replaySpeed = safeSpeed;
      _replayPlaying = wasPlaying;
    });

    if (wasPlaying) _startReplay();
  }

  void _stopReplayTimer() {
    _replayTimer?.cancel();
    _replayTimer = null;
  }

  void _doZoom(int delta) {
    HapticFeedback.selectionClick();

    // FIX: Guard _mapController access with _mapReady flag.
    double base = _currentZoom;
    if (_mapReady && !_shouldUseNativeMapbox) {
      try {
        base = _mapController.camera.zoom;
      } catch (_) {}
    }

    final double nextZoom =
        (base + delta).clamp(_kMinZoom, _kMaxZoom).toDouble();

    setState(() => _currentZoom = nextZoom);

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

    if (_panelDockMode == _PanelDockMode.expanded) {
      _setPanelDockMode(_PanelDockMode.compact);
    } else {
      _setPanelDockMode(_PanelDockMode.expanded);
    }
  }

  void _setMapState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }


  // ───────────────────────────────────────────────────────────────────────────
  // PREMIUM FEATURE CONTROLS
  // ───────────────────────────────────────────────────────────────────────────

  void _setPanelDockMode(_PanelDockMode mode) {
    if (_panelDockMode == mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _panelDockMode = mode;
      _panelExpanded = mode != _PanelDockMode.mini;
    });

    if (mode == _PanelDockMode.expanded) {
      _panelSlideController.forward();
    } else if (mode == _PanelDockMode.mini) {
      _panelSlideController.reverse();
    }
  }

  void _cyclePanelDockMode() {
    switch (_panelDockMode) {
      case _PanelDockMode.expanded:
        _setPanelDockMode(_PanelDockMode.compact);
        break;
      case _PanelDockMode.compact:
        _setPanelDockMode(_PanelDockMode.mini);
        break;
      case _PanelDockMode.mini:
        _setPanelDockMode(_PanelDockMode.expanded);
        break;
    }
  }

  void _handlePanelVerticalDragEnd(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0.0;

    if (velocity > 220) {
      if (_panelDockMode == _PanelDockMode.expanded) {
        _setPanelDockMode(_PanelDockMode.compact);
      } else {
        _setPanelDockMode(_PanelDockMode.mini);
      }
      return;
    }

    if (velocity < -220) {
      if (_panelDockMode == _PanelDockMode.mini) {
        _setPanelDockMode(_PanelDockMode.compact);
      } else {
        _setPanelDockMode(_PanelDockMode.expanded);
      }
    }
  }

  void _toggleQuickActionMenu() {
    HapticFeedback.selectionClick();
    setState(() {
      _quickActionMenuState =
          _quickActionMenuState == _QuickActionMenuState.open
              ? _QuickActionMenuState.closed
              : _QuickActionMenuState.open;
    });
  }

  void _closeQuickActionMenu() {
    if (_quickActionMenuState == _QuickActionMenuState.closed) return;
    setState(() => _quickActionMenuState = _QuickActionMenuState.closed);
  }

  void _toggleFloatingHudMini() {
    if (_floatingHudLocked) return;
    HapticFeedback.selectionClick();
    setState(() {
      _floatingHudMini = !_floatingHudMini;
      _floatingHudOffset = _clampFloatingHudOffset(_floatingHudOffset);
    });
  }

  void _toggleFloatingHudLock() {
    HapticFeedback.mediumImpact();
    setState(() => _floatingHudLocked = !_floatingHudLocked);
  }

  Offset _clampFloatingHudOffset(Offset value) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    final double hudWidth = _floatingHudMini ? 78.0 : 120.0;
    final double hudHeight = _floatingHudMini ? 74.0 : 116.0;

    final double minX = 8.0;
    final double maxX = math.max(minX, screen.width - hudWidth - 8.0);
    final double minY = padding.top + 72.0;
    final double maxY = math.max(minY, screen.height - hudHeight - padding.bottom - 98.0);

    return Offset(
      value.dx.clamp(minX, maxX).toDouble(),
      value.dy.clamp(minY, maxY).toDouble(),
    );
  }

  void _updateFloatingHudOffset(DragUpdateDetails details) {
    if (_floatingHudLocked) return;
    final Offset next = _clampFloatingHudOffset(_floatingHudOffset + details.delta);
    if (next == _floatingHudOffset) return;
    setState(() => _floatingHudOffset = next);
  }

  void _snapFloatingHudToEdge() {
    if (_floatingHudLocked) return;
    final Size screen = MediaQuery.sizeOf(context);
    final double hudWidth = _floatingHudMini ? 78.0 : 120.0;
    final double targetX =
        _floatingHudOffset.dx + hudWidth / 2.0 < screen.width / 2.0
            ? 12.0
            : screen.width - hudWidth - 12.0;
    setState(() {
      _floatingHudOffset = _clampFloatingHudOffset(
        Offset(targetX, _floatingHudOffset.dy),
      );
    });
  }

  void _cycleReplayCameraMode() {
    HapticFeedback.selectionClick();
    setState(() => _replayCameraMode = _replayCameraMode.next);

    final LatLng? target = _positionAtReplayIndex(_replayIndex);
    if (target != null && _replayCameraMode != _ReplayCameraMode.free) {
      _moveReplayCamera(target, force: true);
    }
  }

  void _moveReplayCamera(LatLng position, {bool force = false}) {
    if (!_isValidLatLng(position)) return;

    switch (_replayCameraMode) {
      case _ReplayCameraMode.free:
        return;
      case _ReplayCameraMode.follow:
        _animatedMove(position, _currentZoom, force: force);
        return;
      case _ReplayCameraMode.cinematic:
        _animatedMove(position, math.max(_currentZoom, 16.8), force: true);
        return;
      case _ReplayCameraMode.orbit:
        _cinematicOrbitAngle = (_cinematicOrbitAngle + 18.0) % 360.0;
        _animatedMove(position, math.max(_currentZoom, 16.2), force: true);
        return;
    }
  }

  double _appleMapsZoomForSpeed(double kmh) {
    if (!kmh.isFinite || kmh <= 5.0) return 17.3;
    if (kmh < 30.0) return 16.9;
    if (kmh < 70.0) return 16.2;
    if (kmh < 110.0) return 15.5;
    return 14.9;
  }

  void _premiumFollowLatest() {
    final LatLng? target =
        widget.isLive ? (_route.rawPoints.isEmpty ? null : _route.rawPoints.last) : _positionAtReplayIndex(_replayIndex);
    if (target == null) return;

    final double speed = widget.isLive ? _route.lastSpeedKmh : _speedAtReplayIndex(_replayIndex);
    _animatedMove(target, _appleMapsZoomForSpeed(speed), force: true);
  }

  void _openMapboxControls() {
    HapticFeedback.lightImpact();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RoutePlannerSheet<DirectionsProfile,
          MapboxStandardPreset, MapboxRuntimeMode>(
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
        initialPreset: _mapboxPreset,
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
        initialRuntime: _mapboxRuntimeMode,
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
        directionsLoading: _directionsLoading,
        plannedRoute: _plannedRoute == null
            ? null
            : PlannedRouteSummary.fromRoute(_plannedRoute!),
        currentPositionProvider: () => _routePlanningStart,
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
    required DirectionsProfile profile,
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

    setState(() => _directionsLoading = true);

    try {
      final MapboxDirectionsService service = MapboxDirectionsService(
        accessToken: _kMapboxAccessToken,
      );

      final PlannedRoute route = await service.planRoute(
        start: start,
        destination: destination,
        profile: profile,
      );

      if (!mounted) return;

      setState(() => _plannedRoute = route);

      Navigator.of(context).maybePop();
      _showSnack('Route planned.');
    } on MapboxDirectionsException catch (error) {
      if (mounted) _showSnack(error.message);
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
  // BUILD
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final List<fm.Marker> allMarkers = _buildMarkers();
    final MediaQueryData media = MediaQuery.of(context);
    final double topPad = media.padding.top;
    final Size viewportSize = media.size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // ── MAP ──────────────────────────────────────────────────────────
            if (_route.isEmpty)
              RepaintBoundary(
                child: _EmptyMapState(
                mapStyle: _mapStyle,
                isLive: widget.isLive,
                ),
              )
            else if (_shouldUseNativeMapbox)
              RepaintBoundary(
                child: _NativeMapboxLayer(
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
                ),
              )
            else
              RepaintBoundary(
                child: _FlutterMapLayer(
                mapController: _mapController,
                route: _route,
                plannedRoute: _plannedRoute,
                allMarkers: allMarkers,
                showSpeedGradient: _showSpeedGradient,
                mapStyle: _mapStyle,
                currentZoom: _currentZoom,
                onMapReady: () { if (mounted) _mapReady = true; },
                onZoomChanged: (double zoom) => _currentZoom = zoom,
                onUserDrag: () {
                  if (_followMode) setState(() => _followMode = false);
                },
                ),
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
                right: 12,
                child: _buildStylePicker(),
              ),

            
            // ── ZOOM CONTROLS ─────────────────────────────────────────────
            if (!_route.isEmpty)
              ValueListenableBuilder<double>(
                valueListenable: _bottomPanelHeight,
                builder: (_, double panelH, __) => Positioned(
                  right: 16,
                  bottom: (panelH + 18).clamp(18.0, viewportSize.height * 0.62).toDouble(),
                  child: RepaintBoundary(child: _buildZoomControls()),
                ),
              ),

            // ── PREMIUM FLOATING SPEED HUD ───────────────────────────────────
            if (!_route.isEmpty) _buildFloatingSpeedHud(),

            // ── PREMIUM QUICK ACTION WHEEL ────────────────────────────────────
            if (!_route.isEmpty) _buildQuickActionWheel(),

            // ── BOTTOM PANEL ─────────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: RepaintBoundary(child: _buildBottomPanel(context)),
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
    final double width = MediaQuery.sizeOf(context).width;
    final bool compact = width < 390;
    final double iconSize = compact ? 34 : 38;
    final double iconGap = compact ? 5 : 7;
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
            left: compact ? 10 : 14,
            right: compact ? 10 : 14,
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
                child: _GlassIconBox(
                  icon: CupertinoIcons.chevron_left,
                  size: iconSize,
                ),
              ),
              SizedBox(width: compact ? 8 : 12),
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
                        Flexible(
                          child: Text(
                            widget.isLive ? 'LIVE TRACKING' : 'TRIP REPLAY',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
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
                              color: _kBlueSoft,
                              icon: CupertinoIcons.map_pin_ellipse,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 5 : 8),
              _PressableButton(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showSpeedGradient = !_showSpeedGradient);
                },
                child: _GlassIconBox(
                  icon: Icons.speed_rounded,
                  size: iconSize,
                  active: _showSpeedGradient,
                  activeColor: _kBlue,
                ),
              ),
              SizedBox(width: iconGap),
              _PressableButton(
                onTap: _toggleChart,
                child: _GlassIconBox(
                  icon: CupertinoIcons.graph_square,
                  size: iconSize,
                  active: _showChart,
                  activeColor: _kBlue,
                ),
              ),
              SizedBox(width: iconGap),
              _PressableButton(
                onTap: _openMapboxControls,
                child: _GlassIconBox(
                  icon: CupertinoIcons.location_north_line_fill,
                  size: iconSize,
                  active: _plannedRoute != null,
                  activeColor: _kBlue,
                ),
              ),
              SizedBox(width: iconGap),
              _PressableButton(
                onTap: _cycleMapStyle,
                child: _GlassIconBox(
                  icon: _mapStyle.icon,
                  size: iconSize,
                  active: _stylePickerOpen,
                  activeColor: _kBlue,
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
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: math.min(290, MediaQuery.sizeOf(context).width - 24),
            constraints: BoxConstraints(
              maxHeight: math.min(520, MediaQuery.sizeOf(context).height * 0.62),
            ),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kCard.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 20,
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: MapStyle.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (BuildContext context, int index) {
                final MapStyle style = MapStyle.values[index];
                final bool active = _mapStyle == style;

                return _PressableButton(
                  onTap: () => _selectStyle(style),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? _kBlue.withValues(alpha: 0.13)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active
                            ? _kBlue.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          style.icon,
                          color: active ? _kBlueSoft : Colors.white54,
                          size: 17,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                style.fullLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: active ? _kBlueSoft : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                style.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (active) ...<Widget>[
                          const SizedBox(width: 8),
                          const Icon(
                            CupertinoIcons.checkmark_alt,
                            color: _kBlueSoft,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }


}

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

class _PressableButton extends StatefulWidget {
  const _PressableButton({
    required this.onTap,
    required this.child,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 170),
    value: 1.0,
    lowerBound: 0.90,
    upperBound: 1.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _playTapAnimation() async {
    try {
      await _ctrl.reverse();
      if (mounted) await _ctrl.forward();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        unawaited(_playTapAnimation());
        widget.onTap();
      },
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) => _ctrl.forward(),
      onTapCancel: () => _ctrl.forward(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, Widget? child) =>
            Transform.scale(scale: _ctrl.value, child: child),
        child: widget.child,
      ),
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: button,
    );
  }
}

class _GlassIconBox extends StatelessWidget {
  const _GlassIconBox({
    required this.icon,
    required this.size,
    this.active = false,
    this.activeColor = _kBlue,
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
        final double t = math.sin(controller.value * math.pi).clamp(0.0, 1.0).toDouble();
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
          color: _kBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kBlue.withValues(alpha: 0.20)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _kBlueSoft,
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
                  _kBlue.withValues(alpha: 0.18),
                  _kBlueDeep.withValues(alpha: 0.08),
                ],
              )
            : null,
        color: isActive ? null : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? _kBlue.withValues(alpha: 0.45) : _kCardBorder,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 15, color: isActive ? _kBlueSoft : Colors.white60),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? _kBlueSoft : Colors.white60,
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
                  if (widget.mapStyle.isDark) {
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
                              color: _kBlue.withValues(
                                alpha: (1.0 - value) * 0.12,
                              ),
                              border: Border.all(
                                color: _kBlue.withValues(
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
                              _kBlueSoft.withValues(alpha: 0.35),
                              _kBlue.withValues(alpha: 0.16),
                              Colors.black.withValues(alpha: 0.36),
                            ],
                          ),
                          border: Border.all(
                            color: _kBlue.withValues(alpha: 0.24),
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: _kBlue.withValues(alpha: 0.18),
                              blurRadius: 22,
                            ),
                          ],
                        ),
                        child: const Icon(
                          CupertinoIcons.map,
                          color: _kBlueSoft,
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


// ─────────────────────────────────────────────────────────────────────────────
// PREMIUM OVERLAYS — Floating HUD + Quick Action Wheel
// ─────────────────────────────────────────────────────────────────────────────

extension _MapScreenPremiumOverlays on _MapScreenState {
  Widget _buildFloatingSpeedHud() {
    return ValueListenableBuilder<double>(
      valueListenable: _hudSpeed,
      builder: (_, double speed, __) {
        final Color color = _speedColor(speed);
        final String speedLabel = speed.toStringAsFixed(0);

        return Positioned(
          left: _floatingHudOffset.dx,
          top: _floatingHudOffset.dy,
          child: GestureDetector(
            onPanUpdate: _updateFloatingHudOffset,
            onPanEnd: (_) => _snapFloatingHudToEdge(),
            onDoubleTap: _toggleFloatingHudMini,
            onLongPress: _toggleFloatingHudLock,
            child: RepaintBoundary(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: _floatingHudMini ? 78 : 120,
                padding: EdgeInsets.symmetric(
                  horizontal: _floatingHudMini ? 10 : 14,
                  vertical: _floatingHudMini ? 8 : 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(_floatingHudMini ? 22 : 28),
                  border: Border.all(
                    color: (_floatingHudLocked ? _kRed : color)
                        .withValues(alpha: 0.34),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_floatingHudMini ? 22 : 28),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              _floatingHudLocked
                                  ? CupertinoIcons.lock_fill
                                  : CupertinoIcons.speedometer,
                              color: color,
                              size: _floatingHudMini ? 12 : 15,
                            ),
                            if (!_floatingHudMini) ...<Widget>[
                              const SizedBox(width: 5),
                              Text(
                                widget.isLive ? 'LIVE' : _replayCameraMode.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.52),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: _floatingHudMini ? 2 : 5),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            speedLabel,
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _floatingHudMini ? 28 : 42,
                              height: 0.92,
                              letterSpacing: -2.0,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (!_floatingHudMini) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            'KM/H',
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionWheel() {
    return ValueListenableBuilder<double>(
      valueListenable: _bottomPanelHeight,
      builder: (_, double panelHeight, __) {
        final bool open = _quickActionMenuState == _QuickActionMenuState.open;
        final EdgeInsets safe = MediaQuery.paddingOf(context);
        final Size screen = MediaQuery.sizeOf(context);
        final double panelAwareBottom = panelHeight + 20.0;
        final double minBottom = safe.bottom + (_panelDockMode.isMini ? 92.0 : 148.0);
        final double bottom = math.min(
          math.max(panelAwareBottom, minBottom),
          math.max(96.0, screen.height * 0.58),
        );

        return Positioned(
          right: 16,
          bottom: bottom,
          child: RepaintBoundary(
            child: SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.bottomRight,
                clipBehavior: Clip.none,
                children: <Widget>[
                  _QuickActionBubble(
                    open: open,
                    offset: const Offset(-128, -12),
                    icon: CupertinoIcons.arrow_down_right_arrow_up_left,
                    label: 'Fit',
                    onTap: () {
                      _closeQuickActionMenu();
                      _fitRoute();
                    },
                  ),
                  _QuickActionBubble(
                    open: open,
                    offset: const Offset(-112, -72),
                    icon: _followMode
                        ? CupertinoIcons.location_fill
                        : CupertinoIcons.location,
                    label: 'Follow',
                    active: _followMode,
                    onTap: () {
                      _closeQuickActionMenu();
                      _toggleFollow();
                    },
                  ),
                  _QuickActionBubble(
                    open: open,
                    offset: const Offset(-62, -118),
                    icon: CupertinoIcons.map_fill,
                    label: 'Style',
                    onTap: () {
                      _closeQuickActionMenu();
                      setState(() => _stylePickerOpen = !_stylePickerOpen);
                    },
                  ),
                  _QuickActionBubble(
                    open: open,
                    offset: const Offset(0, -132),
                    icon: CupertinoIcons.location_north_line_fill,
                    label: 'Route',
                    active: _plannedRoute != null,
                    onTap: () {
                      _closeQuickActionMenu();
                      _openMapboxControls();
                    },
                  ),
                  if (!widget.isLive)
                    _QuickActionBubble(
                      open: open,
                      offset: const Offset(-12, -68),
                      icon: _replayCameraMode.icon,
                      label: _replayCameraMode.label,
                      active: _replayCameraMode != _ReplayCameraMode.follow,
                      onTap: _cycleReplayCameraMode,
                    ),
                  _PressableButton(
                    onTap: _toggleQuickActionMenu,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: open
                            ? const LinearGradient(colors: <Color>[_kRed, _kBlue])
                            : _kBlueGlassGradient,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: (open ? _kRed : _kBlue).withValues(alpha: 0.34),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(
                        open
                            ? CupertinoIcons.xmark
                            : CupertinoIcons.slider_horizontal_3,
                        color: Colors.white,
                        size: 24,
                      ),
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

}

class _QuickActionBubble extends StatelessWidget {
  const _QuickActionBubble({
    required this.open,
    required this.offset,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final bool open;
  final Offset offset;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: open ? 1.0 : 0.0,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            scale: open ? 1.0 : 0.62,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              offset: open ? Offset(offset.dx / 58.0, offset.dy / 58.0) : Offset.zero,
              child: _PressableButton(
                onTap: onTap,
                child: Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (active ? _kBlueSoft : Colors.white)
                          .withValues(alpha: active ? 0.42 : 0.14),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.32),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        icon,
                        color: active ? _kBlueSoft : Colors.white,
                        size: 18,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? _kBlueSoft : Colors.white70,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
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
