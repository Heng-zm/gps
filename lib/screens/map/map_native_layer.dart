// ignore_for_file: deprecated_member_use

part of 'map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NATIVE MAPBOX LAYER
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// NATIVE MAPBOX LAYER — Android/mobile only. Web uses flutter_map fallback.
// ─────────────────────────────────────────────────────────────────────────────

int _mapColorToInt(Color color) => color.value;

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
  final PlannedRoute? plannedRoute;
  final MapStyle mapStyle;
  final MapboxStandardPreset mapboxPreset;
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
          pulsingColor: _mapColorToInt(_kBlue),
          pulsingMaxRadius: 46,
          showAccuracyRing: widget.isLive,
          accuracyRingColor: _mapColorToInt(_kBlue.withValues(alpha: 0.18)),
          accuracyRingBorderColor:
              _mapColorToInt(_kBlue.withValues(alpha: 0.42)),
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

    if (!widget.mapStyle.isStandardFamily) return;

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

      final PlannedRoute? planned = widget.plannedRoute;
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

  static String _styleUri(MapStyle style) => style.styleUri;

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
