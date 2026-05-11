import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GPS SERVICE
// ─────────────────────────────────────────────────────────────────────────────

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
  Position? _lastEmittedPosition;
  DateTime? _lastProcessedTimestamp;
  double? _lastValidAltitude;

  double _totalDistanceMeters = 0;
  double _altitudeGainMeters = 0;
  double _maxSpeedMph = 0;
  double _movingSpeedSum = 0;
  int _movingPointsCount = 0;

  double _maxAltitudeFt = -100000;
  double _minAltitudeFt = 100000;

  // Speed smoothing — keep a small ring buffer of recent clamped speeds.
  final List<double> _recentSpeeds = [];
  static const int _speedSmoothingWindow = 4;

  // Kalman-lite: rolling accuracy-weighted position smoother state.
  double? _smoothedLat;
  double? _smoothedLng;
  double _kalmanUncertainty = 15.0; // metres

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  // ── Trip metadata ──────────────────────────────────────────────────────────
  // Expose start time so UI can compute elapsed duration independently.
  DateTime? _tripStartTime;
  DateTime? get tripStartTime => _tripStartTime;

  // ── Stream ─────────────────────────────────────────────────────────────────
  Stream<TripPoint>? get pointStream => _pointController?.stream;

  // ── Constants ──────────────────────────────────────────────────────────────
  static const double _stoppedThresholdMph = 1.1;
  static const double _mpsToMph = 2.23694;
  static const double _metersToFeet = 3.28084;
  static const double _metersToMiles = 1609.34;
  static const double _altitudeJitterThreshold = 1.5; // metres
  static const double _maxPlausibleSpeedMph = 250.0;
  static const double _minPointDistanceStorage = 3.0; // metres
  static const int _minStorageIntervalSeconds = 10;
  static const int _minProcessIntervalMs = 200;

  // Kalman process noise (Q) — tune higher for faster response, lower for
  // smoother path.
  static const double _kalmanProcessNoise = 3.0; // metres²/update

  static double get _minAccuracyThreshold => kIsWeb ? 100.0 : 40.0;

  // ── Public Accessors ───────────────────────────────────────────────────────
  List<TripPoint> get currentPoints => UnmodifiableListView(_points);
  double get currentDistanceMiles => _totalDistanceMeters / _metersToMiles;
  double get currentMaxSpeedMph => _maxSpeedMph;
  double get currentAvgSpeedMph =>
      _movingPointsCount == 0 ? 0.0 : _movingSpeedSum / _movingPointsCount;
  Duration get currentTripTime => _tripStopwatch.elapsed;
  Duration get currentStoppedTime => _stoppedStopwatch.elapsed;
  Duration get currentMovingTime =>
      _tripStopwatch.elapsed - _stoppedStopwatch.elapsed;

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
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
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (e) {
      debugPrint('GpsService.getCurrentLocation error: $e');
      return Geolocator.getLastKnownPosition();
    }
  }

  // ── Tracking lifecycle ─────────────────────────────────────────────────────

  Future<void> startTracking() async {
    if (_isTracking) return;

    final bool ok = await requestPermission();
    if (!ok) return;

    _resetInternalState();
    _isTracking = true;
    _tripStartTime = DateTime.now();
    _tripStopwatch.start();

    await _pointController?.close();
    _pointController = StreamController<TripPoint>.broadcast();

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(
      _handleNewPosition,
      onError: (Object e, StackTrace st) {
        debugPrint('GpsService stream error: $e\n$st');
      },
      cancelOnError: false,
    );
  }

  TripSummary? stopTracking() {
    if (!_isTracking) return null;
    _isTracking = false;

    _tripStopwatch.stop();
    _stoppedStopwatch.stop();

    _positionSubscription?.cancel();
    _positionSubscription = null;

    if (_points.isEmpty) {
      _pointController?.close();
      _pointController = null;
      _tripStartTime = null;
      return null;
    }

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
      points: List.unmodifiable(List<TripPoint>.from(_points)),
    );

    _pointController?.close();
    _pointController = null;
    _tripStartTime = null;

    return summary;
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  void _resetInternalState() {
    _points.clear();
    _recentSpeeds.clear();
    _tripStopwatch.reset();
    _stoppedStopwatch.reset();
    _lastPosition = null;
    _lastEmittedPosition = null;
    _lastProcessedTimestamp = null;
    _lastValidAltitude = null;
    _smoothedLat = null;
    _smoothedLng = null;
    _kalmanUncertainty = 15.0;
    _totalDistanceMeters = 0;
    _altitudeGainMeters = 0;
    _maxSpeedMph = 0;
    _movingSpeedSum = 0;
    _movingPointsCount = 0;
    _maxAltitudeFt = -100000;
    _minAltitudeFt = 100000;
  }

  // ── Location settings ──────────────────────────────────────────────────────

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
        intervalDuration: const Duration(milliseconds: 800),
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

  // ── Core position handler ──────────────────────────────────────────────────

  void _handleNewPosition(Position pos) {
    // ── 1. Debounce rapid OS bursts ──────────────────────────────────────────
    final DateTime now = DateTime.now();
    if (_lastProcessedTimestamp != null) {
      final int elapsed =
          now.difference(_lastProcessedTimestamp!).inMilliseconds;
      if (elapsed < _minProcessIntervalMs) return;
    }
    _lastProcessedTimestamp = now;

    // ── 2. Accuracy gate ─────────────────────────────────────────────────────
    if (pos.accuracy > _minAccuracyThreshold) return;

    // ── 3. Kalman-lite position smoother ─────────────────────────────────────
    // Reduces GPS jitter on stationary or slow-moving paths.
    final LatLng smoothedPos = _kalmanSmooth(pos);

    // ── 4. Speed calculation ─────────────────────────────────────────────────
    double speedMps = pos.speed < 0 ? 0.0 : pos.speed;

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
      if (timeSecs > 0.1) speedMps = distMeters / timeSecs;
    }

    final double rawSpeedMph = speedMps * _mpsToMph;
    final double clampedSpeedMph =
        rawSpeedMph.clamp(0.0, _maxPlausibleSpeedMph);

    // ── 5. Speed smoothing (rolling average) ─────────────────────────────────
    _recentSpeeds.add(clampedSpeedMph);
    if (_recentSpeeds.length > _speedSmoothingWindow) {
      _recentSpeeds.removeAt(0);
    }
    final double smoothedSpeedMph =
        _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;

    final double altitudeFt = pos.altitude * _metersToFeet;

    // ── 6. Peak statistics ───────────────────────────────────────────────────
    // Use raw clamped speed for peak (smoothed would under-report true max).
    if (clampedSpeedMph > _maxSpeedMph) _maxSpeedMph = clampedSpeedMph;
    if (altitudeFt > _maxAltitudeFt) _maxAltitudeFt = altitudeFt;
    if (altitudeFt < _minAltitudeFt) _minAltitudeFt = altitudeFt;

    // ── 7. Distance + stopped time ───────────────────────────────────────────
    if (_lastPosition != null) {
      final double gap = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );

      if (clampedSpeedMph >= _stoppedThresholdMph && gap > 1.0) {
        _totalDistanceMeters += gap;
        _movingSpeedSum += smoothedSpeedMph;
        _movingPointsCount++;
        if (_stoppedStopwatch.isRunning) _stoppedStopwatch.stop();
      } else {
        if (!_stoppedStopwatch.isRunning) _stoppedStopwatch.start();
      }

      // ── 8. Altitude gain (jitter-filtered) ────────────────────────────────
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

    // ── 9. Build TripPoint ───────────────────────────────────────────────────
    final TripPoint point = TripPoint(
      position: smoothedPos,
      speedMph: smoothedSpeedMph,
      altitudeFt: altitudeFt,
      timestamp: pos.timestamp,
      accuracyMeters: pos.accuracy,
    );

    // ── 10. Smart storage (RAM guard) ────────────────────────────────────────
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
      _lastPosition = pos;
    }

    _lastEmittedPosition = pos;

    // ── 11. Emit to stream ───────────────────────────────────────────────────
    final StreamController<TripPoint>? ctrl = _pointController;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(point);
    }
  }

  // ── Kalman-lite smoother ───────────────────────────────────────────────────
  // A 1-D Kalman filter applied independently to lat and lng.
  // Reduces jitter while keeping latency low on fast movement.

  LatLng _kalmanSmooth(Position pos) {
    if (_smoothedLat == null || _smoothedLng == null) {
      _smoothedLat = pos.latitude;
      _smoothedLng = pos.longitude;
      _kalmanUncertainty = pos.accuracy;
      return LatLng(pos.latitude, pos.longitude);
    }

    // Predict step — uncertainty grows by process noise each update.
    _kalmanUncertainty += _kalmanProcessNoise;

    // Update step — Kalman gain blends prediction with measurement.
    final double measurementNoise = pos.accuracy * pos.accuracy;
    final double gain =
        _kalmanUncertainty / (_kalmanUncertainty + measurementNoise);

    _smoothedLat = _smoothedLat! + gain * (pos.latitude - _smoothedLat!);
    _smoothedLng = _smoothedLng! + gain * (pos.longitude - _smoothedLng!);
    _kalmanUncertainty = (1.0 - gain) * _kalmanUncertainty;

    return LatLng(_smoothedLat!, _smoothedLng!);
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
    _tripStartTime = null;
  }
}
