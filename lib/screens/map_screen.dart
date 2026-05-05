import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_data.dart';

class MapScreen extends StatefulWidget {
  final List<TripPoint> points;
  final bool isLive;

  const MapScreen({
    super.key,
    required this.points,
    this.isLive = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  // PERFORMANCE: Cached lists to achieve O(1) rendering & memory efficiency
  late List<TripPoint> _points;
  late List<LatLng> _polylinePoints;

  bool _followUser = true;

  @override
  void initState() {
    super.initState();
    _initializeData();

    if (!widget.isLive) {
      // If viewing a finished trip, don't continuously lock the camera to the user
      _followUser = false;
    }
  }

  void _initializeData() {
    _points = List.from(widget.points);
    _polylinePoints = _points.map((p) => p.position).toList();
  }

  // BUG FIX & UPGRADE: Replaced the anti-pattern polling `Timer` with Flutter's native lifecycle.
  // This reacts instantly when the parent widget updates the point list, costing zero idle resources.
  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLive && widget.points.length != oldWidget.points.length) {
      if (widget.points.length > _points.length) {
        // PERFORMANCE: Efficiently append only the new points (O(1) appending)
        final newPts = widget.points.sublist(_points.length);

        setState(() {
          _points.addAll(newPts);
          _polylinePoints.addAll(newPts.map((p) => p.position));
        });

        // Automatically pan the map as the user drives if follow mode is active
        if (_followUser && _points.isNotEmpty) {
          _mapController.move(
              _points.last.position, _mapController.camera.zoom);
        }
      } else {
        // Edge Case: The entire list was cleared or replaced upstream
        setState(() => _initializeData());
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng? get _currentPosition =>
      _points.isEmpty ? null : _points.last.position;

  void _centerOnUser() {
    final pos = _currentPosition;
    if (pos == null) return;
    _mapController.move(pos, 16.0);
    setState(() => _followUser = true);
  }

  @override
  Widget build(BuildContext context) {
    // Defaults to Phnom Penh, Cambodia if there's no initial position data yet
    final center = _currentPosition ?? const LatLng(11.5564, 104.9282);

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.0,
              // UX FIX: Automatically calculates bounds to perfectly frame finished routes
              initialCameraFit: (!widget.isLive && _polylinePoints.length > 1)
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(_polylinePoints),
                      padding: const EdgeInsets.all(50.0),
                    )
                  : null,
              onPositionChanged: (position, hasGesture) {
                // If user physically drags the map, disconnect the camera lock
                if (hasGesture && _followUser) {
                  setState(() => _followUser = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.gpstracker',
              ),
              if (_polylinePoints.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polylinePoints, // Uses the cached list directly
                      color: const Color(0xFF4ECDC4),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
              if (_points.isNotEmpty)
                MarkerLayer(
                  markers: [
                    // Start Marker
                    Marker(
                      point: _points.first.position,
                      width: 20.0,
                      height: 20.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE74C3C),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.0),
                        ),
                      ),
                    ),
                    // Current Position / End Marker
                    if (_points.length > 1)
                      Marker(
                        point: _points.last.position,
                        width: 28.0,
                        height: 28.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF4ECDC4),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3.0),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4ECDC4)
                                    .withValues(alpha: 0.5),
                                blurRadius: 12.0,
                                spreadRadius: 4.0,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),

          // Top App Bar Header Overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40.0,
                      height: 40.0,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: const Icon(CupertinoIcons.chevron_left,
                          color: Colors.white, size: 18.0),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.isLive) ...[
                          Container(
                            width: 8.0,
                            height: 8.0,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ECDC4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                        ],
                        Text(
                          widget.isLive ? 'LIVE TRACKING' : 'TRIP ROUTE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Stats Panel Overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: _centerOnUser,
                      child: Container(
                        width: 44.0,
                        height: 44.0,
                        margin: const EdgeInsets.only(bottom: 12.0),
                        decoration: BoxDecoration(
                          color: _followUser
                              ? const Color(0xFF4ECDC4)
                              : const Color(0xFF1A1A1A).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12.0),
                          border: _followUser
                              ? null
                              : Border.all(color: const Color(0xFF333333)),
                        ),
                        child: Icon(
                          CupertinoIcons.location_fill,
                          color: _followUser ? Colors.black : Colors.white,
                          size: 20.0,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      child: _points.isEmpty
                          ? const Center(
                              child: Text(
                                'No GPS data yet',
                                style: TextStyle(color: Color(0xFF666666)),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _MapStat(
                                  label: 'SPEED',
                                  value: '${_points.last.speedMph.toInt()}',
                                  unit: 'mph',
                                ),
                                const _VertDivider(),
                                _MapStat(
                                  label: 'POINTS',
                                  value: '${_points.length}',
                                  unit: 'pts',
                                ),
                                const _VertDivider(),
                                _MapStat(
                                  label: 'ALTITUDE',
                                  value: '${_points.last.altitudeFt.toInt()}',
                                  unit: 'ft',
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStat extends StatelessWidget {
  final String label, value, unit;

  const _MapStat({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF666666),
            fontSize: 10.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4.0),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22.0,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2.0),
            Text(
              unit,
              style: const TextStyle(
                color: Color(0xFF4ECDC4),
                fontSize: 11.0,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  const _VertDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1.0,
        height: 36.0,
        color: const Color(0xFF2A2A2A),
      );
}
