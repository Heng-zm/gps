import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';

import '../models/trip_data.dart';
import '../utils/smooth_polyline.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
const _kGold = Color(0xFFD4A843);
const _kRed = Color(0xFFE74C3C);
const _kTeal = Color(0xFF4ECDC4);
const _kBg = Color(0xFF070707);
const _kCard = Color(0xFF111111);
const _kCardBorder = Color(0xFF1E1E1E);

class MapScreen extends StatefulWidget {
  final List<TripPoint> points;
  final bool isLive;

  const MapScreen({
    super.key,
    required this.points,
    required this.isLive,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final fm.MapController _mapController = fm.MapController();

  List<LatLng> _smoothedPoints = [];
  List<LatLng> _rawPoints = [];
  List<_SpeedSegment> _speedSegments = [];

  bool _followMode = true;
  bool _showSpeedGradient = false;
  double _currentZoom = 16.0;
  double _calculatedDistance = 0.0;
  double _calculatedMaxSpeed = 0.0;
  int _peakSpeedIndex = -1;

  // FIX: Track bottom panel height via notifier so HUD/zoom buttons
  // reposition reactively without magic-number constants.
  final ValueNotifier<double> _bottomPanelHeight = ValueNotifier(0);

  late AnimationController _markerPulseController;

  @override
  void initState() {
    super.initState();
    _markerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    // FIX: Single pass over widget.points instead of two separate calls.
    _processPoints();
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points != oldWidget.points) {
      // FIX: Single pass here too.
      _processPoints();
      if (_followMode && widget.isLive && widget.points.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(widget.points.last.position, _currentZoom);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _markerPulseController.dispose();
    _bottomPanelHeight.dispose();
    // FIX: Wrapped in try/catch; controller can throw if map never mounted.
    try {
      _mapController.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ── Stats + Route — single pass ────────────────────────────────────────────

  /// FIX: Merged `_recalculateTripStats` and `_buildSmoothedRoute` into one
  /// method so `widget.points` is only iterated once per update.
  void _processPoints() {
    if (widget.points.isEmpty) {
      setState(() {
        _calculatedDistance = 0.0;
        _calculatedMaxSpeed = 0.0;
        _peakSpeedIndex = -1;
        _smoothedPoints = [];
        _rawPoints = [];
        _speedSegments = [];
      });
      return;
    }

    // ── Stats ────────────────────────────────────────────────────────────────
    double dist = 0;
    double maxS = 0;
    int maxIdx = 0;
    const Distance distCalc = Distance();

    final rawPoints = <LatLng>[];
    final List<_SpeedSegment> segments = [];

    for (int i = 0; i < widget.points.length; i++) {
      final pt = widget.points[i];
      rawPoints.add(pt.position);

      if (pt.speedMph > maxS) {
        maxS = pt.speedMph;
        maxIdx = i;
      }
      if (i > 0) {
        dist += distCalc.as(
          LengthUnit.Kilometer,
          widget.points[i - 1].position,
          pt.position,
        );
        // Build speed segments in the same pass.
        final double avgSpeed =
            (widget.points[i - 1].speedMph + pt.speedMph) / 2;
        segments.add(_SpeedSegment(
          points: [widget.points[i - 1].position, pt.position],
          color: _speedColor(avgSpeed),
        ));
      }
    }

    // ── Smooth route ─────────────────────────────────────────────────────────
    final simplified = simplifyPolyline(rawPoints, epsilon: 0.000035);
    final smoothed = smoothPolyline(simplified, tension: 0.5, subdivisions: 10);

    setState(() {
      _calculatedDistance = dist;
      _calculatedMaxSpeed = maxS;
      _peakSpeedIndex = maxIdx;
      _rawPoints = rawPoints;
      _smoothedPoints = smoothed;
      _speedSegments = segments;
    });
  }

  Color _speedColor(double mph) {
    if (mph < 10) return const Color(0xFF4ECDC4);
    if (mph < 25) return const Color(0xFF27AE60);
    if (mph < 45) return const Color(0xFFD4A843);
    if (mph < 65) return const Color(0xFFE67E22);
    return const Color(0xFFE74C3C);
  }

  // ── Fit bounds ─────────────────────────────────────────────────────────────

  void _fitRoute() {
    if (_rawPoints.isEmpty) return;
    if (_rawPoints.length == 1) {
      _mapController.move(_rawPoints.first, _currentZoom);
      return;
    }
    final bounds = fm.LatLngBounds.fromPoints(_rawPoints);
    _mapController.fitCamera(
      fm.CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(64),
      ),
    );
    setState(() {
      _followMode = false;
      _currentZoom = _mapController.camera.zoom;
    });
  }

  void _toggleFollow() {
    final newFollow = !_followMode;
    setState(() => _followMode = newFollow);
    if (newFollow && widget.points.isNotEmpty) {
      _mapController.move(widget.points.last.position, _currentZoom);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final List<fm.Marker> allMarkers = _buildMarkers();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: [
            fm.FlutterMap(
              mapController: _mapController,
              options: fm.MapOptions(
                initialCenter: widget.points.isNotEmpty
                    ? widget.points.last.position
                    : const LatLng(0, 0),
                initialZoom: _currentZoom,
                onMapEvent: (event) {
                  if (event is fm.MapEventMove) {
                    _currentZoom = event.camera.zoom;
                  }
                  if (event is fm.MapEventMoveStart &&
                      event.source != fm.MapEventSource.mapController) {
                    if (_followMode) {
                      setState(() => _followMode = false);
                    }
                  }
                },
                interactionOptions: const fm.InteractionOptions(
                  flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
                ),
              ),
              children: [
                fm.TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.rideai.app',
                ),
                if (_smoothedPoints.isNotEmpty)
                  _showSpeedGradient
                      ? _buildSpeedGradientLayer()
                      : _buildSmoothPolylineLayer(),
                fm.MarkerLayer(markers: allMarkers),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildHeader(context),
            ),
            // FIX: HUD and zoom buttons now use ValueNotifier<double> for the
            // bottom offset so they sit just above the bottom panel regardless
            // of whether the speed legend is visible.
            if (widget.points.isNotEmpty)
              ValueListenableBuilder<double>(
                valueListenable: _bottomPanelHeight,
                builder: (_, panelH, __) => Positioned(
                  left: 16,
                  bottom: panelH + 12,
                  child: _buildLiveSpeedHUD(),
                ),
              ),
            ValueListenableBuilder<double>(
              valueListenable: _bottomPanelHeight,
              builder: (_, panelH, __) => Positioned(
                right: 16,
                bottom: panelH + 12,
                child: _buildZoomControls(),
              ),
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

  // ── Marker builder ─────────────────────────────────────────────────────────

  List<fm.Marker> _buildMarkers() {
    if (widget.points.isEmpty) return const [];

    final List<fm.Marker> markers = [
      _startMarker(widget.points.first.position),
    ];

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

  // ── Polyline layers ────────────────────────────────────────────────────────

  Widget _buildSmoothPolylineLayer() {
    return fm.PolylineLayer(
      polylines: [
        fm.Polyline(
          points: _smoothedPoints,
          color: _kGold.withValues(alpha: 0.25),
          strokeWidth: 10,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        fm.Polyline(
          points: _smoothedPoints,
          color: _kGold,
          strokeWidth: 4.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }

  /// FIX: Single loop instead of two — builds glow + solid polyline for each
  /// segment together, halving the number of list iterations.
  Widget _buildSpeedGradientLayer() {
    final List<fm.Polyline> polylines = [];
    for (final seg in _speedSegments) {
      // Glow pass
      polylines.add(fm.Polyline(
        points: seg.points,
        color: seg.color.withValues(alpha: 0.3),
        strokeWidth: 10,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));
      // Solid pass
      polylines.add(fm.Polyline(
        points: seg.points,
        color: seg.color,
        strokeWidth: 4.5,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
      ));
    }
    return fm.PolylineLayer(polylines: polylines);
  }

  // ── Markers ────────────────────────────────────────────────────────────────

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
                spreadRadius: 1,
              ),
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
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(CupertinoIcons.checkmark_alt,
              color: Colors.white, size: 13),
        ),
      );

  fm.Marker _liveMarker(LatLng pos) => fm.Marker(
        point: pos,
        width: 80,
        height: 80,
        child: AnimatedBuilder(
          animation: _markerPulseController,
          builder: (_, __) {
            final double scale = _markerPulseController.value;
            final double opacity = (1.0 - scale).clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 60 * scale,
                  height: 60 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kRed.withValues(alpha: opacity * 0.45),
                    border: Border.all(
                      color: _kRed.withValues(alpha: opacity * 0.7),
                      width: 1.2,
                    ),
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: _kRed, width: 3.5),
                    boxShadow: [
                      BoxShadow(
                        color: _kRed.withValues(alpha: 0.8),
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

  /// FIX: Replaced deprecated `.withOpacity()` with `.withValues(alpha:)`.
  fm.Marker _speedTagMarker(TripPoint point) => fm.Marker(
        point: point.position,
        width: 40,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _speedColor(point.speedMph).withValues(alpha: 0.5),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            point.speedMph.toStringAsFixed(0),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

  /// FIX: Removed unnecessary wrapping `Column` around the single `Container`.
  /// FIX: `BoxShadow` now uses named `color:` parameter with `.withValues()`.
  fm.Marker _peakSpeedMarker(TripPoint point) => fm.Marker(
        point: point.position,
        width: 60,
        height: 26,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _kGold,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.bolt_fill,
                  color: Colors.black, size: 10),
              const SizedBox(width: 2),
              Text(
                '${point.speedMph.toStringAsFixed(0)} peak',
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

  // ── Live Speed HUD ────────────────────────────────────────────────────────

  /// FIX: `.withOpacity()` replaced with `.withValues(alpha:)`.
  /// FIX: `BoxShadow` uses named `color:` parameter.
  Widget _buildLiveSpeedHUD() {
    if (widget.points.isEmpty) return const SizedBox.shrink();
    final lastPoint = widget.points.last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.54),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CURRENT SPEED',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                lastPoint.speedMph.toStringAsFixed(0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'MPH',
                style: TextStyle(
                  color: _kGold,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 12,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.07),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kCardBorder),
              ),
              child: const Icon(CupertinoIcons.chevron_left,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isLive ? 'LIVE TRACKING' : 'TRIP MAP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                '${widget.points.length} points recorded',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: () =>
                setState(() => _showSpeedGradient = !_showSpeedGradient),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _showSpeedGradient
                    ? _kGold.withValues(alpha: 0.15)
                    : _kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _showSpeedGradient ? _kGold : _kCardBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.speed_rounded,
                    color: _showSpeedGradient ? _kGold : Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'SPEED',
                    style: TextStyle(
                      color: _showSpeedGradient ? _kGold : Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom panel ───────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    if (widget.points.isEmpty) return const SizedBox.shrink();

    return MeasureSize(
      onChange: (size) => _bottomPanelHeight.value = size.height,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _kCardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showSpeedGradient) ...[
              _buildSpeedLegend(),
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                _InfoChip(
                  label: 'DISTANCE',
                  value: '${_calculatedDistance.toStringAsFixed(2)} km',
                  color: _kTeal,
                ),
                _InfoChip(
                  label: 'MAX SPEED',
                  value: '${_calculatedMaxSpeed.toStringAsFixed(0)} mph',
                  color: _kGold,
                ),
                _InfoChip(
                  label: 'POINTS',
                  value: '${widget.points.length}',
                  color: _kRed,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MapActionButton(
                    icon: CupertinoIcons.arrow_down_right_arrow_up_left,
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
                    label: _followMode ? 'FOLLOWING' : 'FOLLOW',
                    isActive: _followMode,
                    onTap: _toggleFollow,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedLegend() {
    const List<_LegendItem> items = [
      _LegendItem(color: Color(0xFF4ECDC4), label: '<10'),
      _LegendItem(color: Color(0xFF27AE60), label: '10–25'),
      _LegendItem(color: Color(0xFFD4A843), label: '25–45'),
      _LegendItem(color: Color(0xFFE67E22), label: '45–65'),
      _LegendItem(color: Color(0xFFE74C3C), label: '65+'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: item.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${item.label} mph',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  // ── Zoom controls ──────────────────────────────────────────────────────────

  Widget _buildZoomControls() {
    return Column(
      children: [
        _ZoomButton(
          icon: CupertinoIcons.plus,
          onTap: () {
            final double z = (_mapController.camera.zoom + 1).clamp(3.0, 19.0);
            setState(() => _currentZoom = z);
            _mapController.move(_mapController.camera.center, z);
          },
        ),
        const SizedBox(height: 8),
        _ZoomButton(
          icon: CupertinoIcons.minus,
          onTap: () {
            final double z = (_mapController.camera.zoom - 1).clamp(3.0, 19.0);
            setState(() => _currentZoom = z);
            _mapController.move(_mapController.camera.center, z);
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEASURE SIZE HELPER
// Used to measure the bottom panel's rendered height so HUD/zoom buttons
// can sit exactly above it without hardcoded magic numbers.
// ─────────────────────────────────────────────────────────────────────────────

typedef _OnWidgetSizeChange = void Function(Size size);

class MeasureSize extends StatefulWidget {
  final Widget child;
  final _OnWidgetSizeChange onChange;

  const MeasureSize({
    super.key,
    required this.onChange,
    required this.child,
  });

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final newSize = box.size;
      if (_oldSize != newSize) {
        _oldSize = newSize;
        widget.onChange(newSize);
      }
    });
    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASSES & SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedSegment {
  final List<LatLng> points;
  final Color color;
  const _SpeedSegment({required this.points, required this.color});
}

class _LegendItem {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});
}

class _InfoChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _InfoChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
            color: isActive ? _kGold.withValues(alpha: 0.5) : _kCardBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive ? _kGold : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? _kGold : Colors.white70,
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
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kCardBorder),
        ),
        child: Icon(icon, color: Colors.white70, size: 18),
      ),
    );
  }
}
