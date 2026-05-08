import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_data.dart';

class GpsService {
  GpsService._internal();
  static final GpsService instance = GpsService._internal();

  StreamController<TripPoint>? _pointController;
  StreamSubscription<Position>? _positionSubscription;

  // ── Internal Data ──────────────────────────────────────────────────────────
  final List<TripPoint> _points = [];
  final Stopwatch _tripStopwatch = Stopwatch();
  final Stopwatch _stoppedStopwatch = Stopwatch();

  Position? _lastPosition;
  double _totalDistanceMeters = 0;
  double _altitudeGainMeters = 0;
  double _maxSpeedMph = 0;
  double _movingSpeedSum = 0;
  int _movingPointsCount = 0;

  double _maxAltitudeFt = -100000;
  double _minAltitudeFt = 100000;
  double? _lastValidAltitude;

  // FIX: Track last-emitted point separately from last-stored point so the
  // stream always fires even when storage is skipped (RAM optimization path).
  Position? _lastEmittedPosition;

  // FIX: Debounce rapid bursts from the OS location layer.
  DateTime? _lastProcessedTimestamp;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  Stream<TripPoint>? get pointStream => _pointController?.stream;

  // ── Constants ──────────────────────────────────────────────────────────────
  static const double _stoppedThresholdMph = 1.1;
  static const double _mpsToMph = 2.23694;
  static const double _metersToFeet = 3.28084;
  static const double _metersToMiles = 1609.34;
  static const double _altitudeJitterThreshold = 1.5; // meters
  static const double _maxPlausibleSpeedMph = 240.0;
  static const double _minPointDistanceStorage = 3.0; // meters (RAM guard)
  static const int _minStorageIntervalSeconds = 10;
  // FIX: Minimum ms between processed positions to debounce OS bursts.
  static const int _minProcessIntervalMs = 250;

  // FIX: Accuracy threshold is platform-aware.
  static double get _minAccuracyThreshold => kIsWeb ? 100.0 : 40.0;

  // ── Public Accessors (UI) ──────────────────────────────────────────────────
  List<TripPoint> get currentPoints => UnmodifiableListView(_points);
  double get currentDistanceMiles => _totalDistanceMeters / _metersToMiles;
  double get currentMaxSpeedMph => _maxSpeedMph;
  double get currentAvgSpeedMph =>
      _movingPointsCount == 0 ? 0.0 : _movingSpeedSum / _movingPointsCount;
  Duration get currentTripTime => _tripStopwatch.elapsed;
  Duration get currentStoppedTime => _stoppedStopwatch.elapsed;

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    // FIX: Check service enabled first — avoids a crash on Android when
    // location services are fully disabled at the OS level.
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  // ── One-shot location (weather / UI init) ──────────────────────────────────

  Future<Position?> getCurrentLocation() async {
    try {
      final bool ok = await requestPermission();
      if (!ok) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          // FIX: Explicit timeLimit prevents hanging indefinitely on cold start.
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('GpsService.getCurrentLocation error: $e');
      // Faster fallback — getLastKnownPosition never throws.
      return Geolocator.getLastKnownPosition();
    }
  }

  // ── Tracking lifecycle ─────────────────────────────────────────────────────

  Future<void> startTracking() async {
    // FIX: Guard against calling startTracking while already running.
    if (_isTracking) return;

    final bool ok = await requestPermission();
    if (!ok) return;

    _resetInternalState();
    _isTracking = true;
    _tripStopwatch.start();

    // FIX: Always create a fresh broadcast controller so previous listeners
    // don't receive events from the new session.
    await _pointController?.close();
    _pointController = StreamController<TripPoint>.broadcast();

    final LocationSettings settings = _buildLocationSettings();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _handleNewPosition,
      onError: (Object e, StackTrace st) {
        // FIX: Log stack trace for easier debugging in production.
        debugPrint('GpsService stream error: $e\n$st');
      },
      // FIX: cancelOnError: false so a transient GPS glitch doesn't kill the
      // entire stream session.
      cancelOnError: false,
    );
  }

  TripSummary? stopTracking() {
    if (!_isTracking) return null;
    _isTracking = false;

    _tripStopwatch.stop();
    _stoppedStopwatch.stop();

    // FIX: Cancel subscription before closing controller to prevent late events
    // being pushed into a closed sink.
    _positionSubscription?.cancel();
    _positionSubscription = null;

    if (_points.isEmpty) {
      _pointController?.close();
      _pointController = null;
      return null;
    }

    // FIX: Guard sentinel values in case altitude was never updated.
    final double maxAlt = _maxAltitudeFt == -100000 ? 0 : _maxAltitudeFt;
    final double minAlt = _minAltitudeFt == 100000 ? 0 : _minAltitudeFt;

    final TripSummary summary = TripSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _points.first.timestamp,
      totalTime: _tripStopwatch.elapsed,
      stoppedTime: _stoppedStopwatch.elapsed,
      movingTime: _tripStopwatch.elapsed - _stoppedStopwatch.elapsed,
      maxSpeedMph: _maxSpeedMph,
      avgSpeedMph:
          _movingPointsCount == 0 ? 0.0 : _movingSpeedSum / _movingPointsCount,
      altitudeGainFt: _altitudeGainMeters * _metersToFeet,
      maxAltitudeFt: maxAlt,
      minAltitudeFt: minAlt,
      distanceMiles: _totalDistanceMeters / _metersToMiles,
      // FIX: Already an UnmodifiableListView from currentPoints; copy to a
      // plain list so TripSummary owns its own immutable snapshot.
      points: List.unmodifiable(List<TripPoint>.from(_points)),
    );

    _pointController?.close();
    _pointController = null;

    return summary;
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  void _resetInternalState() {
    _points.clear();
    _tripStopwatch.reset();
    _stoppedStopwatch.reset();
    _lastPosition = null;
    _lastEmittedPosition = null;
    _lastProcessedTimestamp = null;
    _lastValidAltitude = null;
    _totalDistanceMeters = 0;
    _altitudeGainMeters = 0;
    _maxSpeedMph = 0;
    _movingSpeedSum = 0;
    _movingPointsCount = 0;
    _maxAltitudeFt = -100000;
    _minAltitudeFt = 100000;
  }

  LocationSettings _buildLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        distanceFilter: 1,
      );
    }
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        intervalDuration: const Duration(seconds: 1),
        distanceFilter: 1,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Tracking your journey in real-time',
          notificationTitle: 'TrackPro AI Active',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }

  void _handleNewPosition(Position pos) {
    // ── 1. Debounce ──────────────────────────────────────────────────────────
    // FIX: Some Android devices fire positions in rapid bursts. Ignore events
    // that arrive faster than _minProcessIntervalMs.
    final now = DateTime.now();
    if (_lastProcessedTimestamp != null) {
      final int elapsed =
          now.difference(_lastProcessedTimestamp!).inMilliseconds;
      if (elapsed < _minProcessIntervalMs) return;
    }
    _lastProcessedTimestamp = now;

    // ── 2. Accuracy gate ─────────────────────────────────────────────────────
    if (pos.accuracy > _minAccuracyThreshold) return;

    // ── 3. Speed calculation ─────────────────────────────────────────────────
    double speedMps = pos.speed < 0 ? 0.0 : pos.speed;

    // FIX: Fallback speed calc uses _lastEmittedPosition (always set) rather
    // than _lastPosition (only set on stored points), giving better coverage.
    if (speedMps <= 0 && _lastEmittedPosition != null) {
      final double distMeters = Geolocator.distanceBetween(
        _lastEmittedPosition!.latitude,
        _lastEmittedPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      final double timeSecs = pos.timestamp
              .difference(_lastEmittedPosition!.timestamp)
              .inMilliseconds /
          1000.0;
      if (timeSecs > 0.1) {
        // FIX: Guard tiny time deltas that produce astronomical speeds.
        speedMps = distMeters / timeSecs;
      }
    }

    final double speedMph = speedMps * _mpsToMph;

    // FIX: Hard-clamp implausible spikes rather than just returning — this way
    // we still update stopped/moving state and emit a point.
    final double clampedSpeedMph = speedMph.clamp(0.0, _maxPlausibleSpeedMph);

    final double altitudeFt = pos.altitude * _metersToFeet;

    // ── 4. Peak statistics ───────────────────────────────────────────────────
    if (clampedSpeedMph > _maxSpeedMph) _maxSpeedMph = clampedSpeedMph;
    if (altitudeFt > _maxAltitudeFt) _maxAltitudeFt = altitudeFt;
    if (altitudeFt < _minAltitudeFt) _minAltitudeFt = altitudeFt;

    // ── 5. Distance + stopped time ───────────────────────────────────────────
    if (_lastPosition != null) {
      final double gap = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );

      // FIX: Use clampedSpeedMph so an implausible spike doesn't accumulate
      // distance. Require both speed threshold AND minimum displacement.
      if (clampedSpeedMph >= _stoppedThresholdMph && gap > 1.0) {
        _totalDistanceMeters += gap;
        _movingSpeedSum += clampedSpeedMph;
        _movingPointsCount++;
        if (_stoppedStopwatch.isRunning) _stoppedStopwatch.stop();
      } else {
        if (!_stoppedStopwatch.isRunning) _stoppedStopwatch.start();
      }

      // ── 6. Altitude gain (jitter-filtered) ────────────────────────────────
      if (_lastValidAltitude == null) {
        _lastValidAltitude = pos.altitude;
      } else {
        final double altDiff = pos.altitude - _lastValidAltitude!;
        if (altDiff.abs() > _altitudeJitterThreshold) {
          if (altDiff > 0) _altitudeGainMeters += altDiff;
          _lastValidAltitude = pos.altitude;
        }
      }
    }

    // ── 7. Build point ───────────────────────────────────────────────────────
    final TripPoint point = TripPoint(
      position: LatLng(pos.latitude, pos.longitude),
      speedMph: clampedSpeedMph,
      altitudeFt: altitudeFt,
      timestamp: pos.timestamp,
      accuracyMeters: pos.accuracy,
    );

    // ── 8. Smart storage (RAM optimization) ─────────────────────────────────
    // FIX: Decouple storage decision from emission — always emit, selectively
    // store. Previously, _lastPosition was only updated on stored points, which
    // caused the fallback speed calc to use stale positions.
    bool shouldStore = _points.isEmpty;
    if (!shouldStore && _lastPosition != null) {
      final double d = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );
      final bool distTrigger = d >= _minPointDistanceStorage;
      final bool timeTrigger =
          pos.timestamp.difference(_points.last.timestamp).inSeconds >=
              _minStorageIntervalSeconds;
      shouldStore = distTrigger || timeTrigger;
    }

    if (shouldStore) {
      _points.add(point);
      // FIX: _lastPosition only tracks stored points (for storage gating).
      _lastPosition = pos;
    }

    // FIX: _lastEmittedPosition tracks every position for speed fallback.
    _lastEmittedPosition = pos;

    // ── 9. Emit to stream ────────────────────────────────────────────────────
    // FIX: Check both null and closed before adding to sink.
    final StreamController<TripPoint>? ctrl = _pointController;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(point);
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  void dispose() {
    _isTracking = false;
    _tripStopwatch.stop();
    _stoppedStopwatch.stop();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _pointController?.close();
    _pointController = null;
  }
}
