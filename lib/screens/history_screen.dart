import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';

import '../services/settings_service.dart';

/// ─── MODEL: SAVED ROUTE POINT ───────────────────────────────────────────────
/// Stores individual GPS points and speeds to recreate the map polyline.
class SavedRoutePoint {
  final double lat;
  final double lng;
  final double speedMph;

  SavedRoutePoint({
    required this.lat,
    required this.lng,
    required this.speedMph,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'spd': speedMph,
      };

  factory SavedRoutePoint.fromJson(Map<String, dynamic> json) {
    return SavedRoutePoint(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      speedMph: (json['spd'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// ─── MODEL: SAVED TRIP ──────────────────────────────────────────────────────
class SavedTrip {
  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;

  // NEW: The recorded route coordinates
  final List<SavedRoutePoint> route;

  late final String formattedDate =
      DateFormat('MMM d, yyyy · h:mm a').format(date);
  late final String formattedDuration = _calculateFormattedDuration();

  SavedTrip({
    required this.id,
    required this.date,
    required this.distanceMiles,
    required this.maxSpeedMph,
    required this.avgSpeedMph,
    required this.totalTime,
    required this.altitudeGainFt,
    required this.route, // Added to constructor
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'distanceMiles': distanceMiles,
        'maxSpeedMph': maxSpeedMph,
        'avgSpeedMph': avgSpeedMph,
        'totalTimeSeconds': totalTime.inSeconds,
        'altitudeGainFt': altitudeGainFt,
        // Save the route points as a JSON array
        'route_points': route.map((p) => p.toJson()).toList(),
      };

  static SavedTrip? tryFromJson(Map<String, dynamic> json) {
    final rawDate = (json['date'] as num?)?.toInt();
    if (rawDate == null || rawDate == 0) {
      debugPrint('SavedTrip.tryFromJson: missing or zero date — skipping.');
      return null;
    }

    // Parse the route points safely
    final rawRoute = json['route_points'] as List<dynamic>? ?? [];
    final parsedRoute = rawRoute
        .map((e) => SavedRoutePoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return SavedTrip(
      id: json['id']?.toString() ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(rawDate),
      distanceMiles: (json['distanceMiles'] as num?)?.toDouble() ?? 0.0,
      maxSpeedMph: (json['maxSpeedMph'] as num?)?.toDouble() ?? 0.0,
      avgSpeedMph: (json['avgSpeedMph'] as num?)?.toDouble() ?? 0.0,
      totalTime:
          Duration(seconds: (json['totalTimeSeconds'] as num?)?.toInt() ?? 0),
      altitudeGainFt: (json['altitudeGainFt'] as num?)?.toDouble() ?? 0.0,
      route: parsedRoute, // Assign mapped route
    );
  }

  String _calculateFormattedDuration() {
    final h = totalTime.inHours;
    final m = totalTime.inMinutes.remainder(60);
    final s = totalTime.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  // ── SUPABASE CRUD ──────────────────────────────────────────────────────────

  static Future<bool> saveTrip(SavedTrip trip) async {
    try {
      await Supabase.instance.client
          .from('saved_trips')
          .upsert(trip.toJson(), onConflict: 'id');
      return true;
    } catch (e) {
      debugPrint('Supabase Save Error: $e');
      return false;
    }
  }

  static Future<List<SavedTrip>> loadAllTrips() async {
    try {
      final data = await Supabase.instance.client
          .from('saved_trips')
          .select()
          .order('date', ascending: false);

      final List<SavedTrip> trips = [];
      for (final row in data) {
        try {
          final trip = SavedTrip.tryFromJson(row);
          if (trip != null) trips.add(trip);
        } catch (e) {
          debugPrint('Skipped corrupted record: $e');
        }
      }
      return trips;
    } catch (e) {
      debugPrint('Supabase Load Error: $e');
      return [];
    }
  }

  static Future<bool> deleteTrip(String id) async {
    try {
      await Supabase.instance.client.from('saved_trips').delete().eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Supabase Delete Error: $e');
      return false;
    }
  }
}

/// ─── SCREEN: HISTORY ────────────────────────────────────────────────────────
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SettingsService _settings = SettingsService.instance;
  List<SavedTrip> _trips = [];
  bool _loading = true;

  double _totalMiles = 0;
  double _allTimeTopSpeedMph = 0;
  int _totalMinutes = 0;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_updateUI);
    _loadTrips();
  }

  @override
  void dispose() {
    _settings.removeListener(_updateUI);
    super.dispose();
  }

  void _updateUI() {
    if (mounted) setState(() {});
  }

  void _calculateLifetimeStats() {
    double tempMiles = 0;
    double tempTopSpeed = 0;
    int tempMinutes = 0;

    for (final t in _trips) {
      tempMiles += t.distanceMiles;
      if (t.maxSpeedMph > tempTopSpeed) tempTopSpeed = t.maxSpeedMph;
      tempMinutes += t.totalTime.inMinutes;
    }

    _totalMiles = tempMiles;
    _allTimeTopSpeedMph = tempTopSpeed;
    _totalMinutes = tempMinutes;
  }

  Future<void> _loadTrips() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final results = await SavedTrip.loadAllTrips();

    if (mounted) {
      setState(() {
        _trips = results;
        _calculateLifetimeStats();
        _loading = false;
      });
    }
  }

  Future<void> _executeDelete(SavedTrip trip) async {
    await HapticFeedback.mediumImpact();
    final originalIndex = _trips.indexOf(trip);

    setState(() {
      _trips.remove(trip);
      _calculateLifetimeStats();
    });

    final success = await SavedTrip.deleteTrip(trip.id);

    if (!success && mounted) {
      setState(() {
        if (originalIndex >= 0 && originalIndex <= _trips.length) {
          _trips.insert(originalIndex, trip);
        } else {
          _trips.add(trip);
        }
        _calculateLifetimeStats();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete. Connection error.'),
            backgroundColor: Color(0xFFE74C3C),
          ),
        );
      }
    }
  }

  Future<bool> _confirmDelete(SavedTrip trip) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('Delete Trip'),
        content:
            const Text('Permanently remove this recording from the cloud?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _executeDelete(trip);
    }
    return false;
  }

  void _openTripDetails(SavedTrip trip) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => TripDetailScreen(trip: trip, settings: _settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000), // Flat Black Aesthetic
      child: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _loadTrips),
            SliverToBoxAdapter(child: _buildHeader()),
            if (!_loading && _trips.isNotEmpty)
              SliverToBoxAdapter(child: _buildLifetimeSummary()),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CupertinoActivityIndicator(radius: 12)),
                ),
              )
            else if (_trips.isEmpty)
              const SliverToBoxAdapter(child: _EmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: SliverList.builder(
                  itemCount: _trips.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      // NEW: Tap to open detailed map
                      onTap: () => _openTripDetails(_trips[i]),
                      child: _TripCard(
                        trip: _trips[i],
                        onDelete: () => _confirmDelete(_trips[i]),
                        settings: _settings,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TRIP HISTORY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _loading
                ? 'Loading recordings…'
                : '${_trips.length} Cloud recording${_trips.length == 1 ? '' : 's'} available',
            style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLifetimeSummary() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF222225)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _LifetimeStat(
            label: 'TOTAL ${_settings.distanceUnit.toUpperCase()}',
            value: _settings.toDisplayDistance(_totalMiles).toStringAsFixed(1),
          ),
          const _VertDivider(),
          _LifetimeStat(
            label: 'TOP ${_settings.speedUnit.toUpperCase()}',
            value: _settings
                .toDisplaySpeed(_allTimeTopSpeedMph)
                .toInt()
                .toString(),
          ),
          const _VertDivider(),
          _LifetimeStat(
            label: 'TOTAL TIME',
            value: _totalMinutes >= 60
                ? '${(_totalMinutes / 60).toStringAsFixed(1)}h'
                : '${_totalMinutes}m',
          ),
        ],
      ),
    );
  }
}

/// ─── HELPER COMPONENTS ──────────────────────────────────────────────────────

class _LifetimeStat extends StatelessWidget {
  final String label, value;
  const _LifetimeStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF32D74B), // Premium Green
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  final SavedTrip trip;
  final SettingsService settings;
  final Future<bool> Function() onDelete;

  const _TripCard(
      {required this.trip, required this.onDelete, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(trip.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 25),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(CupertinoIcons.delete,
            color: Color(0xFFFF3B30), size: 22),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF222225)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _buildIcon(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trip.formattedDate,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(trip.formattedDuration,
                          style: const TextStyle(
                              color: Color(0xFF777777), fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${settings.toDisplayDistance(trip.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        Text('VIEW MAP',
                            style: TextStyle(
                                color: Color(0xFFD4A843),
                                fontSize: 9,
                                fontWeight: FontWeight.w900)),
                        SizedBox(width: 4),
                        Icon(CupertinoIcons.chevron_right,
                            color: Color(0xFFD4A843), size: 10),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const Divider(color: Color(0xFF222225), height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MiniStat(
                    label: 'MAX SPEED',
                    value:
                        '${settings.toDisplaySpeed(trip.maxSpeedMph).toInt()} ${settings.speedUnit}'),
                _MiniStat(
                    label: 'AVG SPEED',
                    value:
                        '${settings.toDisplaySpeed(trip.avgSpeedMph).toInt()} ${settings.speedUnit}'),
                _MiniStat(
                    label: 'ALT GAIN',
                    value:
                        '+${(trip.altitudeGainFt * (settings.useKmh ? 0.3048 : 1.0)).toInt()} ${settings.useKmh ? 'm' : 'ft'}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF32D74B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(CupertinoIcons.map_pin_ellipse,
          color: Color(0xFF32D74B), size: 18),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  const _VertDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: const Color(0xFF222225));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Center(
        child: Column(
          children: [
            Icon(CupertinoIcons.cloud_moon_fill,
                color: Colors.white.withValues(alpha: 0.05), size: 64),
            const SizedBox(height: 20),
            const Text('No History Found',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Saved trips will appear here.',
                style: TextStyle(color: Color(0xFF555555), fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// ─── NEW SCREEN: TRIP MAP DETAIL ────────────────────────────────────────────
/// Opens when a user taps a history card. Renders the saved path polyline.
class TripDetailScreen extends StatelessWidget {
  final SavedTrip trip;
  final SettingsService settings;

  const TripDetailScreen(
      {super.key, required this.trip, required this.settings});

  @override
  Widget build(BuildContext context) {
    // Convert SavedRoutePoints back to LatLng list for FlutterMap
    final List<LatLng> latLngPoints =
        trip.route.map((p) => LatLng(p.lat, p.lng)).toList();

    // Bounds calculation to auto-frame the whole route
    fm.LatLngBounds? bounds;
    if (latLngPoints.isNotEmpty) {
      bounds = fm.LatLngBounds.fromPoints(latLngPoints);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Stack(
          children: [
            // MAP LAYER
            Positioned.fill(
              child: latLngPoints.isEmpty
                  ? const Center(
                      child: Text("No route data saved.",
                          style: TextStyle(color: Colors.white54)))
                  : fm.FlutterMap(
                      options: fm.MapOptions(
                        initialCameraFit: bounds != null
                            ? fm.CameraFit.bounds(
                                bounds: bounds,
                                padding: const EdgeInsets.all(50))
                            : null,
                        interactionOptions: const fm.InteractionOptions(
                          flags: fm.InteractiveFlag.all &
                              ~fm.InteractiveFlag.rotate,
                        ),
                      ),
                      children: [
                        // Same high-quality satellite style used in TrackingScreen
                        fm.TileLayer(
                          urlTemplate:
                              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                          userAgentPackageName: 'com.example.app',
                          tileBuilder: (context, tileWidget, tile) {
                            return ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                Colors.black.withValues(alpha: 0.15),
                                BlendMode.darken,
                              ),
                              child: tileWidget,
                            );
                          },
                        ),
                        fm.PolylineLayer(
                          polylines: [
                            fm.Polyline(
                              points: latLngPoints,
                              color: const Color(0xFFD4A843), // Gold Polyline
                              strokeWidth: 4.5,
                              strokeCap: StrokeCap.round,
                              strokeJoin: StrokeJoin.round,
                            ),
                          ],
                        ),
                        // Start and End Markers
                        if (latLngPoints.isNotEmpty)
                          fm.MarkerLayer(
                            markers: [
                              fm.Marker(
                                point: latLngPoints.first,
                                width: 20,
                                height: 20,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.black, width: 3),
                                  ),
                                ),
                              ),
                              fm.Marker(
                                point: latLngPoints.last,
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(
                                        0xFF32D74B), // Green for End Point
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.black, width: 3),
                                  ),
                                ),
                              ),
                            ],
                          )
                      ],
                    ),
            ),

            // TOP NAVIGATION BAR (Glassmorphic)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 20,
                    right: 20,
                    bottom: 15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141416).withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: const Icon(CupertinoIcons.back,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Text(
                      trip.formattedDate
                          .split(' · ')
                          .first, // Just the date portion
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // BOTTOM STATS DOCK
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                    top: 25,
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).padding.bottom > 0
                        ? MediaQuery.of(context).padding.bottom + 10
                        : 30),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border(
                      top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                          width: 1)),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black,
                        blurRadius: 30,
                        offset: Offset(0, -10))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _DetailStat(
                          icon: CupertinoIcons.arrow_swap,
                          label: 'DISTANCE',
                          value:
                              '${settings.toDisplayDistance(trip.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}',
                          color: const Color(0xFF32D74B),
                        ),
                        _DetailStat(
                          icon: CupertinoIcons.stopwatch_fill,
                          label: 'DURATION',
                          value: trip.formattedDuration,
                          color: const Color(0xFFD4A843),
                        ),
                        _DetailStat(
                          icon: CupertinoIcons.speedometer,
                          label: 'TOP SPEED',
                          value:
                              '${settings.toDisplaySpeed(trip.maxSpeedMph).toInt()} ${settings.speedUnit}',
                          color: const Color(0xFFFF3B30),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0),
        ),
      ],
    );
  }
}
