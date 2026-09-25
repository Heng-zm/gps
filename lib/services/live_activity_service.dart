import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service managing iOS ActivityKit Live Activities & Dynamic Island updates,
/// as well as coordinating lock-screen metric synchronization for active journeys.
class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  static const MethodChannel _channel =
      MethodChannel('com.trackpro.live_activity');

  bool _isActive = false;
  bool? _isSupportedCached;
  DateTime? _lastUpdateTime;

  /// Returns whether a Live Activity is currently active.
  bool get isActive => _isActive;

  /// Check whether Live Activities are supported and enabled on the current platform/device.
  Future<bool> isSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    if (_isSupportedCached != null) return _isSupportedCached!;

    try {
      final bool? supported = await _channel.invokeMethod<bool>('isSupported');
      _isSupportedCached = supported ?? false;
      return _isSupportedCached!;
    } catch (e) {
      debugPrint('[LiveActivityService] isSupported error: $e');
      _isSupportedCached = false;
      return false;
    }
  }

  /// Starts a Live Activity for the current tracking session.
  Future<String?> startActivity({
    String tripName = 'TrackPro Journey',
    double speedMph = 0.0,
    double distanceMiles = 0.0,
    Duration elapsedTime = Duration.zero,
    double maxSpeedMph = 0.0,
    double avgSpeedMph = 0.0,
    String speedUnit = 'MPH',
    String distanceUnit = 'mi',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      _isActive = true;
      return null;
    }

    try {
      final String formattedTime = _formatDuration(elapsedTime);
      final dynamic activityId = await _channel.invokeMethod('startActivity', <String, dynamic>{
        'tripName': tripName,
        'speedMph': speedMph,
        'distanceMiles': distanceMiles,
        'elapsedSeconds': elapsedTime.inSeconds,
        'formattedTime': formattedTime,
        'maxSpeedMph': maxSpeedMph,
        'avgSpeedMph': avgSpeedMph,
        'speedUnit': speedUnit,
        'distanceUnit': distanceUnit,
      });

      _isActive = true;
      _lastUpdateTime = DateTime.now();
      debugPrint('[LiveActivityService] Started Live Activity: $activityId');
      return activityId?.toString();
    } catch (e) {
      debugPrint('[LiveActivityService] startActivity error: $e');
      _isActive = false;
      return null;
    }
  }

  /// Updates the ongoing Live Activity with real-time tracking metrics.
  /// Throttled to at most once per [minThrottleDuration] (default 1 second)
  /// to preserve battery and channel bandwidth unless [force] is true.
  Future<void> updateActivity({
    required double speedMph,
    required double distanceMiles,
    required Duration elapsedTime,
    double maxSpeedMph = 0.0,
    double avgSpeedMph = 0.0,
    String speedUnit = 'MPH',
    String distanceUnit = 'mi',
    Duration minThrottleDuration = const Duration(milliseconds: 900),
    bool force = false,
  }) async {
    if (!_isActive) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    final DateTime now = DateTime.now();
    if (!force && _lastUpdateTime != null) {
      if (now.difference(_lastUpdateTime!) < minThrottleDuration) {
        return;
      }
    }
    _lastUpdateTime = now;

    try {
      final String formattedTime = _formatDuration(elapsedTime);
      await _channel.invokeMethod('updateActivity', <String, dynamic>{
        'speedMph': speedMph,
        'distanceMiles': distanceMiles,
        'elapsedSeconds': elapsedTime.inSeconds,
        'formattedTime': formattedTime,
        'maxSpeedMph': maxSpeedMph,
        'avgSpeedMph': avgSpeedMph,
        'speedUnit': speedUnit,
        'distanceUnit': distanceUnit,
      });
    } catch (e) {
      debugPrint('[LiveActivityService] updateActivity error: $e');
    }
  }

  /// Ends any ongoing Live Activity and dismisses it from Dynamic Island and Lock Screen.
  Future<void> stopActivity() async {
    _isActive = false;
    _lastUpdateTime = null;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    try {
      await _channel.invokeMethod('stopActivity');
      debugPrint('[LiveActivityService] Stopped Live Activity');
    } catch (e) {
      debugPrint('[LiveActivityService] stopActivity error: $e');
    }
  }

  static String _formatDuration(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
