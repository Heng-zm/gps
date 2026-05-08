import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../services/settings_service.dart';

/// ─── MODEL: SAVED TRIP ──────────────────────────────────────────────────────
class SavedTrip {
  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;

  // PERFORMANCE: Pre-calculate formatters so they don't run during scrolling.
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
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'distanceMiles': distanceMiles,
        'maxSpeedMph': maxSpeedMph,
        'avgSpeedMph': avgSpeedMph,
        'totalTimeSeconds': totalTime.inSeconds,
        'altitudeGainFt': altitudeGainFt,
      };

  // FIX: Returns null instead of a silently broken Jan-1-1970 object when
  // the 'date' field is missing or zero.
  static SavedTrip? tryFromJson(Map<String, dynamic> json) {
    final rawDate = (json['date'] as num?)?.toInt();
    if (rawDate == null || rawDate == 0) {
      debugPrint('SavedTrip.tryFromJson: missing or zero date — skipping.');
      return null;
    }
    return SavedTrip(
      id: json['id']?.toString() ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(rawDate),
      distanceMiles: (json['distanceMiles'] as num?)?.toDouble() ?? 0.0,
      maxSpeedMph: (json['maxSpeedMph'] as num?)?.toDouble() ?? 0.0,
      avgSpeedMph: (json['avgSpeedMph'] as num?)?.toDouble() ?? 0.0,
      totalTime:
          Duration(seconds: (json['totalTimeSeconds'] as num?)?.toInt() ?? 0),
      altitudeGainFt: (json['altitudeGainFt'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // FIX: Shows seconds for sub-minute trips so a 45-second trip no longer
  // shows '0m'. Tiers: Xh YYm | Ym YYs | Xs
  String _calculateFormattedDuration() {
    final h = totalTime.inHours;
    final m = totalTime.inMinutes.remainder(60);
    final s = totalTime.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  // ── SUPABASE CRUD ──────────────────────────────────────────────────────────

  // FIX: upsert instead of insert — re-saving the same trip ID no longer
  // throws a duplicate-key error.
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

  // FIX: Uses tryFromJson so records with bad dates are skipped cleanly.
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

  // Cached lifetime stats.
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

  // FIX: Changed from `void async` to `Future<void>` so callers can await it
  // and exceptions propagate instead of being silently swallowed.
  Future<void> _executeDelete(SavedTrip trip) async {
    await HapticFeedback.mediumImpact();
    final originalIndex = _trips.indexOf(trip);

    // 1. Optimistic removal from UI.
    setState(() {
      _trips.remove(trip);
      _calculateLifetimeStats();
    });

    // 2. Background cloud delete.
    final success = await SavedTrip.deleteTrip(trip.id);

    // 3. Rollback on failure.
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

  // FIX: Uses the dialog's own BuildContext `c` for Navigator.pop() to avoid
  // using a potentially stale outer context after the async gap.
  // FIX: confirmDismiss always returns false — the Dismissible widget must
  // not perform its own removal animation since the state update (_trips.remove)
  // already handles it. Returning true from confirmDismiss caused a duplicate-
  // removal flash where the item disappeared twice.
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
            // FIX: Use dialog-scoped context `c`, not the outer `context`.
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

    // Always return false: state management handles list removal, not Dismissible.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _loadTrips),
            SliverToBoxAdapter(child: _buildHeader()),
            // FIX: Only show lifetime stats when not loading — prevents stale
            // data from the previous fetch appearing above the new spinner.
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
                    child: _TripCard(
                      trip: _trips[i],
                      onDelete: () => _confirmDelete(_trips[i]),
                      settings: _settings,
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
          // FIX: Show a neutral subtitle while loading so the stale count
          // doesn't flicker during refresh.
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
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF222222)),
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
                color: Color(0xFF4ECDC4),
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
          color: const Color(0xFFE74C3C).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(CupertinoIcons.delete,
            color: Color(0xFFE74C3C), size: 22),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF252525)),
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
                Text(
                  '${settings.toDisplayDistance(trip.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MiniStat(
                    label: 'MAX',
                    value:
                        '${settings.toDisplaySpeed(trip.maxSpeedMph).toInt()} ${settings.speedUnit}'),
                _MiniStat(
                    label: 'AVG',
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
        color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(CupertinoIcons.placemark_fill,
          color: Color(0xFF4ECDC4), size: 18),
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
                color: Color(0xFF555555),
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
      Container(width: 1, height: 28, color: const Color(0xFF2A2A2A));
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
