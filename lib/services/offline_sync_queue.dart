import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Offline Sync Queue for TrackPro trips.
///
/// Purpose:
/// - If Supabase save fails, keep the trip payload locally.
/// - Retry upload later from Summary/History/Settings/main startup.
/// - Prevent duplicate queued items by trip id.
/// - Keep queue small and safe for SharedPreferences.
///
/// This service stores only payloads intended for the public.saved_trips table.
class OfflineSyncQueue {
  OfflineSyncQueue._();

  static final OfflineSyncQueue instance = OfflineSyncQueue._();

  static const String _queueKey = 'trackpro_offline_sync_queue_v1';
  static const int _maxItems = 80;
  static const int _maxAttemptsBeforeSlowRetry = 5;

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  bool _syncing = false;

  /// Call once on app startup after Settings/Supabase init.
  Future<void> loadStatus() async {
    final List<_QueuedTrip> queue = await _readQueue();
    pendingCount.value = queue.length;
  }

  /// Add or replace a pending trip payload.
  Future<void> enqueueTrip(
    Map<String, dynamic> payload, {
    Object? error,
  }) async {
    final String id = payload['id']?.toString() ?? '';
    if (id.isEmpty) {
      debugPrint('OfflineSyncQueue ignored trip with empty id.');
      return;
    }

    final List<_QueuedTrip> queue = await _readQueue();

    final DateTime now = DateTime.now();
    final _QueuedTrip item = _QueuedTrip(
      id: id,
      table: 'saved_trips',
      payload: Map<String, dynamic>.from(payload),
      createdAtMillis: now.millisecondsSinceEpoch,
      updatedAtMillis: now.millisecondsSinceEpoch,
      attempts: 0,
      lastError: error?.toString(),
    );

    final List<_QueuedTrip> next = <_QueuedTrip>[item];

    for (final _QueuedTrip existing in queue) {
      if (existing.id == id) continue;
      if (next.length >= _maxItems) break;
      next.add(existing);
    }

    await _writeQueue(next);

    debugPrint(
      'OfflineSyncQueue queued trip $id. Pending: ${next.length}. Error: $error',
    );
  }

  /// Try to upload all queued trips.
  ///
  /// Returns sync result for UI messages.
  Future<OfflineSyncResult> syncNow() async {
    if (_syncing) {
      return OfflineSyncResult(
        attempted: 0,
        succeeded: 0,
        failed: pendingCount.value,
        pending: pendingCount.value,
        message: 'Sync already running.',
      );
    }

    _syncing = true;

    try {
      final List<_QueuedTrip> queue = await _readQueue();

      if (queue.isEmpty) {
        pendingCount.value = 0;
        return const OfflineSyncResult(
          attempted: 0,
          succeeded: 0,
          failed: 0,
          pending: 0,
          message: 'No offline trips to sync.',
        );
      }

      int attempted = 0;
      int succeeded = 0;
      int failed = 0;

      final List<_QueuedTrip> stillPending = <_QueuedTrip>[];

      for (final _QueuedTrip item in queue) {
        attempted++;

        if (!_shouldRetryNow(item)) {
          stillPending.add(item);
          continue;
        }

        try {
          await Supabase.instance.client
              .from(item.table)
              .upsert(item.payload, onConflict: 'id');

          succeeded++;
          debugPrint('OfflineSyncQueue synced trip ${item.id}.');
        } catch (error, stackTrace) {
          failed++;
          debugPrint(
            'OfflineSyncQueue failed trip ${item.id}: $error\n$stackTrace',
          );

          stillPending.add(
            item.copyWithFailure(error.toString()),
          );
        }
      }

      await _writeQueue(stillPending);

      final String message = succeeded > 0 && stillPending.isEmpty
          ? 'Offline sync complete. $succeeded trip(s) uploaded.'
          : succeeded > 0
              ? 'Synced $succeeded trip(s). ${stillPending.length} still pending.'
              : 'Offline sync failed. ${stillPending.length} trip(s) still pending.';

      return OfflineSyncResult(
        attempted: attempted,
        succeeded: succeeded,
        failed: failed,
        pending: stillPending.length,
        message: message,
      );
    } finally {
      _syncing = false;
    }
  }

  /// Returns pending queue items for UI/debug.
  Future<List<OfflineSyncItemInfo>> pendingItems() async {
    final List<_QueuedTrip> queue = await _readQueue();

    return queue.map((item) {
      return OfflineSyncItemInfo(
        id: item.id,
        table: item.table,
        attempts: item.attempts,
        lastError: item.lastError,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(item.updatedAtMillis),
      );
    }).toList(growable: false);
  }

  /// Remove a queued trip by id after user deletes/discards it.
  Future<void> remove(String id) async {
    final List<_QueuedTrip> queue = await _readQueue();
    final List<_QueuedTrip> next = queue
        .where((_QueuedTrip item) => item.id != id)
        .toList(growable: false);

    await _writeQueue(next);
  }

  /// Clear everything. Use only for factory reset/debug.
  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
    pendingCount.value = 0;
  }

  bool _shouldRetryNow(_QueuedTrip item) {
    if (item.attempts < _maxAttemptsBeforeSlowRetry) return true;

    final DateTime last =
        DateTime.fromMillisecondsSinceEpoch(item.updatedAtMillis);
    final Duration age = DateTime.now().difference(last);

    // After many failures, avoid hammering Supabase/network.
    return age.inMinutes >= 10;
  }

  Future<List<_QueuedTrip>> _readQueue() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> rawItems =
          prefs.getStringList(_queueKey) ?? <String>[];

      final List<_QueuedTrip> queue = <_QueuedTrip>[];

      for (final String raw in rawItems) {
        try {
          final Object? decoded = jsonDecode(raw);
          final _QueuedTrip? item = _QueuedTrip.tryFromJson(decoded);
          if (item != null) queue.add(item);
        } catch (error) {
          debugPrint('OfflineSyncQueue skipped corrupted item: $error');
        }
      }

      pendingCount.value = queue.length;
      return List<_QueuedTrip>.unmodifiable(queue);
    } catch (error, stackTrace) {
      debugPrint('OfflineSyncQueue read error: $error\n$stackTrace');
      pendingCount.value = 0;
      return const <_QueuedTrip>[];
    }
  }

  Future<void> _writeQueue(List<_QueuedTrip> queue) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final List<String> encoded = queue
        .take(_maxItems)
        .map((_QueuedTrip item) => jsonEncode(item.toJson()))
        .toList(growable: false);

    await prefs.setStringList(_queueKey, encoded);
    pendingCount.value = encoded.length;
  }
}

class OfflineSyncResult {
  const OfflineSyncResult({
    required this.attempted,
    required this.succeeded,
    required this.failed,
    required this.pending,
    required this.message,
  });

  final int attempted;
  final int succeeded;
  final int failed;
  final int pending;
  final String message;

  bool get hasPending => pending > 0;
  bool get hasSuccess => succeeded > 0;
}

class OfflineSyncItemInfo {
  const OfflineSyncItemInfo({
    required this.id,
    required this.table,
    required this.attempts,
    required this.lastError,
    required this.updatedAt,
  });

  final String id;
  final String table;
  final int attempts;
  final String? lastError;
  final DateTime updatedAt;
}

class _QueuedTrip {
  const _QueuedTrip({
    required this.id,
    required this.table,
    required this.payload,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    required this.attempts,
    required this.lastError,
  });

  final String id;
  final String table;
  final Map<String, dynamic> payload;
  final int createdAtMillis;
  final int updatedAtMillis;
  final int attempts;
  final String? lastError;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'table': table,
      'payload': payload,
      'createdAtMillis': createdAtMillis,
      'updatedAtMillis': updatedAtMillis,
      'attempts': attempts,
      if (lastError != null) 'lastError': lastError,
    };
  }

  _QueuedTrip copyWithFailure(String error) {
    return _QueuedTrip(
      id: id,
      table: table,
      payload: payload,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      attempts: attempts + 1,
      lastError: error,
    );
  }

  static _QueuedTrip? tryFromJson(Object? raw) {
    if (raw is! Map) return null;

    final Map<String, dynamic> json = raw.map(
      (dynamic key, dynamic value) => MapEntry<String, dynamic>(
        key.toString(),
        value,
      ),
    );

    final String id = json['id']?.toString() ?? '';
    final String table = json['table']?.toString() ?? 'saved_trips';
    final Object? payloadRaw = json['payload'];

    if (id.isEmpty || payloadRaw is! Map) return null;

    final Map<String, dynamic> payload = payloadRaw.map(
      (dynamic key, dynamic value) => MapEntry<String, dynamic>(
        key.toString(),
        value,
      ),
    );

    return _QueuedTrip(
      id: id,
      table: table.isEmpty ? 'saved_trips' : table,
      payload: payload,
      createdAtMillis: _asInt(json['createdAtMillis']),
      updatedAtMillis: _asInt(json['updatedAtMillis']),
      attempts: _asInt(json['attempts']),
      lastError: json['lastError']?.toString(),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
