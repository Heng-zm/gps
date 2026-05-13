import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/settings_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY SCREEN — Optimized Premium Dark UI
// Bug fixes + performance improvements + safer parsing + route map detail
// ═══════════════════════════════════════════════════════════════════════════════

// ── Palette ──────────────────────────────────────────────────────────────────
const Color _kBg = Color(0xFF000000);
const Color _kSurface = Color(0xFF141416);
const Color _kSurfaceSoft = Color(0xFF1A1A1D);
const Color _kBorder = Color(0xFF242428);
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD54F);
const Color _kGreen = Color(0xFF32D74B);
const Color _kRed = Color(0xFFFF3B30);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kTextMuted = Color(0xFF777777);

const Duration _kFastAnim = Duration(milliseconds: 160);
const Duration _kMedAnim = Duration(milliseconds: 260);

const LatLng _kFallbackCenter = LatLng(11.5564, 104.9282);
const double _kFallbackZoom = 13.0;

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL: SAVED ROUTE POINT
// ═══════════════════════════════════════════════════════════════════════════════

class SavedRoutePoint {
  final double lat;
  final double lng;
  final double speedMph;

  const SavedRoutePoint({
    required this.lat,
    required this.lng,
    required this.speedMph,
  });

  bool get isValid {
    return lat.isFinite &&
        lng.isFinite &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lng >= -180.0 &&
        lng <= 180.0;
  }

  LatLng get latLng => LatLng(lat, lng);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'lat': lat,
      'lng': lng,
      'spd': speedMph,
    };
  }

  factory SavedRoutePoint.fromJson(Map<String, dynamic> json) {
    final double parsedLat = _numToDouble(json['lat']);
    final double parsedLng = _numToDouble(json['lng']);
    final double parsedSpeed = _numToDouble(json['spd']);

    return SavedRoutePoint(
      lat: parsedLat,
      lng: parsedLng,
      speedMph: parsedSpeed.isFinite && parsedSpeed >= 0.0 ? parsedSpeed : 0.0,
    );
  }

  static double _numToDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODEL: SAVED TRIP
// ═══════════════════════════════════════════════════════════════════════════════

class SavedTrip {
  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;
  final List<SavedRoutePoint> route;

  late final String formattedDate =
      DateFormat('MMM d, yyyy · h:mm a').format(date);

  late final String formattedDateShort = DateFormat('MMM d, yyyy').format(date);

  late final String formattedDuration = _calculateFormattedDuration();

  SavedTrip({
    required this.id,
    required this.date,
    required this.distanceMiles,
    required this.maxSpeedMph,
    required this.avgSpeedMph,
    required this.totalTime,
    required this.altitudeGainFt,
    required List<SavedRoutePoint> route,
  }) : route = List<SavedRoutePoint>.unmodifiable(
          route.where((SavedRoutePoint point) => point.isValid),
        );

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'date': date.millisecondsSinceEpoch,
      'distanceMiles': distanceMiles,
      'maxSpeedMph': maxSpeedMph,
      'avgSpeedMph': avgSpeedMph,
      'totalTimeSeconds': totalTime.inSeconds,
      'altitudeGainFt': altitudeGainFt,
      'route_points': route.map((SavedRoutePoint p) => p.toJson()).toList(),
    };
  }

  static SavedTrip? tryFromJson(Map<String, dynamic> json) {
    try {
      final int? rawDate = _readInt(json['date']);
      if (rawDate == null || rawDate <= 0) {
        debugPrint('SavedTrip.tryFromJson: invalid date, skipping row.');
        return null;
      }

      final String id = json['id']?.toString().trim() ?? '';
      if (id.isEmpty) {
        debugPrint('SavedTrip.tryFromJson: missing id, skipping row.');
        return null;
      }

      final List<SavedRoutePoint> parsedRoute =
          _parseRoutePoints(json['route_points']);

      return SavedTrip(
        id: id,
        date: DateTime.fromMillisecondsSinceEpoch(rawDate),
        distanceMiles: _readDouble(json['distanceMiles']),
        maxSpeedMph: _readDouble(json['maxSpeedMph']),
        avgSpeedMph: _readDouble(json['avgSpeedMph']),
        totalTime: Duration(
          seconds: math.max(0, _readInt(json['totalTimeSeconds']) ?? 0),
        ),
        altitudeGainFt: _readDouble(json['altitudeGainFt']),
        route: parsedRoute,
      );
    } catch (error, stackTrace) {
      debugPrint('SavedTrip.tryFromJson failed: $error\n$stackTrace');
      return null;
    }
  }

  static List<SavedRoutePoint> _parseRoutePoints(Object? value) {
    if (value is! List) return const <SavedRoutePoint>[];

    final List<SavedRoutePoint> points = <SavedRoutePoint>[];

    for (final Object? item in value) {
      if (item is Map<String, dynamic>) {
        final SavedRoutePoint point = SavedRoutePoint.fromJson(item);
        if (point.isValid) points.add(point);
      } else if (item is Map) {
        final SavedRoutePoint point = SavedRoutePoint.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (point.isValid) points.add(point);
      }
    }

    return List<SavedRoutePoint>.unmodifiable(points);
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double _readDouble(Object? value) {
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0.0;
    }

    if (value is String) {
      final double? parsed = double.tryParse(value);
      return parsed != null && parsed.isFinite ? parsed : 0.0;
    }

    return 0.0;
  }

  String _calculateFormattedDuration() {
    final int seconds = math.max(0, totalTime.inSeconds);
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }

    if (minutes > 0) {
      return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
    }

    return '${secs}s';
  }

  // ── Supabase CRUD ──────────────────────────────────────────────────────────

  static Future<bool> saveTrip(SavedTrip trip) async {
    try {
      await Supabase.instance.client
          .from('saved_trips')
          .upsert(trip.toJson(), onConflict: 'id');

      return true;
    } catch (error, stackTrace) {
      debugPrint('Supabase saveTrip error: $error\n$stackTrace');
      return false;
    }
  }

  static Future<List<SavedTrip>> loadAllTrips() async {
    try {
      final List<Map<String, dynamic>> rows = await Supabase.instance.client
          .from('saved_trips')
          .select()
          .order('date', ascending: false);

      final List<SavedTrip> trips = <SavedTrip>[];

      for (final Map<String, dynamic> row in rows) {
        final SavedTrip? trip = SavedTrip.tryFromJson(row);
        if (trip != null) trips.add(trip);
      }

      return List<SavedTrip>.unmodifiable(trips);
    } catch (error, stackTrace) {
      debugPrint('Supabase loadAllTrips error: $error\n$stackTrace');
      return const <SavedTrip>[];
    }
  }

  static Future<bool> deleteTrip(String id) async {
    if (id.trim().isEmpty) return false;

    try {
      await Supabase.instance.client.from('saved_trips').delete().eq('id', id);
      return true;
    } catch (error, stackTrace) {
      debugPrint('Supabase deleteTrip error: $error\n$stackTrace');
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN: HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SettingsService _settings = SettingsService.instance;

  List<SavedTrip> _trips = const <SavedTrip>[];
  bool _loading = true;
  bool _refreshing = false;

  double _totalMiles = 0.0;
  double _allTimeTopSpeedMph = 0.0;
  int _totalMinutes = 0;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    unawaited(_loadTrips());
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _calculateLifetimeStats() {
    double totalMiles = 0.0;
    double topSpeed = 0.0;
    int totalMinutes = 0;

    for (final SavedTrip trip in _trips) {
      totalMiles += trip.distanceMiles.isFinite ? trip.distanceMiles : 0.0;

      if (trip.maxSpeedMph.isFinite && trip.maxSpeedMph > topSpeed) {
        topSpeed = trip.maxSpeedMph;
      }

      totalMinutes += math.max(0, trip.totalTime.inMinutes);
    }

    _totalMiles = totalMiles;
    _allTimeTopSpeedMph = topSpeed;
    _totalMinutes = totalMinutes;
  }

  Future<void> _loadTrips() async {
    if (!mounted || _refreshing) return;

    setState(() {
      _loading = _trips.isEmpty;
      _refreshing = true;
    });

    final List<SavedTrip> results = await SavedTrip.loadAllTrips();

    if (!mounted) return;

    setState(() {
      _trips = results;
      _calculateLifetimeStats();
      _loading = false;
      _refreshing = false;
    });
  }

  Future<void> _executeDelete(SavedTrip trip) async {
    HapticFeedback.mediumImpact();

    final int originalIndex =
        _trips.indexWhere((SavedTrip t) => t.id == trip.id);
    if (originalIndex < 0) return;

    setState(() {
      final List<SavedTrip> next = List<SavedTrip>.from(_trips);
      next.removeAt(originalIndex);
      _trips = List<SavedTrip>.unmodifiable(next);
      _calculateLifetimeStats();
    });

    final bool success = await SavedTrip.deleteTrip(trip.id);

    if (!success && mounted) {
      setState(() {
        final List<SavedTrip> rollback = List<SavedTrip>.from(_trips);
        final int safeIndex = originalIndex < 0
            ? 0
            : originalIndex > rollback.length
                ? rollback.length
                : originalIndex;
        rollback.insert(safeIndex, trip);
        _trips = List<SavedTrip>.unmodifiable(rollback);
        _calculateLifetimeStats();
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to delete. Connection error.'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
  }

  Future<bool> _confirmDelete(SavedTrip trip) async {
    final bool? result = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Delete Trip'),
          content: const Text(
            'Permanently remove this recording from the cloud?',
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _executeDelete(trip);
    }

    return false;
  }

  void _openTripDetails(SavedTrip trip) {
    HapticFeedback.lightImpact();

    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => TripDetailScreen(
          trip: trip,
          settings: _settings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showSummary = !_loading && _trips.isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: _kBg,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: _HistoryBackground()),
            SafeArea(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: <Widget>[
                  CupertinoSliverRefreshControl(onRefresh: _loadTrips),
                  SliverToBoxAdapter(
                    child: _HistoryHeader(
                      loading: _loading,
                      refreshing: _refreshing,
                      tripCount: _trips.length,
                    ),
                  ),
                  if (showSummary)
                    SliverToBoxAdapter(
                      child: _LifetimeSummary(
                        settings: _settings,
                        totalMiles: _totalMiles,
                        allTimeTopSpeedMph: _allTimeTopSpeedMph,
                        totalMinutes: _totalMinutes,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  if (_loading)
                    const SliverToBoxAdapter(child: _LoadingState())
                  else if (_trips.isEmpty)
                    const SliverToBoxAdapter(child: _EmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      sliver: SliverList.builder(
                        itemCount: _trips.length,
                        itemBuilder: (BuildContext context, int index) {
                          final SavedTrip trip = _trips[index];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _Pressable(
                              onTap: () => _openTripDetails(trip),
                              child: _TripCard(
                                trip: trip,
                                settings: _settings,
                                onDelete: () => _confirmDelete(trip),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY HEADER / SUMMARY
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryBackground extends StatelessWidget {
  const _HistoryBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.5, -0.8),
          radius: 1.1,
          colors: <Color>[
            _kGold.withValues(alpha: 0.13),
            const Color(0xFF070707),
            _kBg,
          ],
          stops: const <double>[0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.loading,
    required this.refreshing,
    required this.tripCount,
  });

  final bool loading;
  final bool refreshing;
  final int tripCount;

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    if (loading) {
      subtitle = 'Loading recordings…';
    } else if (refreshing) {
      subtitle = 'Refreshing cloud recordings…';
    } else {
      subtitle =
          '$tripCount cloud recording${tripCount == 1 ? '' : 's'} available';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SafeText(
            'TRIP HISTORY',
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 5),
          _SafeText(
            subtitle,
            maxLines: 1,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LifetimeSummary extends StatelessWidget {
  const _LifetimeSummary({
    required this.settings,
    required this.totalMiles,
    required this.allTimeTopSpeedMph,
    required this.totalMinutes,
  });

  final SettingsService settings;
  final double totalMiles;
  final double allTimeTopSpeedMph;
  final int totalMinutes;

  @override
  Widget build(BuildContext context) {
    final String totalDistance =
        settings.toDisplayDistance(totalMiles).toStringAsFixed(1);
    final String topSpeed =
        settings.toDisplaySpeed(allTimeTopSpeedMph).round().toString();
    final String totalTime = totalMinutes >= 60
        ? '${(totalMinutes / 60).toStringAsFixed(1)}h'
        : '${totalMinutes}m';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
      decoration: BoxDecoration(
        color: _kSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _LifetimeStat(
              label: 'TOTAL ${settings.distanceUnit.toUpperCase()}',
              value: totalDistance,
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _LifetimeStat(
              label: 'TOP ${settings.speedUnit.toUpperCase()}',
              value: topSpeed,
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _LifetimeStat(
              label: 'TOTAL TIME',
              value: totalTime,
            ),
          ),
        ],
      ),
    );
  }
}

class _LifetimeStat extends StatelessWidget {
  const _LifetimeStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _SafeText(
          value,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w900,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _SafeText(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _kGreen,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRIP CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.settings,
    required this.onDelete,
  });

  final SavedTrip trip;
  final SettingsService settings;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<String>(trip.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 25),
        decoration: BoxDecoration(
          color: _kRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _kRed.withValues(alpha: 0.18),
          ),
        ),
        child: const Icon(
          CupertinoIcons.delete,
          color: _kRed,
          size: 22,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _kBorder),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                _TripIcon(hasRoute: trip.route.length >= 2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SafeText(
                        trip.formattedDate,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _SafeText(
                        trip.route.length >= 2
                            ? '${trip.formattedDuration} · ${trip.route.length} points'
                            : '${trip.formattedDuration} · no route',
                        maxLines: 1,
                        style: const TextStyle(
                          color: _kTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    _SafeText(
                      '${settings.toDisplayDistance(trip.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        fontFeatures: <ui.FontFeature>[
                          ui.FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _SafeText(
                          'VIEW MAP',
                          maxLines: 1,
                          style: TextStyle(
                            color: _kGold,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_right,
                          color: _kGold,
                          size: 10,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const Divider(color: _kBorder, height: 32),
            Row(
              children: <Widget>[
                Expanded(
                  child: _MiniStat(
                    label: 'MAX SPEED',
                    value:
                        '${settings.toDisplaySpeed(trip.maxSpeedMph).round()} ${settings.speedUnit}',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'AVG SPEED',
                    value:
                        '${settings.toDisplaySpeed(trip.avgSpeedMph).round()} ${settings.speedUnit}',
                  ),
                ),
                Expanded(
                  child: _MiniStat(
                    label: 'ALT GAIN',
                    value:
                        '+${_displayAltitudeGain(trip.altitudeGainFt, settings)}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _displayAltitudeGain(double feet, SettingsService settings) {
    final double safeFeet = feet.isFinite ? feet : 0.0;

    if (settings.useKmh) {
      return '${(safeFeet * 0.3048).round()} m';
    }

    return '${safeFeet.round()} ft';
  }
}

class _TripIcon extends StatelessWidget {
  const _TripIcon({
    required this.hasRoute,
  });

  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    final Color color = hasRoute ? _kGreen : _kTextMuted;
    final IconData icon =
        hasRoute ? CupertinoIcons.map_pin_ellipse : CupertinoIcons.map;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.16),
        ),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SafeText(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Color(0xFF666666),
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        _SafeText(
          value,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: _kBorder,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOADING / EMPTY
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: CupertinoActivityIndicator(
          radius: 12,
          color: _kGoldSoft,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 100, left: 24, right: 24),
      child: Center(
        child: Column(
          children: <Widget>[
            Icon(
              CupertinoIcons.cloud_moon_fill,
              color: Colors.white.withValues(alpha: 0.06),
              size: 66,
            ),
            const SizedBox(height: 20),
            const _SafeText(
              'No History Found',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            const _SafeText(
              'Saved trips will appear here.',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF555555),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN: TRIP DETAIL MAP
// ═══════════════════════════════════════════════════════════════════════════════

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({
    super.key,
    required this.trip,
    required this.settings,
  });

  final SavedTrip trip;
  final SettingsService settings;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  static const Duration _replayFrame = Duration(milliseconds: 33);
  static const double _segmentSecondsAt1x = 0.55;

  late final List<SavedRoutePoint> _route;
  late final List<LatLng> _points;
  late final fm.MapController _mapController;

  Timer? _replayTimer;
  DateTime? _lastReplayTick;
  DateTime? _lastCameraFollow;

  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  int _replayIndex = 0;
  double _segmentProgress = 0.0;

  LatLng? _replayPosition;
  double _replaySpeedMph = 0.0;

  bool get _hasRoute => _points.length >= 2;

  double get _routeProgress {
    if (!_hasRoute) return 0.0;
    final int segmentCount = math.max(1, _points.length - 1);
    return ((_replayIndex + _segmentProgress) / segmentCount).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();

    _mapController = fm.MapController();

    _route = widget.trip.route
        .where((SavedRoutePoint point) => point.isValid)
        .toList(growable: false);

    _points = _route
        .map((SavedRoutePoint point) => point.latLng)
        .toList(growable: false);

    if (_hasRoute) {
      _replayPosition = _points.first;
      _replaySpeedMph = _route.first.speedMph;
    }
  }

  @override
  void dispose() {
    _stopReplayTimer();
    _mapController.dispose();
    super.dispose();
  }

  fm.MapOptions _mapOptions() {
    if (_hasRoute) {
      return fm.MapOptions(
        initialCameraFit: fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(_points),
          padding: const EdgeInsets.fromLTRB(46, 120, 46, 260),
        ),
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
        ),
      );
    }

    return const fm.MapOptions(
      initialCenter: _kFallbackCenter,
      initialZoom: _kFallbackZoom,
      interactionOptions: fm.InteractionOptions(
        flags: fm.InteractiveFlag.all & ~fm.InteractiveFlag.rotate,
      ),
    );
  }

  void _toggleReplay() {
    HapticFeedback.selectionClick();

    if (!_hasRoute) return;

    if (_isPlaying) {
      _pauseReplay();
    } else {
      _startReplay();
    }
  }

  void _startReplay() {
    if (!_hasRoute) return;

    if (_replayIndex >= _points.length - 1 && _segmentProgress >= 1.0) {
      _resetReplay();
    }

    _lastReplayTick = DateTime.now();

    setState(() {
      _isPlaying = true;
    });

    _replayTimer ??= Timer.periodic(_replayFrame, (_) => _onReplayTick());
  }

  void _pauseReplay() {
    _stopReplayTimer();

    if (!mounted) return;

    setState(() {
      _isPlaying = false;
    });
  }

  void _resetReplay() {
    _stopReplayTimer();

    if (!mounted) return;

    setState(() {
      _isPlaying = false;
      _replayIndex = 0;
      _segmentProgress = 0.0;
      _replayPosition = _hasRoute ? _points.first : null;
      _replaySpeedMph = _route.isNotEmpty ? _route.first.speedMph : 0.0;
    });

    _followReplayMarker(force: true);
  }

  void _stopReplayTimer() {
    _replayTimer?.cancel();
    _replayTimer = null;
    _lastReplayTick = null;
  }

  void _onReplayTick() {
    if (!mounted || !_hasRoute) return;

    final DateTime now = DateTime.now();
    final DateTime previous = _lastReplayTick ?? now;
    _lastReplayTick = now;

    final double elapsedSeconds =
        now.difference(previous).inMilliseconds.clamp(0, 120) / 1000.0;

    final double delta = elapsedSeconds * _playbackSpeed / _segmentSecondsAt1x;

    _advanceReplay(delta);
  }

  void _advanceReplay(double delta) {
    if (!_hasRoute) return;

    int nextIndex = _replayIndex;
    double nextProgress = _segmentProgress + delta;

    while (nextProgress >= 1.0 && nextIndex < _points.length - 2) {
      nextProgress -= 1.0;
      nextIndex++;
    }

    if (nextIndex >= _points.length - 2 && nextProgress >= 1.0) {
      nextIndex = _points.length - 2;
      nextProgress = 1.0;
    }

    final LatLng nextPosition = _interpolateLatLng(
      _points[nextIndex],
      _points[nextIndex + 1],
      nextProgress,
    );

    final double currentSpeed = _interpolateDouble(
      _route[nextIndex].speedMph,
      _route[nextIndex + 1].speedMph,
      nextProgress,
    );

    final bool completed =
        nextIndex == _points.length - 2 && nextProgress >= 1.0;

    setState(() {
      _replayIndex = nextIndex;
      _segmentProgress = nextProgress;
      _replayPosition = nextPosition;
      _replaySpeedMph =
          currentSpeed.isFinite && currentSpeed >= 0.0 ? currentSpeed : 0.0;
      _isPlaying = !completed;
    });

    _followReplayMarker();

    if (completed) {
      _stopReplayTimer();
      HapticFeedback.lightImpact();
    }
  }

  void _seekReplay(double progress) {
    if (!_hasRoute) return;

    final double safeProgress = progress.clamp(0.0, 1.0);
    final double scaled = safeProgress * (_points.length - 1);
    final int rawIndex = scaled.floor();
    final int index = rawIndex < 0
        ? 0
        : rawIndex > _points.length - 2
            ? _points.length - 2
            : rawIndex;
    final double segmentProgress = (scaled - index).clamp(0.0, 1.0);

    final LatLng position = _interpolateLatLng(
      _points[index],
      _points[index + 1],
      segmentProgress,
    );

    final double speed = _interpolateDouble(
      _route[index].speedMph,
      _route[index + 1].speedMph,
      segmentProgress,
    );

    setState(() {
      _replayIndex = index;
      _segmentProgress = segmentProgress;
      _replayPosition = position;
      _replaySpeedMph = speed.isFinite && speed >= 0.0 ? speed : 0.0;
    });

    _followReplayMarker(force: true);
  }

  void _setPlaybackSpeed(double speed) {
    if (_playbackSpeed == speed) return;

    HapticFeedback.selectionClick();

    setState(() {
      _playbackSpeed = speed;
    });
  }

  void _followReplayMarker({bool force = false}) {
    final LatLng? position = _replayPosition;
    if (position == null) return;

    final DateTime now = DateTime.now();
    if (!force &&
        _lastCameraFollow != null &&
        now.difference(_lastCameraFollow!) <
            const Duration(milliseconds: 180)) {
      return;
    }

    _lastCameraFollow = now;

    try {
      final double zoom = _mapController.camera.zoom.isFinite
          ? _mapController.camera.zoom
          : _kFallbackZoom;
      _mapController.move(position, zoom);
    } catch (_) {
      // Map may not be ready yet.
    }
  }

  static LatLng _interpolateLatLng(LatLng a, LatLng b, double t) {
    final double safeT = t.clamp(0.0, 1.0);

    return LatLng(
      _interpolateDouble(a.latitude, b.latitude, safeT),
      _interpolateDouble(a.longitude, b.longitude, safeT),
    );
  }

  static double _interpolateDouble(double a, double b, double t) {
    return a + (b - a) * t.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _hasRoute ? _buildMap() : const _NoRouteMapState(),
            ),
            _TripDetailTopBar(trip: widget.trip),
            _TripReplayBottomDock(
              trip: widget.trip,
              settings: widget.settings,
              hasRoute: _hasRoute,
              isPlaying: _isPlaying,
              playbackSpeed: _playbackSpeed,
              progress: _routeProgress,
              replaySpeedMph: _replaySpeedMph,
              replayPointLabel: _hasRoute
                  ? '${(_replayIndex + 1).clamp(1, _points.length)} / ${_points.length}'
                  : '--',
              onTogglePlay: _toggleReplay,
              onReset: _resetReplay,
              onSeek: _seekReplay,
              onSpeedChanged: _setPlaybackSpeed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return RepaintBoundary(
      child: fm.FlutterMap(
        mapController: _mapController,
        options: _mapOptions(),
        children: <Widget>[
          fm.TileLayer(
            urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
                'World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.trackpro.ai',
            tileBuilder: _darkTileBuilder,
          ),
          fm.PolylineLayer(
            polylines: <fm.Polyline>[
              fm.Polyline(
                points: _points,
                color: _kGold.withValues(alpha: 0.30),
                strokeWidth: 9.0,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              fm.Polyline(
                points: _points,
                color: _kGoldSoft,
                strokeWidth: 4.5,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
          fm.MarkerLayer(
            markers: <fm.Marker>[
              fm.Marker(
                point: _points.first,
                width: 28,
                height: 28,
                child: const _RouteMarker(
                  color: Colors.white,
                  icon: CupertinoIcons.play_fill,
                ),
              ),
              fm.Marker(
                point: _points.last,
                width: 32,
                height: 32,
                child: const _RouteMarker(
                  color: _kGreen,
                  icon: CupertinoIcons.flag_fill,
                ),
              ),
              if (_replayPosition != null)
                fm.Marker(
                  point: _replayPosition!,
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  child: _ReplayMarker(
                    speedMph: _replaySpeedMph,
                    settings: widget.settings,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    fm.TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.15),
        BlendMode.darken,
      ),
      child: tileWidget,
    );
  }
}

class _NoRouteMapState extends StatelessWidget {
  const _NoRouteMapState();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: _kBg),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _kBorder),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                CupertinoIcons.map,
                color: Colors.white30,
                size: 48,
              ),
              SizedBox(height: 16),
              _SafeText(
                'No route data saved',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              _SafeText(
                'This trip has stats, but no GPS path points.',
                maxLines: 2,
                textAlign: TextAlign.center,
                softWrap: true,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripDetailTopBar extends StatelessWidget {
  const _TripDetailTopBar({
    required this.trip,
  });

  final SavedTrip trip;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.of(context).padding;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: padding.top + 10,
          left: 20,
          right: 20,
          bottom: 18,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.86),
              Colors.black.withValues(alpha: 0.44),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: <Widget>[
            _RoundBackButton(onTap: () => Navigator.pop(context)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SafeText(
                    trip.formattedDateShort,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black, blurRadius: 10),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  _SafeText(
                    '${trip.route.length} route points',
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundBackButton extends StatelessWidget {
  const _RoundBackButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.84),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: const Icon(
              CupertinoIcons.back,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _TripReplayBottomDock extends StatelessWidget {
  const _TripReplayBottomDock({
    required this.trip,
    required this.settings,
    required this.hasRoute,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.progress,
    required this.replaySpeedMph,
    required this.replayPointLabel,
    required this.onTogglePlay,
    required this.onReset,
    required this.onSeek,
    required this.onSpeedChanged,
  });

  final SavedTrip trip;
  final SettingsService settings;
  final bool hasRoute;
  final bool isPlaying;
  final double playbackSpeed;
  final double progress;
  final double replaySpeedMph;
  final String replayPointLabel;
  final VoidCallback onTogglePlay;
  final VoidCallback onReset;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeedChanged;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.of(context).padding;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: padding.bottom > 0 ? padding.bottom + 10 : 28,
            ),
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Colors.black,
                  blurRadius: 30,
                  offset: Offset(0, -10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _DetailStat(
                        icon: CupertinoIcons.arrow_swap,
                        label: 'DISTANCE',
                        value:
                            '${settings.toDisplayDistance(trip.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}',
                        color: _kGreen,
                      ),
                    ),
                    Expanded(
                      child: _DetailStat(
                        icon: CupertinoIcons.stopwatch_fill,
                        label: 'DURATION',
                        value: trip.formattedDuration,
                        color: _kGold,
                      ),
                    ),
                    Expanded(
                      child: _DetailStat(
                        icon: CupertinoIcons.speedometer,
                        label: 'REPLAY SPEED',
                        value: hasRoute
                            ? '${settings.toDisplaySpeed(replaySpeedMph).round()} ${settings.speedUnit}'
                            : '--',
                        color: _kRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ReplayControlPanel(
                  enabled: hasRoute,
                  isPlaying: isPlaying,
                  playbackSpeed: playbackSpeed,
                  progress: progress,
                  pointLabel: replayPointLabel,
                  onTogglePlay: onTogglePlay,
                  onReset: onReset,
                  onSeek: onSeek,
                  onSpeedChanged: onSpeedChanged,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayControlPanel extends StatelessWidget {
  const _ReplayControlPanel({
    required this.enabled,
    required this.isPlaying,
    required this.playbackSpeed,
    required this.progress,
    required this.pointLabel,
    required this.onTogglePlay,
    required this.onReset,
    required this.onSeek,
    required this.onSpeedChanged,
  });

  final bool enabled;
  final bool isPlaying;
  final double playbackSpeed;
  final double progress;
  final String pointLabel;
  final VoidCallback onTogglePlay;
  final VoidCallback onReset;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeedChanged;

  @override
  Widget build(BuildContext context) {
    final Color activeColor = enabled ? _kGoldSoft : Colors.white24;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.075),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _CircularReplayButton(
                enabled: enabled,
                icon: isPlaying
                    ? CupertinoIcons.pause_fill
                    : CupertinoIcons.play_fill,
                color: isPlaying ? _kRed : _kGreen,
                onTap: onTogglePlay,
              ),
              const SizedBox(width: 10),
              _CircularReplayButton(
                enabled: enabled,
                icon: CupertinoIcons.restart,
                color: _kGold,
                onTap: onReset,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SafeText(
                      enabled ? 'TRIP REPLAY' : 'REPLAY UNAVAILABLE',
                      maxLines: 1,
                      style: TextStyle(
                        color: enabled ? Colors.white : Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _SafeText(
                      enabled ? 'Point $pointLabel' : 'No saved GPS route.',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _SafeText(
                '${(progress * 100).round()}%',
                maxLines: 1,
                style: TextStyle(
                  color: activeColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const <ui.FontFeature>[
                    ui.FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          IgnorePointer(
            ignoring: !enabled,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.35,
              child: CupertinoSlider(
                min: 0.0,
                max: 1.0,
                value: progress.clamp(0.0, 1.0),
                activeColor: _kGoldSoft,
                thumbColor: Colors.white,
                onChanged: onSeek,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _SpeedChip(
                enabled: enabled,
                label: '1x',
                selected: playbackSpeed == 1.0,
                onTap: () => onSpeedChanged(1.0),
              ),
              const SizedBox(width: 8),
              _SpeedChip(
                enabled: enabled,
                label: '2x',
                selected: playbackSpeed == 2.0,
                onTap: () => onSpeedChanged(2.0),
              ),
              const SizedBox(width: 8),
              _SpeedChip(
                enabled: enabled,
                label: '4x',
                selected: playbackSpeed == 4.0,
                onTap: () => onSpeedChanged(4.0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircularReplayButton extends StatelessWidget {
  const _CircularReplayButton({
    required this.enabled,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: enabled ? onTap : () {},
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.28),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 14,
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.enabled,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? _kGoldSoft : Colors.white54;

    return _Pressable(
      onTap: enabled ? onTap : () {},
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: AnimatedContainer(
          duration: _kMedAnim,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? _kGold.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? _kGoldSoft.withValues(alpha: 0.34)
                  : Colors.white.withValues(alpha: 0.075),
            ),
          ),
          child: _SafeText(
            label,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        _SafeText(
          value,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
        const SizedBox(height: 3),
        _SafeText(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 14,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: color == Colors.white ? Colors.black : Colors.white,
        size: 12,
      ),
    );
  }
}

class _ReplayMarker extends StatefulWidget {
  const _ReplayMarker({
    required this.speedMph,
    required this.settings,
  });

  final double speedMph;
  final SettingsService settings;

  @override
  State<_ReplayMarker> createState() => _ReplayMarkerState();
}

class _ReplayMarkerState extends State<_ReplayMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int speed = widget.settings.toDisplaySpeed(widget.speedMph).round();

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Opacity(
              opacity: (1.0 - _pulse.value).clamp(0.0, 1.0),
              child: Container(
                width: 22 + _pulse.value * 32,
                height: 22 + _pulse.value * 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _kGoldSoft.withValues(alpha: 0.65),
                    width: 2,
                  ),
                ),
              ),
            ),
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                color: _kGoldSoft,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 3),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _kGoldSoft.withValues(alpha: 0.45),
                    blurRadius: 18,
                  ),
                  const BoxShadow(
                    color: Colors.black54,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: _SafeText(
                  speed.toString(),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    fontFeatures: <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

class _SafeText extends StatelessWidget {
  const _SafeText(
    this.data, {
    required this.style,
    this.maxLines,
    this.textAlign,
    this.softWrap = false,
  });

  final String data;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        data,
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        softWrap: softWrap,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: _kFastAnim,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.88 : 1.0,
          duration: _kFastAnim,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
