// ignore_for_file: deprecated_member_use

part of 'tracking_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MAP LAYER
// ═══════════════════════════════════════════════════════════════════════════════

// FULL-SCREEN MAP FIRST UI
// ═══════════════════════════════════════════════════════════════════════════════

class _FullScreenLiveMap extends StatefulWidget {
  const _FullScreenLiveMap({
    required this.posN,
    required this.headingN,
    required this.followModeN,
    required this.mapController,
    required this.gps,
    required this.settings,
    required this.presetN,
    required this.runtimeModeN,
    required this.plannedRouteN,
    required this.performanceModeN,
    required this.polylineCount,
    required this.onMapReady,
  });

  final ValueNotifier<LatLng?> posN;
  final ValueNotifier<double> headingN;
  final ValueNotifier<_MapFollowMode> followModeN;

  /// Kept only for constructor compatibility with existing TrackingScreen.
  /// Native Mapbox uses its own [mb.MapboxMap] controller.
  final fm.MapController mapController;

  final GpsService gps;
  final SettingsService settings;
  final ValueNotifier<MapboxStandardPreset> presetN;
  final ValueNotifier<MapboxRuntimeMode> runtimeModeN;
  final ValueNotifier<PlannedRoute?> plannedRouteN;
  final ValueNotifier<_TrackingPerformanceMode> performanceModeN;
  final int Function() polylineCount;
  final VoidCallback onMapReady;

  @override
  State<_FullScreenLiveMap> createState() => _FullScreenLiveMapState();
}

class _FullScreenLiveMapState extends State<_FullScreenLiveMap> {
  mb.MapboxMap? _mapboxMap;
  mb.PolylineAnnotationManager? _routeOuterManager;
  mb.PolylineAnnotationManager? _routeCoreManager;
  mb.PolylineAnnotationManager? _plannedOuterManager;
  mb.PolylineAnnotationManager? _plannedCoreManager;

  bool _styleLoaded = false;
  bool _locationReady = false;
  bool _disposed = false;
  int _lastRouteCount = -1;
  int _lastRouteSignature = 0;
  int _lastPlannedRouteSignature = 0;
  DateTime? _lastCameraAt;
  DateTime? _lastRouteAt;

  @override
  void initState() {
    super.initState();
    widget.posN.addListener(_onLiveMapInputChanged);
    widget.headingN.addListener(_onLiveMapInputChanged);
    widget.followModeN.addListener(_onFollowModeChanged);
    widget.presetN.addListener(_onMapboxPresetChanged);
    widget.runtimeModeN.addListener(_onMapRuntimeChanged);
    widget.plannedRouteN.addListener(_onPlannedRouteChanged);
    widget.performanceModeN.addListener(_onPerformanceModeChanged);
  }

  @override
  void didUpdateWidget(covariant _FullScreenLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.mapStyle != widget.settings.mapStyle) {
      unawaited(_loadMapboxStyle());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_routeOuterManager?.deleteAll());
    unawaited(_routeCoreManager?.deleteAll());
    unawaited(_plannedOuterManager?.deleteAll());
    unawaited(_plannedCoreManager?.deleteAll());
    widget.posN.removeListener(_onLiveMapInputChanged);
    widget.headingN.removeListener(_onLiveMapInputChanged);
    widget.followModeN.removeListener(_onFollowModeChanged);
    widget.presetN.removeListener(_onMapboxPresetChanged);
    widget.runtimeModeN.removeListener(_onMapRuntimeChanged);
    widget.plannedRouteN.removeListener(_onPlannedRouteChanged);
    widget.performanceModeN.removeListener(_onPerformanceModeChanged);
    super.dispose();
  }

  void _onMapCreated(mb.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    unawaited(_configureMapboxMap());
  }

  Future<void> _configureMapboxMap() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (_disposed || !mounted || map == null) return;

    try {
      await map.scaleBar.updateSettings(mb.ScaleBarSettings(enabled: false));
      await map.compass.updateSettings(mb.CompassSettings(enabled: false));
      await map.attribution.updateSettings(
        mb.AttributionSettings(enabled: true),
      );
      await map.logo.updateSettings(mb.LogoSettings(enabled: true));
    } catch (error) {
      debugPrint('Mapbox ornament settings error: $error');
    }

    await _configureNativeLocationPuck();
    await _loadMapboxStyle();
    widget.onMapReady();
  }

  Future<void> _configureNativeLocationPuck() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null || _locationReady) return;

    try {
      await map.location.updateSettings(
        mb.LocationComponentSettings(
          enabled: true,
          puckBearingEnabled: true,
          puckBearing: mb.PuckBearing.HEADING,
          pulsingEnabled: true,
          pulsingColor: AppColors.blue.value,
          pulsingMaxRadius: 48.0,
          showAccuracyRing: true,
          accuracyRingColor: const Color(0x332563EB).value,
          accuracyRingBorderColor: const Color(0x882563EB).value,
        ),
      );
      _locationReady = true;
    } catch (error) {
      debugPrint('Mapbox location puck error: $error');
    }
  }

  Future<void> _loadMapboxStyle() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (_disposed || !mounted || map == null) return;

    if (_disposed || !mounted) return;

    _styleLoaded = false;
    _lastRouteCount = -1;

    try {
      await map.loadStyleURI(_mapboxStyleUri(widget.settings.mapStyle));
      if (_disposed || !mounted) return;
      _styleLoaded = true;
      _routeOuterManager = null;
      _routeCoreManager = null;
      _plannedOuterManager = null;
      _plannedCoreManager = null;
      _lastRouteSignature = 0;
      _lastPlannedRouteSignature = 0;

      await _configureStandardStyle();
      if (_disposed || !mounted) return;
      await _configureNativeLocationPuck();
      await _rebuildPlannedRouteAnnotations(force: true);
      await _rebuildRouteAnnotations(force: true);
      await _moveCameraToLatest(force: true);
    } catch (error, stackTrace) {
      debugPrint('Mapbox style load error: $error\n$stackTrace');
    }
  }

  Future<void> _configureStandardStyle() async {
    final mb.MapboxMap? map = _mapboxMap;
    if (_disposed || !mounted || map == null) return;

    try {
      await map.style.setStyleImportConfigProperty(
        'basemap',
        'lightPreset',
        widget.presetN.value.mapboxValue,
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
      debugPrint('Mapbox Standard config skipped: $error');
    }
  }

  void _onMapboxPresetChanged() {
    unawaited(_configureStandardStyle());
  }

  void _onMapRuntimeChanged() {
    if (mounted) setState(() {});
  }

  void _onPerformanceModeChanged() {
    _lastRouteCount = -1;
    _lastRouteSignature = 0;
    unawaited(_rebuildRouteAnnotations(force: true));
  }

  void _onPlannedRouteChanged() {
    unawaited(_rebuildPlannedRouteAnnotations(force: true));
  }

  void _onFollowModeChanged() {
    if (widget.followModeN.value != _MapFollowMode.freeView) {
      unawaited(_moveCameraToLatest(force: true));
    }
  }

  void _onLiveMapInputChanged() {
    unawaited(_moveCameraToLatest());
    unawaited(_rebuildRouteAnnotations());
  }

  Future<void> _moveCameraToLatest({bool force = false}) async {
    if (_disposed || !mounted) return;
    final mb.MapboxMap? map = _mapboxMap;
    final LatLng? position = widget.posN.value;
    if (map == null || position == null || !_isValid(position)) return;

    final _MapFollowMode mode = widget.followModeN.value;
    if (mode == _MapFollowMode.freeView && !force) return;

    final DateTime now = DateTime.now();
    final DateTime? last = _lastCameraAt;
    if (!force &&
        last != null &&
        now.difference(last) < widget.performanceModeN.value.cameraThrottle) {
      return;
    }
    _lastCameraAt = now;

    final bool rotatesWithHeading =
        mode == _MapFollowMode.headingUp || mode == _MapFollowMode.northUp;
    final double bearing =
        rotatesWithHeading ? -_normDeg(widget.headingN.value) : 0.0;
    final double pitch = mode == _MapFollowMode.headingUp
        ? 50.0
        : mode == _MapFollowMode.northUp
            ? 28.0
            : 0.0;
    final double zoom = mode == _MapFollowMode.headingUp
        ? 17.2
        : mode == _MapFollowMode.northUp
            ? 16.8
            : 16.3;

    try {
      await map.easeTo(
        mb.CameraOptions(
          center: mb.Point(
            coordinates: mb.Position(position.longitude, position.latitude),
          ),
          zoom: zoom,
          bearing: bearing,
          pitch: pitch,
        ),
        mb.MapAnimationOptions(duration: force ? 650 : 420, startDelay: 0),
      );
    } catch (error) {
      debugPrint('Mapbox camera error: $error');
    }
  }

  Future<void> _rebuildRouteAnnotations({bool force = false}) async {
    if (_disposed || !mounted) return;
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null || !_styleLoaded) return;

    final List<TripPoint> currentPoints = widget.gps.currentPoints;
    final int count = currentPoints.length;
    final int signature = _routeSignature(currentPoints);

    if (!force &&
        count == _lastRouteCount &&
        signature == _lastRouteSignature) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? last = _lastRouteAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 900)) {
      return;
    }

    _lastRouteAt = now;
    _lastRouteCount = count;
    _lastRouteSignature = signature;

    final List<LatLng> safePoints = currentPoints
        .map((TripPoint point) => point.position)
        .where(_isValid)
        .toList(growable: false);

    final int renderLimit = widget.performanceModeN.value.routeRenderLimit;
    final List<LatLng> renderPoints = safePoints.length > renderLimit
        ? simplifyPolyline(
            safePoints,
            epsilon: widget.performanceModeN.value == _TrackingPerformanceMode.battery
                ? 0.00007
                : 0.00004,
          )
        : safePoints;

    final List<mb.Position> coordinates = renderPoints
        .map((LatLng point) => mb.Position(point.longitude, point.latitude))
        .toList(growable: false);

    try {
      _routeOuterManager ??=
          await map.annotations.createPolylineAnnotationManager();
      _routeCoreManager ??=
          await map.annotations.createPolylineAnnotationManager();
      if (_disposed || !mounted) return;

      await _routeOuterManager?.deleteAll();
      await _routeCoreManager?.deleteAll();

      if (coordinates.length < 2) return;

      final mb.LineString line = mb.LineString(coordinates: coordinates);

      await _routeOuterManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: Colors.white.value,
          lineWidth: 12.5,
          lineOpacity: 0.92,
          lineBorderColor: Colors.black.value,
          lineBorderWidth: 2.5,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );

      await _routeCoreManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: AppColors.blue.value,
          lineWidth: 6.5,
          lineOpacity: 0.98,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Mapbox route annotation error: $error\n$stackTrace');
    }
  }

  Future<void> _rebuildPlannedRouteAnnotations({bool force = false}) async {
    if (_disposed || !mounted) return;
    final mb.MapboxMap? map = _mapboxMap;
    if (map == null || !_styleLoaded) return;

    final PlannedRoute? route = widget.plannedRouteN.value;
    final int signature = _plannedRouteSignature(route);

    if (!force && signature == _lastPlannedRouteSignature) {
      return;
    }

    _lastPlannedRouteSignature = signature;

    try {
      _plannedOuterManager ??=
          await map.annotations.createPolylineAnnotationManager();
      _plannedCoreManager ??=
          await map.annotations.createPolylineAnnotationManager();
      if (_disposed || !mounted) return;

      await _plannedOuterManager?.deleteAll();
      await _plannedCoreManager?.deleteAll();

      if (route == null || route.points.length < 2) return;

      final List<mb.Position> coordinates = route.points
          .where(_isValid)
          .map((LatLng point) => mb.Position(point.longitude, point.latitude))
          .toList(growable: false);

      if (coordinates.length < 2) return;

      final mb.LineString line = mb.LineString(coordinates: coordinates);

      await _plannedOuterManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: Colors.white.value,
          lineWidth: 11.0,
          lineOpacity: 0.82,
          lineBorderColor: Colors.black.value,
          lineBorderWidth: 2.0,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );

      await _plannedCoreManager?.create(
        mb.PolylineAnnotationOptions(
          geometry: line,
          lineColor: _kBlue.value,
          lineWidth: 5.4,
          lineOpacity: 0.94,
          lineJoin: mb.LineJoin.ROUND,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Mapbox planned route annotation error: $error\n$stackTrace');
    }
  }

  static int _routeSignature(List<TripPoint> points) {
    if (points.isEmpty) return 0;

    final TripPoint last = points.last;
    final int lat = (last.position.latitude * 100000).round();
    final int lng = (last.position.longitude * 100000).round();
    final int speed = (last.speedMph * 10).round();

    return Object.hash(points.length, lat, lng, speed);
  }

  static int _plannedRouteSignature(PlannedRoute? route) {
    if (route == null || route.points.isEmpty) return 0;

    final LatLng first = route.points.first;
    final LatLng last = route.points.last;

    return Object.hash(
      route.points.length,
      (first.latitude * 100000).round(),
      (first.longitude * 100000).round(),
      (last.latitude * 100000).round(),
      (last.longitude * 100000).round(),
      route.profile,
    );
  }

  static bool _isValid(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90.0 &&
        point.latitude <= 90.0 &&
        point.longitude >= -180.0 &&
        point.longitude <= 180.0;
  }

  static double _normDeg(double degrees) {
    final double normalized = degrees % 360.0;
    return normalized < 0.0 ? normalized + 360.0 : normalized;
  }

  static String _mapboxStyleUri(AppMapStyle style) {
    final String name = style.name.toLowerCase();
    if (name.contains('satellite')) return mb.MapboxStyles.STANDARD_SATELLITE;
    return mb.MapboxStyles.STANDARD;
  }

  Widget _buildWebFallbackMap(BuildContext context) {
    return RepaintBoundary(
      child: fm.FlutterMap(
        mapController: widget.mapController,
        options: fm.MapOptions(
          initialCenter: widget.posN.value ?? _kDefaultCenter,
          initialZoom: _kDefaultZoom,
          interactionOptions: const fm.InteractionOptions(
            flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
          ),
          onMapReady: widget.onMapReady,
          onMapEvent: (fm.MapEvent event) {
            if (event is fm.MapEventMoveStart &&
                event.source != fm.MapEventSource.mapController &&
                widget.followModeN.value != _MapFollowMode.freeView) {
              widget.followModeN.value = _MapFollowMode.freeView;
            }
          },
        ),
        children: <Widget>[
          fm.TileLayer(
            urlTemplate: _webMapTileUrl(widget.settings.mapStyle),
            userAgentPackageName: 'com.trackpro.ai',
            retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.0,
            maxNativeZoom: 19,
            errorTileCallback: (
              fm.TileImage tile,
              Object error,
              StackTrace? stackTrace,
            ) {
              debugPrint('Tracking web fallback tile error: $error');
            },
          ),
          ValueListenableBuilder<PlannedRoute?>(
            valueListenable: widget.plannedRouteN,
            builder: (_, PlannedRoute? route, __) {
              if (route == null || route.points.length < 2) {
                return const SizedBox.shrink();
              }

              return fm.PolylineLayer(
                polylines: <fm.Polyline>[
                  fm.Polyline(
                    points: route.points,
                    color: Colors.white.withValues(alpha: 0.82),
                    strokeWidth: 10.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  fm.Polyline(
                    points: route.points,
                    color: _kBlue.withValues(alpha: 0.92),
                    strokeWidth: 5.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              );
            },
          ),
          ValueListenableBuilder<LatLng?>(
            valueListenable: widget.posN,
            builder: (_, __, ___) {
              final List<LatLng> points = widget.gps.currentPoints
                  .map((TripPoint point) => point.position)
                  .where(_isValid)
                  .toList(growable: false);

              if (points.length < 2) return const SizedBox.shrink();

              final List<LatLng> simplified = points.length > 900
                  ? simplifyPolyline(points, epsilon: 0.00004)
                  : points;
              final List<LatLng> polyline = simplified.length > 2
                  ? smoothPolyline(
                      simplified,
                      tension: 0.5,
                      subdivisions: simplified.length > 500 ? 4 : 8,
                    )
                  : simplified;

              return fm.PolylineLayer(
                polylines: <fm.Polyline>[
                  fm.Polyline(
                    points: polyline,
                    color: Colors.white.withValues(alpha: 0.96),
                    strokeWidth: 12.0,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  fm.Polyline(
                    points: polyline,
                    color: AppColors.blue.withValues(alpha: 0.96),
                    strokeWidth: 6.5,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              );
            },
          ),
          ValueListenableBuilder<LatLng?>(
            valueListenable: widget.posN,
            builder: (_, LatLng? position, __) {
              if (position == null || !_isValid(position)) {
                return const SizedBox.shrink();
              }

              return fm.MarkerLayer(
                markers: <fm.Marker>[
                  fm.Marker(
                    point: position,
                    width: 74,
                    height: 74,
                    alignment: Alignment.center,
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.headingN,
                      builder: (_, double heading, __) {
                        return ValueListenableBuilder<_MapFollowMode>(
                          valueListenable: widget.followModeN,
                          builder: (_, _MapFollowMode mode, __) {
                            final double markerHeading =
                                mode == _MapFollowMode.headingUp
                                    ? 0.0
                                    : heading;
                            return _LocationPuckMarker(
                              heading: markerHeading,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _webMapTileUrl(AppMapStyle style) {
    final String name = style.name.toLowerCase();
    final String token = _kMapboxAccessToken;

    if (token.isEmpty) {
      if (name.contains('light')) {
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      }

      if (name.contains('dark')) {
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}';
      }

      return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }

    final String styleId = name.contains('satellite')
        ? 'satellite-streets-v12'
        : name.contains('light')
            ? 'navigation-day-v1'
            : 'navigation-night-v1';

    return 'https://api.mapbox.com/styles/v1/mapbox/$styleId/'
        'tiles/512/{z}/{x}/{y}@2x?access_token=$token';
  }

  @override
  Widget build(BuildContext context) {
    final MapboxRuntimeMode runtimeMode = widget.runtimeModeN.value;
    final bool useFallback = kIsWeb ||
        runtimeMode == MapboxRuntimeMode.webFallback ||
        _kMapboxAccessToken.isEmpty;

    if (useFallback) {
      return _buildWebFallbackMap(context);
    }

    final LatLng center = widget.posN.value ?? _kDefaultCenter;
    final String styleUri = _mapboxStyleUri(widget.settings.mapStyle);

    return RepaintBoundary(
      child: mb.MapWidget(
        key: ValueKey<String>('native-mapbox-$styleUri'),
        styleUri: styleUri,
        viewport: mb.CameraViewportState(
          center: mb.Point(
            coordinates: mb.Position(center.longitude, center.latitude),
          ),
          zoom: _kDefaultZoom,
          pitch: 0.0,
          bearing: 0.0,
        ),
        textureView: true,
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: (_) {
          _styleLoaded = true;
          unawaited(_configureStandardStyle());
          unawaited(_configureNativeLocationPuck());
          unawaited(_rebuildPlannedRouteAnnotations(force: true));
          unawaited(_rebuildRouteAnnotations(force: true));
          unawaited(_moveCameraToLatest(force: true));
        },
        onScrollListener: (_) {
          if (widget.followModeN.value != _MapFollowMode.freeView) {
            widget.followModeN.value = _MapFollowMode.freeView;
          }
        },
      ),
    );
  }
}
