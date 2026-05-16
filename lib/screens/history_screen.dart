// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/mapbox_config.dart';
import '../models/location_puck_style.dart';
import '../models/mapbox_styles.dart';
import '../services/settings_service.dart';
import '../widgets/location_puck_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY SCREEN — Premium glass timeline + cinematic trip replay
// Analyzer-safe UI refresh version.
// ═══════════════════════════════════════════════════════════════════════════════

const Color _kBg = Color(0xFF000000);
const Color _kSurface = Color(0xFF111114);
const Color _kSurface2 = Color(0xFF17171B);
const Color _kBorder = Color(0xFF29292E);
const Color _kGold = Color(0xFFD4A843);
const Color _kGoldSoft = Color(0xFFFFD54F);
const Color _kGreen = Color(0xFF32D74B);
const Color _kRed = Color(0xFFFF3B30);
const Color _kBlue = Color(0xFF4A9EFF);
const Color _kCyan = Color(0xFF22D3EE);
const Color _kPurple = Color(0xFF8B5CF6);
const Color _kMuted = Color(0xFF777777);

const LatLng _kFallbackCenter = LatLng(11.5564, 104.9282);
const double _kFallbackZoom = 13.0;
const Duration _kReplayFrame = Duration(milliseconds: 33);

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class SavedRoutePoint {
  const SavedRoutePoint({
    required this.lat,
    required this.lng,
    required this.speedMph,
  });

  final double lat;
  final double lng;
  final double speedMph;

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
    final double parsedLat = _readDouble(
      json['lat'] ?? json['latitude'] ?? json['y'],
    );
    final double parsedLng = _readDouble(
      json['lng'] ?? json['lon'] ?? json['longitude'] ?? json['x'],
    );
    final double parsedSpeed = _readDouble(
      json['spd'] ?? json['speedMph'] ?? json['speed'] ?? json['speed_mph'],
    );

    return SavedRoutePoint(
      lat: parsedLat,
      lng: parsedLng,
      speedMph: parsedSpeed.isFinite && parsedSpeed > 0.0 ? parsedSpeed : 0.0,
    );
  }

  static double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
  }
}

class SavedTrip {
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

  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;
  final List<SavedRoutePoint> route;

  late final String formattedDate = DateFormat('MMM d, yyyy · h:mm a').format(date);
  late final String formattedDateShort = DateFormat('MMM d, yyyy').format(date);
  late final String formattedDuration = _formatDuration(totalTime);

  bool get hasRoute => route.length >= 2;

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
      final String id = (json['id'] ?? '').toString().trim();
      if (id.isEmpty) return null;

      final int? rawDate = _readInt(json['date'] ?? json['created_at_ms']);
      final DateTime date = rawDate != null && rawDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(rawDate)
          : _readDateTime(json['created_at'] ?? json['inserted_at']) ?? DateTime.now();

      return SavedTrip(
        id: id,
        date: date,
        distanceMiles: _readDouble(
          json['distanceMiles'] ?? json['distance_miles'] ?? json['distance'],
        ),
        maxSpeedMph: _readDouble(
          json['maxSpeedMph'] ?? json['max_speed_mph'] ?? json['maxSpeed'],
        ),
        avgSpeedMph: _readDouble(
          json['avgSpeedMph'] ?? json['avg_speed_mph'] ?? json['avgSpeed'],
        ),
        totalTime: Duration(
          seconds: math.max(
            0,
            _readInt(
                  json['totalTimeSeconds'] ??
                      json['total_time_seconds'] ??
                      json['durationSeconds'],
                ) ??
                0,
          ),
        ),
        altitudeGainFt: _readDouble(
          json['altitudeGainFt'] ?? json['altitude_gain_ft'] ?? json['altitudeGain'],
        ),
        route: _parseRoute(json['route_points'] ?? json['route'] ?? json['points']),
      );
    } catch (error, stackTrace) {
      debugPrint('SavedTrip.tryFromJson failed: $error\n$stackTrace');
      return null;
    }
  }

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
      final dynamic data = await Supabase.instance.client
          .from('saved_trips')
          .select()
          .order('date', ascending: false);

      if (data is! List) return const <SavedTrip>[];

      final List<SavedTrip> trips = <SavedTrip>[];
      for (final Object? row in data) {
        if (row is Map<String, dynamic>) {
          final SavedTrip? trip = SavedTrip.tryFromJson(row);
          if (trip != null) trips.add(trip);
        } else if (row is Map) {
          final SavedTrip? trip = SavedTrip.tryFromJson(Map<String, dynamic>.from(row));
          if (trip != null) trips.add(trip);
        }
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

  static List<SavedRoutePoint> _parseRoute(Object? value) {
    if (value is! List) return const <SavedRoutePoint>[];

    final List<SavedRoutePoint> points = <SavedRoutePoint>[];
    for (final Object? item in value) {
      SavedRoutePoint? point;

      if (item is Map<String, dynamic>) {
        point = SavedRoutePoint.fromJson(item);
      } else if (item is Map) {
        point = SavedRoutePoint.fromJson(Map<String, dynamic>.from(item));
      }

      if (point != null && point.isValid) {
        if (points.isEmpty ||
            points.last.lat != point.lat ||
            points.last.lng != point.lng) {
          points.add(point);
        }
      }
    }

    return List<SavedRoutePoint>.unmodifiable(points);
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double _readDouble(Object? value) {
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : 0.0;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value.trim());
      return parsed != null && parsed.isFinite ? parsed : 0.0;
    }
    return 0.0;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _formatDuration(Duration duration) {
    final int seconds = math.max(0, duration.inSeconds);
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;

    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    if (minutes > 0) return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
    return '${secs}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SettingsService _settings = SettingsService.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  List<SavedTrip> _trips = const <SavedTrip>[];
  bool _loading = true;
  bool _refreshing = false;
  String _query = '';
  _HistoryFilter _filter = _HistoryFilter.all;

  double _totalMiles = 0.0;
  double _allTimeTopSpeedMph = 0.0;
  int _totalMinutes = 0;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _searchCtrl.addListener(_onSearchChanged);
    unawaited(_loadTrips());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    final String next = _searchCtrl.text.trim().toLowerCase();
    if (next == _query) return;
    setState(() => _query = next);
  }

  List<SavedTrip> get _visibleTrips {
    final DateTime now = DateTime.now();

    return _trips.where((SavedTrip trip) {
      final bool matchesFilter = switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.week => now.difference(trip.date).inDays <= 7,
        _HistoryFilter.month => now.difference(trip.date).inDays <= 31,
        _HistoryFilter.longTrips => trip.distanceMiles >= 10.0,
        _HistoryFilter.fastTrips => trip.maxSpeedMph >= 55.0,
      };

      if (!matchesFilter) return false;
      if (_query.isEmpty) return true;

      final String haystack = <String>[
        trip.formattedDate,
        trip.formattedDateShort,
        trip.distanceMiles.toStringAsFixed(1),
        trip.maxSpeedMph.toStringAsFixed(0),
        trip.avgSpeedMph.toStringAsFixed(0),
      ].join(' ').toLowerCase();

      return haystack.contains(_query);
    }).toList(growable: false);
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

    final int originalIndex = _trips.indexWhere((SavedTrip t) => t.id == trip.id);
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
        rollback.insert(originalIndex.clamp(0, rollback.length).toInt(), trip);
        _trips = List<SavedTrip>.unmodifiable(rollback);
        _calculateLifetimeStats();
      });

      _showSnack('Failed to delete. Connection error.', _kRed);
    }
  }

  Future<bool> _confirmDelete(SavedTrip trip) async {
    final bool? result = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Delete Trip'),
          content: const Text('Permanently remove this trip from the cloud?'),
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

    if (result == true) await _executeDelete(trip);
    return false;
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
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
    final List<SavedTrip> visibleTrips = _visibleTrips;
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
                  SliverToBoxAdapter(
                    child: _HistoryToolbar(
                      controller: _searchCtrl,
                      selectedFilter: _filter,
                      onFilterChanged: (_HistoryFilter filter) {
                        HapticFeedback.selectionClick();
                        setState(() => _filter = filter);
                      },
                    ),
                  ),
                  if (_loading)
                    const SliverToBoxAdapter(child: _LoadingState())
                  else if (_trips.isEmpty)
                    const SliverToBoxAdapter(child: _EmptyState())
                  else if (visibleTrips.isEmpty)
                    const SliverToBoxAdapter(child: _NoResultsState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 42),
                      sliver: SliverList.builder(
                        itemCount: visibleTrips.length,
                        itemBuilder: (BuildContext context, int index) {
                          final SavedTrip trip = visibleTrips[index];

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Dismissible(
                              key: ValueKey<String>('trip-${trip.id}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) => _confirmDelete(trip),
                              background: const _DeleteBackground(),
                              child: _Pressable(
                                onTap: () => _openTripDetails(trip),
                                child: _TripCard(
                                  trip: trip,
                                  settings: _settings,
                                  onDelete: () => _confirmDelete(trip),
                                ),
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

enum _HistoryFilter { all, week, month, longTrips, fastTrips }

extension _HistoryFilterX on _HistoryFilter {
  String get label {
    return switch (this) {
      _HistoryFilter.all => 'All',
      _HistoryFilter.week => 'Week',
      _HistoryFilter.month => 'Month',
      _HistoryFilter.longTrips => 'Long',
      _HistoryFilter.fastTrips => 'Fast',
    };
  }

  IconData get icon {
    return switch (this) {
      _HistoryFilter.all => CupertinoIcons.square_grid_2x2_fill,
      _HistoryFilter.week => CupertinoIcons.calendar,
      _HistoryFilter.month => CupertinoIcons.calendar_today,
      _HistoryFilter.longTrips => CupertinoIcons.map_fill,
      _HistoryFilter.fastTrips => CupertinoIcons.speedometer,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY UI
// ═══════════════════════════════════════════════════════════════════════════════

class _HistoryBackground extends StatelessWidget {
  const _HistoryBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFF120F07),
                Color(0xFF050506),
                Color(0xFF000000),
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -90,
          child: _BlurOrb(
            size: 280,
            color: _kGoldSoft.withValues(alpha: 0.18),
          ),
        ),
        Positioned(
          top: 120,
          right: -110,
          child: _BlurOrb(
            size: 260,
            color: _kBlue.withValues(alpha: 0.15),
          ),
        ),
        Positioned(
          bottom: -150,
          left: 30,
          child: _BlurOrb(
            size: 320,
            color: _kPurple.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 46, sigmaY: 46),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: _GlassCard(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    _kGoldSoft.withValues(alpha: 0.95),
                    _kGold.withValues(alpha: 0.72),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _kGoldSoft.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.map_fill,
                color: Color(0xFF15130D),
                size: 25,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SafeText(
                    'Trip Timeline',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _SafeText(
                    loading
                        ? 'Syncing your saved rides…'
                        : '$tripCount saved ${tripCount == 1 ? 'trip' : 'trips'} · swipe left to delete',
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: refreshing
                  ? const CupertinoActivityIndicator(
                      key: ValueKey<String>('history-syncing'),
                      color: _kGoldSoft,
                      radius: 10,
                    )
                  : const _HeaderBadge(key: ValueKey<String>('history-ready')),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: const Icon(
        CupertinoIcons.clock_fill,
        color: _kGoldSoft,
        size: 20,
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
    final double displayDistance = settings.toDisplayDistance(totalMiles);
    final double displayTopSpeed = settings.toDisplaySpeed(allTimeTopSpeedMph);
    final double hours = totalMinutes / 60.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: _GlassCard(
        radius: 30,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: _SafeText(
                    'Lifetime Dashboard',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _kGreen.withValues(alpha: 0.18)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(CupertinoIcons.check_mark_circled_solid, color: _kGreen, size: 13),
                      SizedBox(width: 5),
                      _SafeText(
                        'SYNCED',
                        maxLines: 1,
                        style: TextStyle(
                          color: _kGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      _kGoldSoft,
                      _kCyan.withValues(alpha: 0.92),
                      _kPurple.withValues(alpha: 0.90),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SummaryMetric(
                    label: 'Distance',
                    value: displayDistance.toStringAsFixed(displayDistance >= 100 ? 0 : 1),
                    unit: settings.distanceUnit,
                    icon: CupertinoIcons.map_fill,
                    color: _kGoldSoft,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Top Speed',
                    value: displayTopSpeed.round().toString(),
                    unit: settings.speedUnit,
                    icon: CupertinoIcons.speedometer,
                    color: _kCyan,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Time',
                    value: hours >= 10 ? hours.round().toString() : hours.toStringAsFixed(1),
                    unit: 'hr',
                    icon: CupertinoIcons.timer_fill,
                    color: _kGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 16),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _SafeText(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _SafeText(
                    unit,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          _SafeText(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryToolbar extends StatelessWidget {
  const _HistoryToolbar({
    required this.controller,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _HistoryFilter selectedFilter;
  final ValueChanged<_HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: _GlassCard(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          children: <Widget>[
            CupertinoTextField(
              controller: controller,
              placeholder: 'Search date, distance, speed…',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(CupertinoIcons.search, color: Colors.white38, size: 18),
              ),
              suffix: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, TextEditingValue value, __) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return CupertinoButton(
                    padding: const EdgeInsets.only(right: 8),
                    minSize: 0,
                    onPressed: controller.clear,
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Colors.white38,
                      size: 18,
                    ),
                  );
                },
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              cursorColor: _kGoldSoft,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              placeholderStyle: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w700),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            const SizedBox(height: 11),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _HistoryFilter.values.map((_HistoryFilter filter) {
                  final bool selected = selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: filter.label,
                      icon: filter.icon,
                      selected: selected,
                      onTap: () => onFilterChanged(filter),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? const Color(0xFF15130D) : Colors.white60;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: <Color>[_kGoldSoft, _kGold])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _kGoldSoft.withValues(alpha: 0.56) : Colors.white.withValues(alpha: 0.08),
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: _kGoldSoft.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            _SafeText(
              label.toUpperCase(),
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.settings,
    required this.onDelete,
  });

  final SavedTrip trip;
  final SettingsService settings;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final double distance = settings.toDisplayDistance(trip.distanceMiles);
    final double maxSpeed = settings.toDisplaySpeed(trip.maxSpeedMph);
    final double avgSpeed = settings.toDisplaySpeed(trip.avgSpeedMph);

    return _GlassCard(
      radius: 28,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -42,
              top: -44,
              child: _BlurOrb(
                size: 130,
                color: trip.hasRoute
                    ? _kGoldSoft.withValues(alpha: 0.11)
                    : _kRed.withValues(alpha: 0.10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _RouteMiniMap(
                        route: trip.route,
                        accent: trip.hasRoute ? _kGoldSoft : Colors.white24,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _SafeText(
                                    trip.formattedDateShort,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                _TripStatusPill(hasRoute: trip.hasRoute),
                              ],
                            ),
                            const SizedBox(height: 5),
                            _SafeText(
                              trip.formattedDate,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Icon(
                                  trip.hasRoute ? CupertinoIcons.play_circle_fill : CupertinoIcons.location_slash,
                                  color: trip.hasRoute ? _kGreen : Colors.white30,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SafeText(
                                    trip.hasRoute
                                        ? '${trip.route.length} GPS points · cinematic replay'
                                        : 'No GPS route saved',
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 34,
                        onPressed: onDelete,
                        child: const Icon(CupertinoIcons.trash, color: _kRed, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Distance',
                          value: distance.toStringAsFixed(distance >= 100 ? 0 : 1),
                          unit: settings.distanceUnit,
                          color: _kGoldSoft,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Max',
                          value: maxSpeed.round().toString(),
                          unit: settings.speedUnit,
                          color: _kCyan,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Avg',
                          value: avgSpeed.round().toString(),
                          unit: settings.speedUnit,
                          color: _kGreen,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TripMiniStat(
                          label: 'Time',
                          value: trip.formattedDuration,
                          unit: '',
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: <Widget>[
                        const _SafeText(
                          'OPEN REPLAY',
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          CupertinoIcons.chevron_right_circle_fill,
                          color: trip.hasRoute ? _kGoldSoft : Colors.white24,
                          size: 19,
                        ),
                      ],
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

class _TripStatusPill extends StatelessWidget {
  const _TripStatusPill({required this.hasRoute});

  final bool hasRoute;

  @override
  Widget build(BuildContext context) {
    final Color color = hasRoute ? _kGreen : Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: _SafeText(
        hasRoute ? 'ROUTE' : 'DATA',
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _RouteMiniMap extends StatelessWidget {
  const _RouteMiniMap({
    required this.route,
    required this.accent,
  });

  final List<SavedRoutePoint> route;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: CustomPaint(
        painter: _RouteMiniPainter(route: route, accent: accent),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RouteMiniPainter extends CustomPainter {
  const _RouteMiniPainter({
    required this.route,
    required this.accent,
  });

  final List<SavedRoutePoint> route;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    for (int i = 1; i <= 2; i++) {
      final double offset = size.width * i / 3;
      canvas.drawLine(Offset(offset, 0), Offset(offset, size.height), gridPaint);
      canvas.drawLine(Offset(0, offset), Offset(size.width, offset), gridPaint);
    }

    if (route.length < 2) {
      final Paint dot = Paint()..color = accent.withValues(alpha: 0.7);
      canvas.drawCircle(size.center(Offset.zero), 5, dot);
      return;
    }

    double minLat = route.first.lat;
    double maxLat = route.first.lat;
    double minLng = route.first.lng;
    double maxLng = route.first.lng;

    for (final SavedRoutePoint point in route) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLng = math.min(minLng, point.lng);
      maxLng = math.max(maxLng, point.lng);
    }

    final double latRange = math.max(0.000001, maxLat - minLat);
    final double lngRange = math.max(0.000001, maxLng - minLng);
    final double pad = 12;
    final ui.Path path = ui.Path();

    for (int i = 0; i < route.length; i++) {
      final SavedRoutePoint point = route[i];
      final double x = pad + ((point.lng - minLng) / lngRange) * (size.width - pad * 2);
      final double y = pad + (1 - ((point.lat - minLat) / latRange)) * (size.height - pad * 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final Paint glow = Paint()
      ..color = accent.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 8;
    final Paint line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;

    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _RouteMiniPainter oldDelegate) {
    return oldDelegate.route != route || oldDelegate.accent != accent;
  }
}

class _TripMiniStat extends StatelessWidget {
  const _TripMiniStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _SafeText(
                value,
                maxLines: 1,
                style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
            if (unit.isNotEmpty)
              _SafeText(
                unit,
                maxLines: 1,
                style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900),
              ),
            const SizedBox(height: 5),
            _SafeText(
              label.toUpperCase(),
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white30,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(CupertinoIcons.trash_fill, color: _kRed),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(
        child: CupertinoActivityIndicator(color: _kGoldSoft, radius: 14),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: CupertinoIcons.map,
      title: 'No trips yet',
      subtitle: 'Saved recordings will appear here after tracking.',
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: CupertinoIcons.search,
      title: 'No matching trips',
      subtitle: 'Try another search or filter.',
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 90, 26, 26),
      child: Column(
        children: <Widget>[
          Icon(icon, color: _kGoldSoft, size: 44),
          const SizedBox(height: 16),
          _SafeText(
            title,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          _SafeText(
            subtitle,
            maxLines: 2,
            softWrap: true,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRIP DETAIL / REPLAY
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
  late final fm.MapController _mapController;
  late final List<SavedRoutePoint> _route;
  late final List<LatLng> _points;

  Timer? _replayTimer;
  DateTime _lastReplayTick = DateTime.now();

  bool _isPlaying = false;
  int _replayIndex = 0;
  double _segmentProgress = 0.0;
  double _replaySpeedMph = 0.0;
  double _replayBearing = 0.0;
  LatLng? _replayPosition;
  double _replaySpeedMultiplier = 1.0;
  bool _mapStylePickerOpen = false;
  late MapboxVisualStyle _visualStyle;

  bool get _hasRoute => _points.length >= 2;

  double get _routeProgress {
    if (!_hasRoute) return 0.0;
    final int segmentCount = math.max(1, _points.length - 1);
    return ((_replayIndex + _segmentProgress) / segmentCount).clamp(0.0, 1.0).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _mapController = fm.MapController();
    _route = widget.trip.route.where((SavedRoutePoint p) => p.isValid).toList(growable: false);
    _points = _route.map((SavedRoutePoint p) => p.latLng).toList(growable: false);
    _visualStyle = _initialVisualStyle();

    if (_hasRoute) {
      _replayPosition = _points.first;
      _replaySpeedMph = _route.first.speedMph;
      _replayBearing = _bearingBetween(_points.first, _points[1]);
    }
  }

  @override
  void dispose() {
    _stopReplayTimer();
    _mapController.dispose();
    super.dispose();
  }

  MapboxVisualStyle _initialVisualStyle() {
    final List<MapboxVisualStyle> styles = MapboxStyleCatalog.all;
    if (styles.isEmpty) {
      throw StateError('MapboxStyleCatalog.all must not be empty.');
    }

    final String mapName = widget.settings.mapStyle.name.toLowerCase();
    for (final MapboxVisualStyle style in styles) {
      if (style.storageKey.toLowerCase().contains(mapName) ||
          style.label.toLowerCase().contains(mapName)) {
        return style;
      }
    }

    return styles.first;
  }

  void _toggleReplay() {
    HapticFeedback.selectionClick();
    if (!_hasRoute) return;
    _isPlaying ? _pauseReplay() : _startReplay();
  }

  void _startReplay() {
    if (!_hasRoute) return;
    if (_replayIndex >= _points.length - 1 && _segmentProgress >= 1.0) {
      _resetReplay();
    }

    _lastReplayTick = DateTime.now();
    setState(() => _isPlaying = true);
    _replayTimer ??= Timer.periodic(_kReplayFrame, (_) => _onReplayTick());
  }

  void _pauseReplay() {
    _stopReplayTimer();
    if (mounted) setState(() => _isPlaying = false);
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
      _replayBearing = _hasRoute ? _bearingBetween(_points.first, _points[1]) : 0.0;
    });

    _moveMapToReplayPosition();
  }

  void _stopReplayTimer() {
    _replayTimer?.cancel();
    _replayTimer = null;
  }

  void _onReplayTick() {
    if (!_hasRoute || !mounted) return;

    final DateTime now = DateTime.now();
    final double dt = now.difference(_lastReplayTick).inMilliseconds / 1000.0;
    _lastReplayTick = now;

    final double step = (dt * _replaySpeedMultiplier * 1.8).clamp(0.0, 0.20).toDouble();

    setState(() {
      _segmentProgress += step;

      while (_segmentProgress >= 1.0 && _replayIndex < _points.length - 2) {
        _segmentProgress -= 1.0;
        _replayIndex++;
      }

      if (_replayIndex >= _points.length - 2 && _segmentProgress >= 1.0) {
        _replayIndex = _points.length - 2;
        _segmentProgress = 1.0;
        _isPlaying = false;
        _stopReplayTimer();
      }

      final LatLng a = _points[_replayIndex];
      final LatLng b = _points[(_replayIndex + 1).clamp(0, _points.length - 1)];
      final double t = _segmentProgress.clamp(0.0, 1.0).toDouble();

      _replayPosition = LatLng(
        ui.lerpDouble(a.latitude, b.latitude, t) ?? a.latitude,
        ui.lerpDouble(a.longitude, b.longitude, t) ?? a.longitude,
      );

      final double startSpeed = _route[_replayIndex].speedMph;
      final double endSpeed = _route[(_replayIndex + 1).clamp(0, _route.length - 1)].speedMph;
      _replaySpeedMph = ui.lerpDouble(startSpeed, endSpeed, t) ?? startSpeed;
      _replayBearing = _bearingBetween(a, b);
    });

    _moveMapToReplayPosition();
  }

  void _moveMapToReplayPosition() {
    final LatLng? position = _replayPosition;
    if (position == null) return;

    try {
      _mapController.move(position, math.max(_mapController.camera.zoom, 14.5));
    } catch (_) {
      // Map may not be ready yet.
    }
  }

  void _scrubReplay(double value) {
    if (!_hasRoute) return;

    HapticFeedback.selectionClick();
    _pauseReplay();

    final double safe = value.clamp(0.0, 1.0).toDouble();
    final double scaled = safe * (_points.length - 1);
    final int index = scaled.floor().clamp(0, math.max(0, _points.length - 2));
    final double progress = (scaled - index).clamp(0.0, 1.0).toDouble();

    setState(() {
      _replayIndex = index;
      _segmentProgress = progress;
      final LatLng a = _points[_replayIndex];
      final LatLng b = _points[(_replayIndex + 1).clamp(0, _points.length - 1)];
      _replayPosition = LatLng(
        ui.lerpDouble(a.latitude, b.latitude, progress) ?? a.latitude,
        ui.lerpDouble(a.longitude, b.longitude, progress) ?? a.longitude,
      );
      _replayBearing = _bearingBetween(a, b);
      _replaySpeedMph = _route[_replayIndex].speedMph;
    });

    _moveMapToReplayPosition();
  }

  void _selectStyle(MapboxVisualStyle style) {
    HapticFeedback.selectionClick();
    setState(() {
      _visualStyle = style;
      _mapStylePickerOpen = false;
    });
  }

  void _toggleStylePicker() {
    HapticFeedback.selectionClick();
    setState(() => _mapStylePickerOpen = !_mapStylePickerOpen);
  }

  fm.MapOptions _mapOptions() {
    if (_hasRoute) {
      return fm.MapOptions(
        initialCameraFit: fm.CameraFit.bounds(
          bounds: fm.LatLngBounds.fromPoints(_points),
          padding: const EdgeInsets.fromLTRB(46, 120, 46, 250),
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

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = widget.settings;
    final double distance = settings.toDisplayDistance(widget.trip.distanceMiles);
    final double maxSpeed = settings.toDisplaySpeed(widget.trip.maxSpeedMph);
    final double avgSpeed = settings.toDisplaySpeed(widget.trip.avgSpeedMph);
    final double replaySpeed = settings.toDisplaySpeed(_replaySpeedMph);
    final LocationPuckStyle puckStyle = settings.locationPuckStyle;
    final double puckSize = puckStyle.markerSize.clamp(50.0, 92.0).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CupertinoPageScaffold(
        backgroundColor: _kBg,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: _kBg.withValues(alpha: 0.72),
          border: null,
          middle: const Text('Trip Replay', style: TextStyle(color: Colors.white)),
          previousPageTitle: 'History',
        ),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: fm.FlutterMap(
                mapController: _mapController,
                options: _mapOptions(),
                children: <Widget>[
                  fm.TileLayer(
                    key: ValueKey<String>(_visualStyle.storageKey),
                    urlTemplate: _visualStyle.rasterTilesUrl(MapboxConfig.accessToken),
                    userAgentPackageName: 'com.trackpro.ai',
                    retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.0,
                  ),
                  if (_points.length >= 2)
                    fm.PolylineLayer(
                      polylines: <fm.Polyline>[
                        fm.Polyline(
                          points: _points,
                          color: Colors.white.withValues(alpha: 0.70),
                          strokeWidth: 10,
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
                  if (_replayPosition != null)
                    fm.MarkerLayer(
                      markers: <fm.Marker>[
                        fm.Marker(
                          point: _replayPosition!,
                          width: puckSize,
                          height: puckSize,
                          alignment: Alignment.center,
                          child: AppLocationPuck(
                            style: puckStyle,
                            bearing: _replayBearing,
                            speed: replaySpeed,
                            size: puckSize,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Positioned.fill(child: _MapGradientScrim()),
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 52,
              child: _DetailTopCard(
                trip: widget.trip,
                settings: settings,
                distance: distance,
                maxSpeed: maxSpeed,
                avgSpeed: avgSpeed,
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 58,
              right: 24,
              child: _MapStyleButton(
                style: _visualStyle,
                open: _mapStylePickerOpen,
                onTap: _toggleStylePicker,
              ),
            ),
            if (_mapStylePickerOpen)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 108,
                right: 16,
                child: _MapStylePicker(
                  selected: _visualStyle,
                  onChanged: _selectStyle,
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: _ReplayControls(
                hasRoute: _hasRoute,
                isPlaying: _isPlaying,
                progress: _routeProgress,
                replaySpeed: replaySpeed,
                speedUnit: settings.speedUnit,
                multiplier: _replaySpeedMultiplier,
                onPlayPause: _toggleReplay,
                onReset: _resetReplay,
                onScrub: _scrubReplay,
                onMultiplierChanged: (double value) {
                  HapticFeedback.selectionClick();
                  setState(() => _replaySpeedMultiplier = value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _bearingBetween(LatLng a, LatLng b) {
    final double lat1 = _degToRad(a.latitude);
    final double lat2 = _degToRad(b.latitude);
    final double dLng = _degToRad(b.longitude - a.longitude);

    final double y = math.sin(dLng) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    return ((_radToDeg(math.atan2(y, x)) + 360.0) % 360.0);
  }

  static double _degToRad(double value) => value * math.pi / 180.0;
  static double _radToDeg(double value) => value * 180.0 / math.pi;
}

class _MapGradientScrim extends StatelessWidget {
  const _MapGradientScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0.10),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.36),
              Colors.black.withValues(alpha: 0.92),
            ],
            stops: const <double>[0.0, 0.18, 0.46, 0.72, 1.0],
          ),
        ),
      ),
    );
  }
}

class _DetailTopCard extends StatelessWidget {
  const _DetailTopCard({
    required this.trip,
    required this.settings,
    required this.distance,
    required this.maxSpeed,
    required this.avgSpeed,
  });

  final SavedTrip trip;
  final SettingsService settings;
  final double distance;
  final double maxSpeed;
  final double avgSpeed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 62),
      child: _GlassCard(
        radius: 28,
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: <Color>[_kGoldSoft, _kGold]),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    CupertinoIcons.location_north_fill,
                    color: Color(0xFF15130D),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const _SafeText(
                        'Trip Replay',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _SafeText(
                        trip.formattedDate,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: _InlineMetric(
                    label: 'Distance',
                    value: distance.toStringAsFixed(distance >= 100 ? 0 : 1),
                    unit: settings.distanceUnit,
                    color: _kGoldSoft,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InlineMetric(
                    label: 'Max',
                    value: maxSpeed.round().toString(),
                    unit: settings.speedUnit,
                    color: _kCyan,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InlineMetric(
                    label: 'Avg',
                    value: avgSpeed.round().toString(),
                    unit: settings.speedUnit,
                    color: _kGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SafeText(
            value,
            maxLines: 1,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          _SafeText(
            unit.isEmpty ? label : '$label · $unit',
            maxLines: 1,
            style: const TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _MapStyleButton extends StatelessWidget {
  const _MapStyleButton({
    required this.style,
    required this.open,
    required this.onTap,
  });

  final MapboxVisualStyle style;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: open ? 0.95 : 0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: open ? style.accentColor.withValues(alpha: 0.60) : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Icon(style.icon, color: style.accentColor, size: 21),
          ),
        ),
      ),
    );
  }
}

class _MapStylePicker extends StatelessWidget {
  const _MapStylePicker({
    required this.selected,
    required this.onChanged,
  });

  final MapboxVisualStyle selected;
  final ValueChanged<MapboxVisualStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        width: 210,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: MapboxStyleCatalog.all.map((MapboxVisualStyle style) {
            final bool active = selected == style;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(style),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: active
                      ? style.accentColor.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: active
                        ? style.accentColor.withValues(alpha: 0.42)
                        : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(style.icon, color: style.accentColor, size: 16),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _SafeText(
                        style.shortLabel,
                        maxLines: 1,
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (active)
                      Icon(CupertinoIcons.checkmark_circle_fill, color: style.accentColor, size: 16),
                  ],
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _ReplayControls extends StatelessWidget {
  const _ReplayControls({
    required this.hasRoute,
    required this.isPlaying,
    required this.progress,
    required this.replaySpeed,
    required this.speedUnit,
    required this.multiplier,
    required this.onPlayPause,
    required this.onReset,
    required this.onScrub,
    required this.onMultiplierChanged,
  });

  final bool hasRoute;
  final bool isPlaying;
  final double progress;
  final double replaySpeed;
  final String speedUnit;
  final double multiplier;
  final VoidCallback onPlayPause;
  final VoidCallback onReset;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onMultiplierChanged;

  @override
  Widget build(BuildContext context) {
    final double safeProgress = progress.clamp(0.0, 1.0).toDouble();

    return _GlassCard(
      radius: 32,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: hasRoute ? onPlayPause : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: hasRoute
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[_kGoldSoft, _kGold],
                          )
                        : null,
                    color: hasRoute ? null : Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    boxShadow: hasRoute
                        ? <BoxShadow>[
                            BoxShadow(
                              color: _kGoldSoft.withValues(alpha: 0.22),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                    color: hasRoute ? const Color(0xFF15130D) : Colors.white24,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SafeText(
                      hasRoute ? '${replaySpeed.round()} $speedUnit' : 'NO ROUTE DATA',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _SafeText(
                      hasRoute
                          ? '${(safeProgress * 100).round()}% route · ${_speedLabel(multiplier)}x replay'
                          : 'This trip has no saved GPS points.',
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: hasRoute ? onReset : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: hasRoute ? 0.14 : 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBlue.withValues(alpha: hasRoute ? 0.22 : 0.06)),
                  ),
                  child: Icon(CupertinoIcons.gobackward, color: hasRoute ? _kBlue : Colors.white24, size: 21),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 26,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: safeProgress,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: <Color>[_kGoldSoft, _kCyan]),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  CupertinoSlider(
                    value: safeProgress,
                    min: 0,
                    max: 1,
                    activeColor: Colors.transparent,
                    thumbColor: hasRoute ? _kGoldSoft : Colors.white24,
                    onChanged: hasRoute ? onScrub : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _SpeedSelector(
            selected: multiplier,
            onChanged: hasRoute ? onMultiplierChanged : (_) {},
          ),
        ],
      ),
    );
  }

  static String _speedLabel(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({
    required this.selected,
    required this.onChanged,
  });

  final double selected;
  final ValueChanged<double> onChanged;

  static const List<double> _values = <double>[0.5, 1.0, 2.0, 4.0];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _values.map((double value) {
        final bool active = selected == value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  gradient: active ? const LinearGradient(colors: <Color>[_kBlue, _kCyan]) : null,
                  color: active ? null : Colors.white.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? _kCyan.withValues(alpha: 0.34) : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: _SafeText(
                  '${_ReplayControls._speedLabel(value)}x',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Colors.white.withValues(alpha: 0.105),
                _kSurface.withValues(alpha: 0.82),
                Colors.black.withValues(alpha: 0.40),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(padding: padding, child: child),
        ),
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
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

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
    return Text(
      data,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: softWrap,
      textAlign: textAlign,
      style: style,
    );
  }
}
