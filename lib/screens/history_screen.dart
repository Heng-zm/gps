import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../services/settings_service.dart';

/// Model representing a trip stored in local persistence.
class SavedTrip {
  final String id;
  final DateTime date;
  final double distanceMiles;
  final double maxSpeedMph;
  final double avgSpeedMph;
  final Duration totalTime;
  final double altitudeGainFt;

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

  factory SavedTrip.fromJson(Map<String, dynamic> json) => SavedTrip(
        id: json['id'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
        distanceMiles: (json['distanceMiles'] as num).toDouble(),
        maxSpeedMph: (json['maxSpeedMph'] as num).toDouble(),
        avgSpeedMph: (json['avgSpeedMph'] as num).toDouble(),
        totalTime: Duration(seconds: json['totalTimeSeconds'] as int),
        altitudeGainFt: (json['altitudeGainFt'] as num).toDouble(),
      );

  String get formattedDate => DateFormat('MMM d, yyyy · h:mm a').format(date);

  String get formattedDuration {
    final h = totalTime.inHours;
    final m = totalTime.inMinutes.remainder(60);
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    return '${m}m';
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SettingsService _settings = SettingsService.instance;
  List<SavedTrip> _trips = [];
  bool _loading = true;

  // Cached Lifetime Stats
  double _totalMiles = 0;
  double _allTimeTopSpeedMph = 0;
  int _totalMinutes = 0;

  @override
  void initState() {
    super.initState();
    // Re-calculate units if user toggles km/mi in settings
    _settings.addListener(_updateUI);
    _loadTrips();
  }

  @override
  void dispose() {
    _settings.removeListener(_updateUI);
    super.dispose();
  }

  void _updateUI() => setState(() {});

  void _calculateLifetimeStats() {
    _totalMiles = 0;
    _allTimeTopSpeedMph = 0;
    _totalMinutes = 0;

    for (final t in _trips) {
      _totalMiles += t.distanceMiles;
      if (t.maxSpeedMph > _allTimeTopSpeedMph) {
        _allTimeTopSpeedMph = t.maxSpeedMph;
      }
      _totalMinutes += t.totalTime.inMinutes;
    }
  }

  Future<void> _loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('saved_trips') ?? [];

    final parsedTrips = raw.map((s) {
      return SavedTrip.fromJson(jsonDecode(s) as Map<String, dynamic>);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (mounted) {
      setState(() {
        _trips = parsedTrips;
        _calculateLifetimeStats();
        _loading = false;
      });
    }
  }

  Future<void> _deleteTrip(String id) async {
    await HapticFeedback.mediumImpact();
    setState(() {
      _trips.removeWhere((t) => t.id == id);
      _calculateLifetimeStats();
    });

    final prefs = await SharedPreferences.getInstance();
    final updatedRaw = _trips.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('saved_trips', updatedRaw);
  }

  Future<bool> _confirmDelete(SavedTrip trip) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete Trip'),
        content: const Text(
          'This data will be permanently removed from your device.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteTrip(trip.id);
      return true;
    }
    return false;
  }

  @override
  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),

            // FIX: Removed curly braces { }.
            // In a List, 'if (condition) widget' is the correct syntax.
            if (_trips.isNotEmpty) _buildLifetimeSummary(),

            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator(radius: 12))
                  : _trips.isEmpty
                      ? const _EmptyState()
                      : _buildTripList(),
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
          Text(
            '${_trips.length} recording${_trips.length == 1 ? '' : 's'} available',
            style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLifetimeSummary() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(20),
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

  Widget _buildTripList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      itemCount: _trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _TripCard(
        trip: _trips[i],
        onDelete: () => _confirmDelete(_trips[i]),
        settings: _settings,
      ),
    );
  }
}

class _LifetimeStat extends StatelessWidget {
  final String label, value;
  const _LifetimeStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4ECDC4),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  final SavedTrip trip;
  final SettingsService settings;
  final Future<bool> Function() onDelete;

  const _TripCard({
    required this.trip,
    required this.onDelete,
    required this.settings,
  });

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
          color: const Color(0xFFE74C3C).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          CupertinoIcons.delete,
          color: Color(0xFFE74C3C),
          size: 22,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(18),
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
                      Text(
                        trip.formattedDate,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trip.formattedDuration,
                        style: const TextStyle(
                          color: Color(0xFF777777),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${settings.toDisplayDistance(trip.distanceMiles).toStringAsFixed(2)} ${settings.distanceUnit}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(color: Color(0xFF2A2A2A), height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MiniStat(
                  label: 'MAX',
                  value:
                      '${settings.toDisplaySpeed(trip.maxSpeedMph).toInt()} ${settings.speedUnit}',
                ),
                _MiniStat(
                  label: 'AVG',
                  value:
                      '${settings.toDisplaySpeed(trip.avgSpeedMph).toInt()} ${settings.speedUnit}',
                ),
                _MiniStat(
                  label: 'ALT GAIN',
                  value: '+${trip.altitudeGainFt.toInt()} ft',
                ),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        CupertinoIcons.placemark_fill,
        color: Color(0xFF4ECDC4),
        size: 18,
      ),
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
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF555555),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.tickets,
            color: Colors.white.withValues(alpha: 0.1),
            size: 60,
          ),
          const SizedBox(height: 20),
          const Text(
            'No Trips Found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Completed trips will appear here.',
            style: TextStyle(color: Color(0xFF555555), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
