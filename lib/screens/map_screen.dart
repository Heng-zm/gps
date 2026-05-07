import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Import both map providers with prefixes to avoid LatLng conflicts
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as am;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;

import '../models/trip_data.dart';
import '../services/settings_service.dart';

// ─── Palette (OLED Gold Theme) ────────────────────────────────────────────────

class _Gold {
  static const bright = Color(0xFFEDD068);
  static const mid = Color(0xFFD4A843);
  static const dark = Color(0xFF8B6914);
  static const ink = Color(0xFF1A1500);
  static const surface = Color(0xFF0D0D0D);
  static const card = Color(0xFF151515);
}

// ─── MapScreen ────────────────────────────────────────────────────────────────

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
  // Common State
  late List<TripPoint> _points;
  bool _followUser = true;
  final SettingsService _settings = SettingsService.instance;

  // Apple Map Specifics
  am.AppleMapController? _appleController;
  am.MapType _appleMapType = am.MapType.standard;

  // Flutter Map Specifics
  final fm.MapController _flutterController = fm.MapController();
  int _flutterMapStyleIdx = 0;
  final List<String> _flutterTileUrls = [
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  ];

  @override
  void initState() {
    super.initState();
    _points = widget.points.where((p) => p.position.latitude.isFinite).toList();
    if (!widget.isLive) _followUser = false;
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLive && widget.points.length != _points.length) {
      setState(() {
        _points =
            widget.points.where((p) => p.position.latitude.isFinite).toList();
      });
      if (_followUser) _centerOnUser();
    }
  }

  bool get _useAppleMaps => !kIsWeb && Platform.isIOS;

  void _toggleMapStyle() {
    setState(() {
      if (_useAppleMaps) {
        _appleMapType = _appleMapType == am.MapType.standard
            ? am.MapType.hybrid
            : am.MapType.standard;
      } else {
        _flutterMapStyleIdx =
            (_flutterMapStyleIdx + 1) % _flutterTileUrls.length;
      }
    });
  }

  void _centerOnUser() {
    if (_points.isEmpty) return;
    final last = _points.last.position;

    if (_useAppleMaps) {
      _appleController?.animateCamera(am.CameraUpdate.newLatLngZoom(
          am.LatLng(last.latitude, last.longitude), 16));
    } else {
      _flutterController.move(ll.LatLng(last.latitude, last.longitude), 16);
    }
    setState(() => _followUser = true);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: _Gold.surface,
      child: Stack(
        children: [
          _useAppleMaps ? _buildAppleMap() : _buildFlutterMap(),
          _buildTopOverlay(),
          _buildBottomOverlay(),
        ],
      ),
    );
  }

  // ─── iOS Native Apple Map ──────────────────────────────────────────

  Widget _buildAppleMap() {
    final last = _points.isNotEmpty
        ? _points.last.position
        : const ll.LatLng(11.5564, 104.9282);

    return am.AppleMap(
      initialCameraPosition: am.CameraPosition(
          target: am.LatLng(last.latitude, last.longitude), zoom: 15),
      mapType: _appleMapType,
      trackingMode: _followUser ? am.TrackingMode.follow : am.TrackingMode.none,
      myLocationEnabled: true,
      onMapCreated: (c) => _appleController = c,
      onCameraMoveStarted: () {
        if (_followUser) setState(() => _followUser = false);
      },
      polylines: {
        am.Polyline(
          polylineId: am.PolylineId('path'), // FIXED: Added const
          points: _points
              .map((p) => am.LatLng(p.position.latitude, p.position.longitude))
              .toList(),
          color: _Gold.mid,
          width: 6,
          jointType: am.JointType.round,
        ),
      },
      annotations: {
        if (_points.isNotEmpty)
          am.Annotation(
            annotationId: am.AnnotationId('start'), // FIXED: Added const
            position: am.LatLng(_points.first.position.latitude,
                _points.first.position.longitude),
            icon: am.BitmapDescriptor.defaultAnnotationWithHue(
                am.BitmapDescriptor.hueRed),
          ),
      },
    );
  }

  // ─── Web / Android Flutter Map ─────────────────────────────────────

  Widget _buildFlutterMap() {
    final last = _points.isNotEmpty
        ? _points.last.position
        : const ll.LatLng(11.5564, 104.9282);

    return fm.FlutterMap(
      mapController: _flutterController,
      options: fm.MapOptions(
        initialCenter: last,
        initialZoom: 15,
        onPointerDown: (_, __) {
          if (_followUser) setState(() => _followUser = false);
        },
      ),
      children: [
        fm.TileLayer(
          urlTemplate: _flutterTileUrls[_flutterMapStyleIdx],
          subdomains: const ['a', 'b', 'c', 'd'],
        ),
        if (_points.length > 1)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(
                points: _points.map((p) => p.position).toList(),
                color: _Gold.mid,
                strokeWidth: 4,
              ),
            ],
          ),
        if (_points.isNotEmpty)
          fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: _points.first.position,
                child: Container(
                    decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2))),
              ),
              fm.Marker(
                point: _points.last.position,
                width: 30,
                height: 30,
                child: const Icon(CupertinoIcons.location_fill,
                    color: _Gold.bright, size: 20),
              ),
            ],
          ),
      ],
    );
  }

  // ─── UI Overlays ───────────────────────────────────────────────────

  Widget _buildTopOverlay() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            _GlassBtn(
                icon: CupertinoIcons.chevron_left,
                onTap: () => Navigator.pop(context)),
            const SizedBox(width: 12),
            _Badge(isLive: widget.isLive),
            const Spacer(),
            _GlassBtn(
              icon: _useAppleMaps
                  ? (_appleMapType == am.MapType.standard
                      ? CupertinoIcons.map
                      : CupertinoIcons.layers_fill)
                  : (_flutterMapStyleIdx == 0
                      ? CupertinoIcons.map
                      : CupertinoIcons.layers_fill),
              onTap: _toggleMapStyle,
              color: _Gold.bright,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _GlassBtn(
                  icon: CupertinoIcons.location_fill,
                  onTap: _centerOnUser,
                  size: 54,
                  active: _followUser),
              const SizedBox(height: 12),
              _StatsPanel(points: _points, settings: _settings),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Supporting Widgets ──────────────────────────────────────────────

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool active;
  final Color color;

  const _GlassBtn(
      {required this.icon,
      required this.onTap,
      this.size = 44,
      this.active = false,
      this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // FIXED: Use withValues instead of withOpacity
          color: active ? _Gold.mid : _Gold.card.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: _Gold.dark.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: active ? _Gold.ink : color, size: size * 0.45),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final bool isLive;
  const _Badge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          // FIXED: Use withValues instead of withOpacity
          color: _Gold.card.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Gold.dark.withValues(alpha: 0.3))),
      child: Text(isLive ? 'LIVE' : 'HISTORY',
          style: const TextStyle(
              color: _Gold.bright,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2)),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final List<TripPoint> points;
  final SettingsService settings;
  const _StatsPanel({required this.points, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          // FIXED: Use withValues instead of withOpacity
          color: _Gold.card.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _Gold.dark.withValues(alpha: 0.3))),
      child: points.isEmpty
          ? const SizedBox(
              height: 40, child: Center(child: CupertinoActivityIndicator()))
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(
                    label: 'SPEED',
                    value: settings
                        .toDisplaySpeed(points.last.speedMph)
                        .toInt()
                        .toString(),
                    unit: settings.speedUnit),
                _Stat(
                    label: 'ALTITUDE',
                    value: settings.useKmh
                        ? (points.last.altitudeFt * 0.3048).toInt().toString()
                        : points.last.altitudeFt.toInt().toString(),
                    unit: settings.altitudeUnit),
              ],
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value, unit;
  const _Stat({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                // FIXED: Use withValues instead of withOpacity
                color: _Gold.mid.withValues(alpha: 0.6),
                fontSize: 9,
                fontWeight: FontWeight.w800)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(width: 2),
            Text(unit, style: const TextStyle(color: _Gold.mid, fontSize: 10)),
          ],
        )
      ],
    );
  }
}
