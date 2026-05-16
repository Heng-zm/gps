part of 'map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FLUTTER MAP FALLBACK LAYER
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// FLUTTER MAP LAYER
// ─────────────────────────────────────────────────────────────────────────────

class _FlutterMapLayer extends StatelessWidget {
  const _FlutterMapLayer({
    super.key,
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
  final PlannedRoute? plannedRoute;
  final List<fm.Marker> allMarkers;
  final bool showSpeedGradient;
  final MapStyle mapStyle;
  final double currentZoom;
  final VoidCallback onMapReady;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onUserDrag;

  Widget _buildPlannedRouteLayer() {
    final PlannedRoute? route = plannedRoute;
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

