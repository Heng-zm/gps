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
    if (!mph.isFinite || mph < 0.0) {
      return 0.0;
    }

    return mph * 1.609344;
  }

  double get altitudeMeters {
    final double ft = altitudeFt;
    if (!ft.isFinite) {
      return 0.0;
    }
    return ft / 3.28084;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────

const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD86B);
const Color _kRed = Color(0xFFE74C3C);
const Color _kTeal = Color(0xFF4ECDC4);
const Color _kBlue = Color(0xFF3B82F6);
const Color _kGreen = Color(0xFF27AE60);
const Color _kOrange = Color(0xFFE67E22);
const Color _kBg = Color(0xFF070707);
const Color _kCard = Color(0xFF111111);
const Color _kCardBorder = Color(0xFF252528);

const double _kRouteGlowOpacity = 0.18;
const int _kMaxChartSamples = 120;
const int _kMaxMapRenderPoints = 1800;
const double _kDefaultZoom = 16.0;
const double _kMinZoom = 3.0;
const double _kMaxZoom = 19.0;
const double _kCameraMoveMinMeters = 2.0;
const Duration _kCameraMoveThrottle = Duration(milliseconds: 450);

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

  List<String> get subdomains {
    switch (this) {
      case MapStyle.satellite:
        return const <String>[];
      case MapStyle.dark:
      case MapStyle.light:
        return const <String>['a', 'b', 'c', 'd'];
    }
  }

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
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

bool get _isNativeIOS {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.iOS;
}

bool _isValidLatLng(LatLng point) {
  return point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude.abs() <= 90.0 &&
      point.longitude.abs() <= 180.0;
}

double _bearing(LatLng from, LatLng to) {
  if (!_isValidLatLng(from) || !_isValidLatLng(to)) {
    return 0.0;
  }

  final double lat1 = from.latitudeInRad;
  final double lat2 = to.latitudeInRad;
  final double deltaLng = to.longitudeInRad - from.longitudeInRad;

  final double y = math.sin(deltaLng) * math.cos(lat2);
  final double x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);

  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

Color _speedColor(double kmh) {
  if (!kmh.isFinite || kmh <= 0.0) {
    return _kTeal;
  }

  if (kmh < 15) {
    return _kTeal;
  }
  if (kmh < 40) {
    return _kGreen;
  }
  if (kmh < 70) {
    return _kGold;
  }
  if (kmh < 100) {
    return _kOrange;
  }
  return _kRed;
}

String _formatDuration(Duration duration) {
  final Duration safe = duration.isNegative ? Duration.zero : duration;

  final int h = safe.inHours;
  final int m = safe.inMinutes.remainder(60);
  final int s = safe.inSeconds.remainder(60);

  if (h > 0) {
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
  if (m > 0) {
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  return '${s}s';
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

  List<TripPoint> _validTripPoints = <TripPoint>[];
  List<LatLng> _smoothedPoints = <LatLng>[];
  List<LatLng> _rawPoints = <LatLng>[];
  List<_SpeedSegment> _speedSegments = <_SpeedSegment>[];
  List<double> _speedSamples = <double>[];
  List<double> _altSamples = <double>[];

  bool _followMode = true;
  bool _showSpeedGradient = false;
  bool _panelExpanded = true;
  bool _stylePickerOpen = false;
  bool _showChart = false;
  bool _mapReady = false;

  _ChartMode _chartMode = _ChartMode.speed;
  MapStyle _mapStyle = MapStyle.dark;

  double _currentZoom = _kDefaultZoom;
  double _calculatedDistance = 0.0;
  double _calculatedMaxSpeed = 0.0;
  double _calculatedAvgSpeed = 0.0;
  double _calculatedMaxAltitude = 0.0;
  int _peakSpeedIndex = -1;
  double _currentBearing = 0.0;

  final ValueNotifier<double> _bottomPanelHeight = ValueNotifier<double>(0);
  final ValueNotifier<double> _hudSpeed = ValueNotifier<double>(0);

  late final AnimationController _markerPulseController;
  late final AnimationController _chartRevealController;

  AnimationController? _moveAnimController;
  Animation<LatLng>? _moveAnim;

  DateTime? _lastCameraMoveAt;
  LatLng? _lastCameraDestination;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _rawPoints.isEmpty) return;

      if (_rawPoints.length > 1 && !widget.isLive) {
        _fitRoute(haptic: false);
      } else {
        _animatedMove(_rawPoints.last, _currentZoom);
      }
    });
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool changed = widget.points.length != oldWidget.points.length ||
        !identical(widget.points, oldWidget.points) ||
        widget.isLive != oldWidget.isLive;

    if (!changed) {
      return;
    }

    _processPoints();

    if (_followMode && widget.isLive && _rawPoints.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _animatedMove(_rawPoints.last, _currentZoom);
        }
      });
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

  // ───────────────────────────────────────────────────────────────────────────
  // PROCESS POINTS
  // ───────────────────────────────────────────────────────────────────────────

  void _processPoints() {
    final List<TripPoint> valid = widget.points.where((TripPoint point) {
      return _isValidLatLng(point.position);
    }).toList(growable: false);

    if (valid.isEmpty) {
      if (mounted) {
        setState(() {
          _validTripPoints = <TripPoint>[];
          _calculatedDistance = 0.0;
          _calculatedMaxSpeed = 0.0;
          _calculatedAvgSpeed = 0.0;
          _calculatedMaxAltitude = 0.0;
          _peakSpeedIndex = -1;
          _currentBearing = 0.0;
          _smoothedPoints = <LatLng>[];
          _rawPoints = <LatLng>[];
          _speedSegments = <_SpeedSegment>[];
          _speedSamples = <double>[];
          _altSamples = <double>[];
        });
      }

      _hudSpeed.value = 0.0;
      return;
    }

    double distanceKm = 0.0;
    double maxSpeed = 0.0;
    double speedSum = 0.0;
    double maxAltitudeM = 0.0;
    int peakIndex = 0;

    const Distance distanceCalculator = Distance();

    final List<LatLng> raw = <LatLng>[];
    final List<_SpeedSegment> segments = <_SpeedSegment>[];

    for (int i = 0; i < valid.length; i++) {
      final TripPoint point = valid[i];
      final double speedKmh = point.speedKmh;
      final double altitudeM = point.altitudeMeters;

      raw.add(point.position);
      speedSum += speedKmh;

      if (speedKmh > maxSpeed) {
        maxSpeed = speedKmh;
        peakIndex = i;
      }

      if (altitudeM > maxAltitudeM) {
        maxAltitudeM = altitudeM;
      }

      if (i > 0) {
        final TripPoint previous = valid[i - 1];

        final double segmentDistance = distanceCalculator.as(
          LengthUnit.Kilometer,
          previous.position,
          point.position,
        );

        if (segmentDistance.isFinite && segmentDistance >= 0.0) {
          distanceKm += segmentDistance;
        }

        final double avgSegmentSpeed =
            (previous.speedKmh + point.speedKmh) / 2.0;
        final Color color = _speedColor(avgSegmentSpeed);

        if (segments.isNotEmpty && segments.last.color == color) {
          segments.last.points.add(point.position);
        } else {
          segments.add(
            _SpeedSegment(
              points: <LatLng>[previous.position, point.position],
              color: color,
            ),
          );
        }
      }
    }

    double bearing = 0.0;

    if (valid.length >= 2) {
      bearing = _bearing(
        valid[valid.length - 2].position,
        valid.last.position,
      );
    }

    final List<LatLng> smoothed = raw.length > 1
        ? optimizePolylineForMap(
            raw,
            epsilon: raw.length > 700 ? 0.00007 : 0.00004,
            tension: 0.5,
            subdivisions: raw.length > 700 ? 6 : 8,
            maxOutputPoints: _kMaxMapRenderPoints,
          ).where(_isValidLatLng).toList(growable: false)
        : List<LatLng>.from(raw);

    final int n = valid.length;
    final int step = (n / _kMaxChartSamples).ceil().clamp(1, n).toInt();

    final List<double> speedSamples = <double>[];
    final List<double> altitudeSamples = <double>[];

    for (int i = 0; i < n; i += step) {
      final double speed = valid[i].speedKmh;
      final double altitude = valid[i].altitudeMeters;

      if (speed.isFinite) {
        speedSamples.add(speed);
      }
      if (altitude.isFinite) {
        altitudeSamples.add(altitude);
      }
    }

    _hudSpeed.value = valid.last.speedKmh;

    if (!mounted) {
      return;
    }

    setState(() {
      _validTripPoints = valid;
      _calculatedDistance = distanceKm;
      _calculatedMaxSpeed = maxSpeed;
      _calculatedAvgSpeed = n > 0 ? speedSum / n : 0.0;
      _calculatedMaxAltitude = maxAltitudeM;
      _peakSpeedIndex = peakIndex;
      _currentBearing = bearing;
      _rawPoints = raw;
      _smoothedPoints = smoothed;
      _speedSegments = segments;
      _speedSamples = speedSamples;
      _altSamples = altitudeSamples;
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CAMERA
  // ───────────────────────────────────────────────────────────────────────────

  void _animatedMove(
    LatLng destination,
    double zoom, {
    bool force = false,
  }) {
    if (!_isValidLatLng(destination)) {
      return;
    }

    final double safeZoom = zoom.clamp(_kMinZoom, _kMaxZoom).toDouble();

    if (!force && _shouldSkipCameraMove(destination)) {
      return;
    }

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

    _moveAnimController?.stop();
    _moveAnimController?.dispose();
    _moveAnimController = null;
    _moveAnim = null;

    LatLng start;

    try {
      start = _mapController.camera.center;
    } catch (_) {
      try {
        _mapController.move(destination, safeZoom);
      } catch (_) {}
      return;
    }

    _moveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _moveAnim = LatLngTween(begin: start, end: destination).animate(
      CurvedAnimation(
        parent: _moveAnimController!,
        curve: Curves.easeInOutCubic,
      ),
    );

    _moveAnim!.addListener(() {
      final Animation<LatLng>? animation = _moveAnim;
      if (!mounted || animation == null) return;

      try {
        _mapController.move(animation.value, safeZoom);
      } catch (_) {}
    });

    _moveAnimController!.forward();
  }

  bool _shouldSkipCameraMove(LatLng destination) {
    final DateTime? lastMoveAt = _lastCameraMoveAt;
    final LatLng? lastDestination = _lastCameraDestination;

    if (lastMoveAt == null || lastDestination == null) {
      return false;
    }

    final bool tooSoon =
        DateTime.now().difference(lastMoveAt) < _kCameraMoveThrottle;
    if (!tooSoon) {
      return false;
    }

    final double meters = const Distance().as(
      LengthUnit.Meter,
      lastDestination,
      destination,
    );

    return meters.isFinite && meters < _kCameraMoveMinMeters;
  }

  void _fitRoute({bool haptic = true}) {
    if (_rawPoints.isEmpty) {
      return;
    }

    if (haptic) {
      HapticFeedback.lightImpact();
    }

    if (_rawPoints.length == 1) {
      _animatedMove(_rawPoints.first, _currentZoom, force: true);
      return;
    }

    if (_isNativeIOS) {
      _appleMapController.fitPoints(_rawPoints);
      if (mounted) {
        setState(() => _followMode = false);
      }
      return;
    }

    final fm.LatLngBounds bounds = fm.LatLngBounds.fromPoints(_rawPoints);

    try {
      _mapController.fitCamera(
        fm.CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(72, 110, 72, 230),
        ),
      );
    } catch (_) {}

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      try {
        setState(() {
          _currentZoom = _mapController.camera.zoom;
        });
      } catch (_) {}
    });

    setState(() {
      _followMode = false;
    });
  }

  void _toggleFollow() {
    HapticFeedback.lightImpact();

    final bool next = !_followMode;

    setState(() {
      _followMode = next;
    });

    if (next && _rawPoints.isNotEmpty) {
      _animatedMove(_rawPoints.last, _currentZoom, force: true);
    }
  }

  void _selectStyle(MapStyle style) {
    HapticFeedback.selectionClick();

    if (style == _mapStyle) {
      setState(() {
        _stylePickerOpen = false;
      });
      return;
    }

    setState(() {
      _mapStyle = style;
      _stylePickerOpen = false;
    });

    if (_isNativeIOS) {
      _appleMapController.notifyStyleChanged();
    }
  }

  void _doZoom(int delta) {
    HapticFeedback.selectionClick();

    double nextZoom;

    try {
      nextZoom = (_mapController.camera.zoom + delta)
          .clamp(_kMinZoom, _kMaxZoom)
          .toDouble();
    } catch (_) {
      nextZoom = (_currentZoom + delta).clamp(_kMinZoom, _kMaxZoom).toDouble();
    }

    setState(() {
      _currentZoom = nextZoom;
    });

    if (_isNativeIOS) {
      if (_rawPoints.isNotEmpty) {
        _appleMapController.animateTo(_rawPoints.last, zoom: nextZoom);
      }
      return;
    }

    try {
      _mapController.move(_mapController.camera.center, nextZoom);
    } catch (_) {}
  }

  void _toggleChart() {
    HapticFeedback.selectionClick();

    setState(() {
      _showChart = !_showChart;
    });

    if (_showChart) {
      _chartRevealController.forward(from: 0.0);
    } else {
      _chartRevealController.reverse();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final List<fm.Marker> allMarkers = _buildMarkers();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: <Widget>[
            if (_validTripPoints.isEmpty)
              const _EmptyMapState()
            else if (_isNativeIOS)
              _AppleMapLayer(
                controller: _appleMapController,
                points: _validTripPoints,
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
                  if (_followMode) {
                    setState(() {
                      _followMode = false;
                    });
                  }
                },
              )
            else
              _FlutterMapLayer(
                mapController: _mapController,
                points: _validTripPoints,
                smoothedPoints: _smoothedPoints,
                speedSegments: _speedSegments,
                allMarkers: allMarkers,
                showSpeedGradient: _showSpeedGradient,
                mapStyle: _mapStyle,
                currentZoom: _currentZoom,
                onMapReady: () {
                  _mapReady = true;
                },
                onZoomChanged: (double zoom) {
                  _currentZoom = zoom;
                },
                onUserDrag: () {
                  if (_followMode) {
                    setState(() {
                      _followMode = false;
                    });
                  }
                },
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(context),
            ),
            if (_stylePickerOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    setState(() {
                      _stylePickerOpen = false;
                    });
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            if (_stylePickerOpen)
              Positioned(
                top: MediaQuery.of(context).padding.top + 62,
                right: 16,
                child: _buildStylePicker(),
              ),
            if (_validTripPoints.isNotEmpty)
              ValueListenableBuilder<double>(
                valueListenable: _bottomPanelHeight,
                builder: (_, double panelHeight, __) {
                  return Positioned(
                    left: 16,
                    bottom: panelHeight + 12,
                    child: _buildLiveSpeedHud(),
                  );
                },
              ),
            if (_validTripPoints.isNotEmpty)
              ValueListenableBuilder<double>(
                valueListenable: _bottomPanelHeight,
                builder: (_, double panelHeight, __) {
                  return Positioned(
                    right: 16,
                    bottom: panelHeight + 12,
                    child: _buildZoomControls(),
                  );
                },
              ),
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

  // ───────────────────────────────────────────────────────────────────────────
  // MARKERS
  // ───────────────────────────────────────────────────────────────────────────

  List<fm.Marker> _buildMarkers() {
    if (_validTripPoints.isEmpty) return const <fm.Marker>[];

    final List<fm.Marker> markers = <fm.Marker>[
      _startMarker(_validTripPoints.first.position),
    ];

    if (!widget.isLive && _validTripPoints.length > 1) {
      markers.add(_endMarker(_validTripPoints.last.position));
    } else if (widget.isLive) {
      markers.add(_liveMarker(_validTripPoints.last.position));
    }

    if (_showSpeedGradient && _validTripPoints.length > 10) {
      final int markerStep =
          (_validTripPoints.length / 8).ceil().clamp(25, 80).toInt();

      for (int i = markerStep;
          i < _validTripPoints.length - 2;
          i += markerStep) {
        markers.add(_speedTagMarker(_validTripPoints[i]));
      }
    }

    if (_peakSpeedIndex >= 0 &&
        _peakSpeedIndex < _validTripPoints.length &&
        _calculatedMaxSpeed > 5) {
      markers.add(_peakSpeedMarker(_validTripPoints[_peakSpeedIndex]));
    }

    return markers;
  }

  fm.Marker _startMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 34,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kTeal,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _kTeal.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          CupertinoIcons.flag_fill,
          color: Colors.white,
          size: 13,
        ),
      ),
    );
  }

  fm.Marker _endMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 34,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kRed,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _kRed.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          CupertinoIcons.checkmark_alt,
          color: Colors.white,
          size: 13,
        ),
      ),
    );
  }

  fm.Marker _liveMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 88,
      height: 88,
      child: AnimatedBuilder(
        animation: _markerPulseController,
        builder: (_, __) {
          final double scale = _markerPulseController.value;
          final double opacity = (1.0 - scale).clamp(0.0, 1.0).toDouble();

          return RepaintBoundary(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  width: 66 * scale,
                  height: 66 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kRed.withValues(alpha: opacity * 0.35),
                    border: Border.all(
                      color: _kRed.withValues(alpha: opacity * 0.65),
                      width: 1.2,
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: _currentBearing * math.pi / 180.0,
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
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: _kRed.withValues(alpha: 0.75),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  fm.Marker _speedTagMarker(TripPoint point) {
    return fm.Marker(
      point: point.position,
      width: 42,
      height: 22,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _speedColor(point.speedKmh).withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          point.speedKmh.toStringAsFixed(0),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  fm.Marker _peakSpeedMarker(TripPoint point) {
    return fm.Marker(
      point: point.position,
      width: 72,
      height: 30,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[
              _kGoldSoft,
              _kGold,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _kGold.withValues(alpha: 0.45),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              CupertinoIcons.bolt_fill,
              color: Colors.black,
              size: 10,
            ),
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
  // HUD / HEADER / PANEL
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildLiveSpeedHud() {
    return ValueListenableBuilder<double>(
      valueListenable: _hudSpeed,
      builder: (_, double speed, __) {
        final Color accent = _speedColor(speed);

        return ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
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
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder:
                            (Widget child, Animation<double> anim) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.25),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          speed.toStringAsFixed(0),
                          key: ValueKey<String>(speed.toStringAsFixed(0)),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'km/h',
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Stack(
                    children: <Widget>[
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
                        width: (speed / 160).clamp(0.03, 1.0).toDouble() * 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              accent.withValues(alpha: 0.6),
                              accent,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: accent.withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
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
            color: Colors.black.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const _GlassButton(
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    color: Colors.white,
                    size: 18,
                  ),
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
                          const _PulseDot(color: _kRed),
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
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Text(
                          '${_validTripPoints.length} pts',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                          ),
                        ),
                        if (elapsed != null) ...<Widget>[
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.2),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            _formatDuration(elapsed),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (_calculatedDistance > 0) ...<Widget>[
                          Text(
                            '  ·  ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.2),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${_calculatedDistance.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: _kGoldSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _HeaderButton(
                selected: _showSpeedGradient,
                selectedColor: _kGold,
                icon: Icons.speed_rounded,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _showSpeedGradient = !_showSpeedGradient;
                  });
                },
              ),
              const SizedBox(width: 8),
              _HeaderButton(
                selected: _showChart,
                selectedColor: _kBlue,
                icon: CupertinoIcons.graph_square,
                onTap: _toggleChart,
              ),
              const SizedBox(width: 8),
              _HeaderButton(
                selected: _stylePickerOpen,
                selectedColor: _kGold,
                icon: _mapStyle.icon,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _stylePickerOpen = !_stylePickerOpen;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStylePicker() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (_, double t, Widget? child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, -8 * (1 - t)),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 18,
                ),
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: MapStyle.values.map((MapStyle style) {
                  final bool active = _mapStyle == style;

                  return GestureDetector(
                    onTap: () => _selectStyle(style),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? _kGold.withValues(alpha: 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? _kGold.withValues(alpha: 0.45)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            style.icon,
                            color: active ? _kGoldSoft : Colors.white60,
                            size: 15,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            style.label,
                            style: TextStyle(
                              color: active ? _kGoldSoft : Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          if (active) ...<Widget>[
                            const SizedBox(width: 8),
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

  Widget _buildBottomPanel() {
    if (_validTripPoints.isEmpty) return const SizedBox.shrink();

    return MeasureSize(
      onChange: (Size size) {
        _bottomPanelHeight.value = size.height;
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _panelExpanded = !_panelExpanded;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(
                        width: 36,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
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
                              children: <Widget>[
                                if (_showChart && _speedSamples.isNotEmpty)
                                  _buildMiniChart(),
                                if (_showSpeedGradient) ...<Widget>[
                                  const SizedBox(height: 10),
                                  _buildSpeedLegend(),
                                  const SizedBox(height: 10),
                                  Divider(
                                    color: Colors.white.withValues(alpha: 0.07),
                                    height: 1,
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _buildStatsGrid(),
                                const SizedBox(height: 14),
                                Row(
                                  children: <Widget>[
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

  Widget _buildStatsGrid() {
    final bool hasAltitude = _calculatedMaxAltitude > 0.0;

    return Row(
      children: <Widget>[
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
          color: _kGoldSoft,
          icon: CupertinoIcons.bolt_fill,
        ),
        _StatTile(
          label: 'AVG SPEED',
          value: _calculatedAvgSpeed.toStringAsFixed(0),
          unit: 'KM/H',
          color: _kGreen,
          icon: CupertinoIcons.speedometer,
        ),
        _StatTile(
          label: hasAltitude ? 'MAX ALT' : 'POINTS',
          value: hasAltitude
              ? _calculatedMaxAltitude.toStringAsFixed(0)
              : '${_validTripPoints.length}',
          unit: hasAltitude ? 'M' : 'PTS',
          color: _kRed,
          icon: hasAltitude
              ? CupertinoIcons.arrow_up
              : CupertinoIcons.circle_grid_hex,
        ),
      ],
    );
  }

  Widget _buildMiniChart() {
    final bool hasAltitude = _altSamples.any((double value) => value > 0.0);
    final List<double> samples =
        _chartMode == _ChartMode.speed ? _speedSamples : _altSamples;

    return AnimatedBuilder(
      animation: _chartRevealController,
      builder: (_, __) {
        return Opacity(
          opacity: _chartRevealController.value,
          child: SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: _chartRevealController,
              curve: Curves.easeOutCubic,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    _ChartTab(
                      label: 'SPEED',
                      active: _chartMode == _ChartMode.speed,
                      color: _kGoldSoft,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _chartMode = _ChartMode.speed;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    if (hasAltitude)
                      _ChartTab(
                        label: 'ALTITUDE',
                        active: _chartMode == _ChartMode.altitude,
                        color: _kBlue,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _chartMode = _ChartMode.altitude;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: CustomPaint(
                    size: const Size(double.infinity, 72),
                    painter: _MiniChartPainter(
                      samples: samples,
                      color:
                          _chartMode == _ChartMode.speed ? _kGoldSoft : _kBlue,
                      useSpeedColors: _chartMode == _ChartMode.speed,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(
                  color: Colors.white.withValues(alpha: 0.07),
                  height: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpeedLegend() {
    const List<_LegendItem> items = <_LegendItem>[
      _LegendItem(color: _kTeal, label: '<15'),
      _LegendItem(color: _kGreen, label: '15–40'),
      _LegendItem(color: _kGold, label: '40–70'),
      _LegendItem(color: _kOrange, label: '70–100'),
      _LegendItem(color: _kRed, label: '100+'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((_LegendItem item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 22,
              height: 4,
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              item.label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildZoomControls() {
    return Column(
      children: <Widget>[
        _ZoomButton(
          icon: CupertinoIcons.plus,
          onTap: () => _doZoom(1),
        ),
        const SizedBox(height: 8),
        _ZoomButton(
          icon: CupertinoIcons.minus,
          onTap: () => _doZoom(-1),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MINI CHART PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({
    required this.samples,
    required this.color,
    this.useSpeedColors = false,
  });

  final List<double> samples;
  final Color color;
  final bool useSpeedColors;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    final double maxVal =
        samples.reduce(math.max).clamp(1.0, double.infinity).toDouble();
    final double width = size.width;
    final double height = size.height - 4;

    final ui.Path path = ui.Path();
    final ui.Path fillPath = ui.Path();
    final List<Offset> points = <Offset>[];

    for (int i = 0; i < samples.length; i++) {
      final double denominator = math.max(1, samples.length - 1).toDouble();
      final double x = (i / denominator) * width;
      final double y = height - (samples[i] / maxVal) * height;
      points.add(Offset(x, y));
    }

    if (points.isEmpty) {
      return;
    }

    path.moveTo(points.first.dx, points.first.dy);
    fillPath
      ..moveTo(points.first.dx, height + 4)
      ..lineTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final Offset p0 = i > 0 ? points[i - 1] : points[i];
      final Offset p1 = points[i];
      final Offset p2 = points[i + 1];
      final Offset p3 = i + 2 < points.length ? points[i + 2] : p2;

      final double cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final double cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final double cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final double cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    fillPath
      ..lineTo(points.last.dx, height + 4)
      ..close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height + 4));

    canvas.drawPath(fillPath, fillPaint);

    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    if (useSpeedColors && samples.length > 4) {
      final int dotStep =
          (samples.length / 12).ceil().clamp(1, samples.length).toInt();

      for (int i = 0; i < points.length; i += dotStep) {
        final Paint dotPaint = Paint()
          ..color = _speedColor(samples[i])
          ..style = PaintingStyle.fill;

        canvas.drawCircle(points[i], 2.5, dotPaint);
      }
    }

    final ui.ParagraphStyle labelStyle = ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
    );

    for (int tick = 0; tick <= 2; tick++) {
      final int value = (maxVal * tick / 2).round();
      final double y = height - (value / maxVal) * height;

      final Paint tickPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 0.5;

      canvas.drawLine(Offset(0, y), Offset(width, y), tickPaint);

      final ui.ParagraphBuilder builder = ui.ParagraphBuilder(labelStyle)
        ..pushStyle(
          ui.TextStyle(
            color: Colors.white.withValues(alpha: 0.28),
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        )
        ..addText(value.toString());

      final ui.Paragraph paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 40));

      canvas.drawParagraph(paragraph, Offset(2, y - 9));
    }
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.color != color ||
        oldDelegate.useSpeedColors != useSpeedColors;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLUTTER MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _FlutterMapLayer extends StatelessWidget {
  const _FlutterMapLayer({
    required this.mapController,
    required this.points,
    required this.smoothedPoints,
    required this.speedSegments,
    required this.allMarkers,
    required this.showSpeedGradient,
    required this.mapStyle,
    required this.currentZoom,
    required this.onMapReady,
    required this.onZoomChanged,
    required this.onUserDrag,
  });

  final fm.MapController mapController;
  final List<TripPoint> points;
  final List<LatLng> smoothedPoints;
  final List<_SpeedSegment> speedSegments;
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
    final List<fm.Polyline> polylines = <fm.Polyline>[];

    for (final _SpeedSegment segment in speedSegments) {
      if (segment.points.length < 2) {
        continue;
      }

      polylines
        ..add(
          fm.Polyline(
            points: segment.points,
            color: segment.color.withValues(alpha: 0.22),
            strokeWidth: 12,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        )
        ..add(
          fm.Polyline(
            points: segment.points,
            color: segment.color,
            strokeWidth: 4,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
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
          retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.0,
        ),
        if (smoothedPoints.length > 1)
          showSpeedGradient
              ? _buildSpeedGradientLayer()
              : _buildSmoothPolylineLayer(),
        if (allMarkers.isNotEmpty) fm.MarkerLayer(markers: allMarkers),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER / TWEEN
// ─────────────────────────────────────────────────────────────────────────────

class _BearingArrowPainter extends CustomPainter {
  const _BearingArrowPainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2.0;
    final double cy = size.height / 2.0;

    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final ui.Path path = ui.Path()
      ..moveTo(cx, cy - 16)
      ..lineTo(cx - 6, cy + 2)
      ..lineTo(cx, cy - 2)
      ..lineTo(cx + 6, cy + 2)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BearingArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class LatLngTween extends Tween<LatLng> {
  LatLngTween({
    required LatLng begin,
    required LatLng end,
  }) : super(begin: begin, end: end);

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
  RenderObject createRenderObject(BuildContext context) {
    return SizeObserverRenderBox(onChange: onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant SizeObserverRenderBox renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class SizeObserverRenderBox extends RenderProxyBox {
  SizeObserverRenderBox({
    required this.onChange,
  });

  void Function(Size) onChange;
  Size? _previousSize;

  @override
  void performLayout() {
    super.performLayout();

    final Size newSize = child?.size ?? Size.zero;
    final Size? previous = _previousSize;

    if (previous == null ||
        (previous.width - newSize.width).abs() > 0.5 ||
        (previous.height - newSize.height).abs() > 0.5) {
      _previousSize = newSize;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached) {
          onChange(newSize);
        }
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASSES
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedSegment {
  _SpeedSegment({
    required this.points,
    required this.color,
  });

  final List<LatLng> points;
  final Color color;
}

class _LegendItem {
  const _LegendItem({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;
}

enum _ChartMode {
  speed,
  altitude,
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyMapState extends StatelessWidget {
  const _EmptyMapState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kGold.withValues(alpha: 0.1),
              border: Border.all(color: _kGold.withValues(alpha: 0.25)),
            ),
            child: const Icon(
              CupertinoIcons.map,
              color: _kGoldSoft,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No Route Data',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start tracking to see your route, speed graph, and replay map here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              height: 1.45,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.selected,
    required this.selectedColor,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final Color selectedColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: selected ? selectedColor.withValues(alpha: 0.15) : _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? selectedColor : _kCardBorder),
        ),
        child: Icon(
          icon,
          color: selected ? selectedColor : Colors.white54,
          size: 17,
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.child,
  });

  final Widget child;

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
  const _PulseDot({
    required this.color,
  });

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                widget.color.withValues(alpha: 0.5 + _controller.value * 0.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.color.withValues(alpha: _controller.value * 0.6),
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              color: color.withValues(alpha: 0.7),
              size: 11,
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              unit,
              style: TextStyle(
                color: color.withValues(alpha: 0.55),
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
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
          borderRadius: BorderRadius.circular(6),
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

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

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
            color: isActive ? _kGold.withValues(alpha: 0.5) : _kCardBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: isActive ? _kGoldSoft : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? _kGoldSoft : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

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
            child: Icon(
              icon,
              color: Colors.white70,
              size: 18,
            ),
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

  void _attach(_AppleMapLayerState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  void animateTo(LatLng position, {double zoom = 16}) {
    _state?._animateTo(position, zoom: zoom);
  }

  void fitPoints(List<LatLng> points) {
    _state?._fitPoints(points);
  }

  void notifyStyleChanged() {
    _state?._onStyleChanged();
  }

  void dispose() {
    _detach();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPLE MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _AppleMapLayer extends StatefulWidget {
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

    final bool pointChanged = oldWidget.points.length != widget.points.length ||
        !identical(oldWidget.points, widget.points);

    if (pointChanged &&
        widget.followMode &&
        widget.isLive &&
        widget.points.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _animateTo(widget.points.last.position);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  void _animateTo(LatLng position, {double zoom = 16}) {
    if (!_isValidLatLng(position)) {
      return;
    }

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
    final List<LatLng> validPoints =
        points.where(_isValidLatLng).toList(growable: false);

    if (validPoints.isEmpty) {
      return;
    }

    double minLat = validPoints.first.latitude;
    double maxLat = validPoints.first.latitude;
    double minLng = validPoints.first.longitude;
    double maxLng = validPoints.first.longitude;

    for (final LatLng point in validPoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    _mkController?.animateCamera(
      mk.CameraUpdate.newLatLngBounds(
        mk.LatLngBounds(
          southwest: mk.LatLng(minLat, minLng),
          northeast: mk.LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  void _onStyleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Set<mk.Polyline> _buildPolylines() {
    final Set<mk.Polyline> polylines = <mk.Polyline>{};
    int id = 0;

    final Color routeColor = widget.mapStyle.routeColor;

    if (widget.showSpeedGradient) {
      for (final _SpeedSegment segment in widget.speedSegments) {
        if (segment.points.length < 2) {
          continue;
        }

        final List<mk.LatLng> segmentPoints = segment.points
            .where(_isValidLatLng)
            .map(
              (LatLng point) => mk.LatLng(point.latitude, point.longitude),
            )
            .toList(growable: false);

        if (segmentPoints.length < 2) {
          continue;
        }

        polylines.add(
          mk.Polyline(
            polylineId: mk.PolylineId('seg_${id++}'),
            points: segmentPoints,
            color: segment.color,
            width: 5,
          ),
        );
      }
    } else if (widget.smoothedPoints.length > 1) {
      final List<mk.LatLng> mapPoints = widget.smoothedPoints
          .where(_isValidLatLng)
          .map(
            (LatLng point) => mk.LatLng(point.latitude, point.longitude),
          )
          .toList(growable: false);

      if (mapPoints.length > 1) {
        polylines
          ..add(
            mk.Polyline(
              polylineId: mk.PolylineId('route_glow'),
              points: mapPoints,
              color: routeColor.withValues(alpha: 0.18),
              width: 12,
            ),
          )
          ..add(
            mk.Polyline(
              polylineId: mk.PolylineId('route_mid'),
              points: mapPoints,
              color: routeColor.withValues(alpha: 0.45),
              width: 7,
            ),
          )
          ..add(
            mk.Polyline(
              polylineId: mk.PolylineId('route_solid'),
              points: mapPoints,
              color: routeColor,
              width: 4,
            ),
          );
      }
    }

    return polylines;
  }

  Set<mk.Annotation> _buildAnnotations() {
    final Set<mk.Annotation> annotations = <mk.Annotation>{};

    if (widget.points.isEmpty) return annotations;

    annotations.add(
      mk.Annotation(
        annotationId: mk.AnnotationId('start'),
        position: mk.LatLng(
          widget.points.first.position.latitude,
          widget.points.first.position.longitude,
        ),
        infoWindow: mk.InfoWindow(title: 'Start'),
        icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
          mk.BitmapDescriptor.hueCyan,
        ),
      ),
    );

    if (!widget.isLive && widget.points.length > 1) {
      annotations.add(
        mk.Annotation(
          annotationId: mk.AnnotationId('end'),
          position: mk.LatLng(
            widget.points.last.position.latitude,
            widget.points.last.position.longitude,
          ),
          infoWindow: mk.InfoWindow(title: 'End'),
          icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueRed,
          ),
        ),
      );
    } else if (widget.isLive) {
      annotations.add(
        mk.Annotation(
          annotationId: mk.AnnotationId('live'),
          position: mk.LatLng(
            widget.points.last.position.latitude,
            widget.points.last.position.longitude,
          ),
          infoWindow: mk.InfoWindow(title: 'Live'),
          icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

    if (widget.peakSpeedIndex >= 0 &&
        widget.peakSpeedIndex < widget.points.length) {
      final TripPoint peak = widget.points[widget.peakSpeedIndex];

      annotations.add(
        mk.Annotation(
          annotationId: mk.AnnotationId('peak'),
          position: mk.LatLng(
            peak.position.latitude,
            peak.position.longitude,
          ),
          infoWindow: mk.InfoWindow(
            title: '⚡ ${peak.speedKmh.toStringAsFixed(0)} km/h peak',
          ),
          icon: mk.BitmapDescriptor.defaultAnnotationWithHue(
            mk.BitmapDescriptor.hueYellow,
          ),
        ),
      );
    }

    return annotations;
  }

  @override
  Widget build(BuildContext context) {
    final mk.LatLng initialTarget = widget.points.isNotEmpty
        ? mk.LatLng(
            widget.points.last.position.latitude,
            widget.points.last.position.longitude,
          )
        : mk.LatLng(0, 0);

    return mk.AppleMap(
      initialCameraPosition: mk.CameraPosition(
        target: initialTarget,
        zoom: _kDefaultZoom,
      ),
      mapType: widget.mapStyle.appleMapType,
      rotateGesturesEnabled: false,
      polylines: _buildPolylines(),
      annotations: _buildAnnotations(),
      onMapCreated: (mk.AppleMapController controller) {
        _mkController = controller;

        if (widget.points.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _animateTo(widget.points.last.position);
            }
          });
        }
      },
      onCameraMoveStarted: widget.onUserDrag,
    );
  }
}
