import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/trip_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GPS SERVICE
// Bug fixes + performance improvements
// ─────────────────────────────────────────────────────────────────────────────

class GpsService {
  GpsService._internal();

  static final GpsService instance = GpsService._internal();

  StreamController<TripPoint>? _pointController;
  StreamSubscription<Position>? _positionSubscription;

  // ── Internal Data ──────────────────────────────────────────────────────────
  final List<TripPoint> _points = <TripPoint>[];
  final Stopwatch _tripStopwatch = Stopwatch();
  final Stopwatch _stoppedStopwatch = Stopwatch();

  Position? _lastRawPosition;
  LatLng? _lastStoredSmoothedPosition;
  LatLng? _lastEmittedSmoothedPosition;

  DateTime? _lastProcessedAt;
  double? _lastValidAltitudeMeters;

  double _totalDistanceMeters = 0.0;
  double _altitudeGainMeters = 0.0;
  double _maxSpeedMph = 0.0;
  double _movingSpeedSum = 0.0;
  int _movingPointsCount = 0;

  double _maxAltitudeFt = _emptyMaxAltitudeFt;
  double _minAltitudeFt = _emptyMinAltitudeFt;

  final List<double> _recentSpeeds = <double>[];

  double? _smoothedLat;
  double? _smoothedLng;
  double _kalmanUncertainty = _initialKalmanUncertaintyMeters;

  bool _isTracking = false;

  bool get isTracking => _isTracking;

  DateTime? _tripStartTime;

  DateTime? get tripStartTime => _tripStartTime;

  Stream<TripPoint>? get pointStream => _pointController?.stream;

  static const double _stoppedThresholdMph = 1.1;
  static const double _mpsToMph = 2.23694;
  static const double _metersToFeet = 3.28084;
  static const double _metersToMiles = 1609.34;

  static const double _altitudeJitterThresholdMeters = 1.5;
  static const double _maxPlausibleSpeedMph = 250.0;
  static const double _minPointDistanceStorageMeters = 3.0;

  static const int _minStorageIntervalSeconds = 10;
  static const int _minProcessIntervalMs = 200;
  static const int _speedSmoothingWindow = 4;

  static const double _emptyMaxAltitudeFt = -100000.0;
  static const double _emptyMinAltitudeFt = 100000.0;

  static const double _initialKalmanUncertaintyMeters = 15.0;
  static const double _kalmanProcessNoiseMeters = 3.0;

  static double get _minAccuracyThresholdMeters => kIsWeb ? 100.0 : 40.0;

  // ── Public Accessors ───────────────────────────────────────────────────────

  List<TripPoint> get currentPoints => UnmodifiableListView<TripPoint>(_points);

  double get currentDistanceMiles => _totalDistanceMeters / _metersToMiles;

  double get currentMaxSpeedMph => _maxSpeedMph;

  double get currentAvgSpeedMph {
    if (_movingPointsCount == 0) return 0.0;
    return _movingSpeedSum / _movingPointsCount;
  }

  Duration get currentTripTime => _tripStopwatch.elapsed;

  Duration get currentStoppedTime => _stoppedStopwatch.elapsed;

  Duration get currentMovingTime {
    final Duration moving = _tripStopwatch.elapsed - _stoppedStopwatch.elapsed;
    return moving.isNegative ? Duration.zero : moving;
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e, st) {
      debugPrint('GpsService.requestPermission error: $e\n$st');
      return false;
    }
  }

  // ── One-shot location ──────────────────────────────────────────────────────

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
    } catch (e, st) {
      debugPrint('GpsService.getCurrentLocation error: $e\n$st');

      try {
        return await Geolocator.getLastKnownPosition();
      } catch (lastKnownError, lastKnownStack) {
        debugPrint(
          'GpsService.getLastKnownPosition error: '
          '$lastKnownError\n$lastKnownStack',
        );
        return null;
      }
    }
  }

  // ── Tracking lifecycle ─────────────────────────────────────────────────────

  Future<void> startTracking() async {
    if (_isTracking) return;

    final bool ok = await requestPermission();
    if (!ok) return;

    await _safeCancelSubscription();
    await _safeCloseController();

    _resetInternalState();

    _pointController = StreamController<TripPoint>.broadcast();

    _isTracking = true;
    _tripStartTime = DateTime.now();
    _tripStopwatch.start();

    try {
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _buildLocationSettings(),
      ).listen(
        _handleNewPosition,
        onError: (Object e, StackTrace st) {
          debugPrint('GpsService stream error: $e\n$st');
        },
        cancelOnError: false,
      );
    } catch (e, st) {
      debugPrint('GpsService.startTracking error: $e\n$st');

      _isTracking = false;
      _tripStartTime = null;
      _tripStopwatch.stop();

      await _safeCancelSubscription();
      await _safeCloseController();
    }
  }

  TripSummary? stopTracking() {
    if (!_isTracking) return null;

    _isTracking = false;

    _tripStopwatch.stop();
    _stoppedStopwatch.stop();

    _safeCancelSubscription();

    if (_points.isEmpty) {
      _safeCloseController();
      _tripStartTime = null;
      return null;
    }

    final double maxAlt =
        _maxAltitudeFt == _emptyMaxAltitudeFt ? 0.0 : _maxAltitudeFt;
    final double minAlt =
        _minAltitudeFt == _emptyMinAltitudeFt ? 0.0 : _minAltitudeFt;

    final TripSummary summary = TripSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _points.first.timestamp,
      totalTime: _tripStopwatch.elapsed,
      stoppedTime: _stoppedStopwatch.elapsed,
      movingTime: currentMovingTime,
      maxSpeedMph: _maxSpeedMph,
      avgSpeedMph: currentAvgSpeedMph,
      altitudeGainFt: _altitudeGainMeters * _metersToFeet,
      maxAltitudeFt: maxAlt,
      minAltitudeFt: minAlt,
      distanceMiles: _totalDistanceMeters / _metersToMiles,
      points: List<TripPoint>.unmodifiable(_points),
    );

    _safeCloseController();
    _tripStartTime = null;

    return summary;
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  void _resetInternalState() {
    _points.clear();
    _recentSpeeds.clear();

    _tripStopwatch
      ..stop()
      ..reset();

    _stoppedStopwatch
      ..stop()
      ..reset();

    _lastRawPosition = null;
    _lastStoredSmoothedPosition = null;
    _lastEmittedSmoothedPosition = null;
    _lastProcessedAt = null;
    _lastValidAltitudeMeters = null;

    _smoothedLat = null;
    _smoothedLng = null;
    _kalmanUncertainty = _initialKalmanUncertaintyMeters;

    _totalDistanceMeters = 0.0;
    _altitudeGainMeters = 0.0;
    _maxSpeedMph = 0.0;
    _movingSpeedSum = 0.0;
    _movingPointsCount = 0;

    _maxAltitudeFt = _emptyMaxAltitudeFt;
    _minAltitudeFt = _emptyMinAltitudeFt;
  }

  // ── Location settings ──────────────────────────────────────────────────────

  LocationSettings _buildLocationSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          distanceFilter: 1,
        );

      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          intervalDuration: const Duration(milliseconds: 800),
          distanceFilter: 1,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'TrackPro AI Active',
            notificationText: 'Tracking your journey in real-time',
            enableWakeLock: true,
          ),
        );

      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        );
    }
  }

  // ── Core position handler ──────────────────────────────────────────────────

  void _handleNewPosition(Position pos) {
    if (!_isTracking) return;

    final DateTime now = DateTime.now();

    if (_lastProcessedAt != null) {
      final int elapsedMs = now.difference(_lastProcessedAt!).inMilliseconds;
      if (elapsedMs < _minProcessIntervalMs) return;
    }

    _lastProcessedAt = now;

    if (!_isUsablePosition(pos)) return;

    final LatLng smoothedPosition = _kalmanSmooth(pos);

    final double clampedSpeedMph = _calculateClampedSpeedMph(
      currentPosition: pos,
      currentSmoothedPosition: smoothedPosition,
    );

    final double smoothedSpeedMph = _smoothSpeed(clampedSpeedMph);
    final double altitudeFt = pos.altitude * _metersToFeet;

    _updatePeakStats(
      clampedSpeedMph: clampedSpeedMph,
      altitudeFt: altitudeFt,
    );

    _updateDistanceAndMovementStats(
      currentSmoothedPosition: smoothedPosition,
      smoothedSpeedMph: smoothedSpeedMph,
      clampedSpeedMph: clampedSpeedMph,
    );

    _updateAltitudeGain(pos.altitude);

    final TripPoint point = TripPoint(
      position: smoothedPosition,
      speedMph: smoothedSpeedMph,
      altitudeFt: altitudeFt,
      timestamp: pos.timestamp,
      accuracyMeters: pos.accuracy,
    );

    if (_shouldStorePoint(pos, smoothedPosition)) {
      _points.add(point);
      _lastStoredSmoothedPosition = smoothedPosition;
    }

    _lastRawPosition = pos;
    _lastEmittedSmoothedPosition = smoothedPosition;

    _emitPoint(point);
  }

  bool _isUsablePosition(Position pos) {
    if (pos.latitude.isNaN ||
        pos.longitude.isNaN ||
        pos.latitude.abs() > 90.0 ||
        pos.longitude.abs() > 180.0) {
      return false;
    }

    if (pos.accuracy.isNaN || pos.accuracy <= 0.0) {
      return false;
    }

    if (pos.accuracy > _minAccuracyThresholdMeters) {
      return false;
    }

    return true;
  }

  double _calculateClampedSpeedMph({
    required Position currentPosition,
    required LatLng currentSmoothedPosition,
  }) {
    double speedMps = currentPosition.speed.isNaN || currentPosition.speed < 0
        ? 0.0
        : currentPosition.speed;

    final Position? previousRaw = _lastRawPosition;
    final LatLng? previousSmoothed = _lastEmittedSmoothedPosition;

    if (speedMps <= 0.0 && previousRaw != null && previousSmoothed != null) {
      final int deltaMs = currentPosition.timestamp
          .difference(previousRaw.timestamp)
          .inMilliseconds;

      if (deltaMs > 100) {
        final double distanceMeters = Geolocator.distanceBetween(
          previousSmoothed.latitude,
          previousSmoothed.longitude,
          currentSmoothedPosition.latitude,
          currentSmoothedPosition.longitude,
        );

        speedMps = distanceMeters / (deltaMs / 1000.0);
      }
    }

    final double rawSpeedMph = speedMps * _mpsToMph;
    return rawSpeedMph.clamp(0.0, _maxPlausibleSpeedMph).toDouble();
  }

  double _smoothSpeed(double speedMph) {
    _recentSpeeds.add(speedMph);

    if (_recentSpeeds.length > _speedSmoothingWindow) {
      _recentSpeeds.removeAt(0);
    }

    double total = 0.0;
    for (final double speed in _recentSpeeds) {
      total += speed;
    }

    return total / _recentSpeeds.length;
  }

  void _updatePeakStats({
    required double clampedSpeedMph,
    required double altitudeFt,
  }) {
    if (clampedSpeedMph > _maxSpeedMph) {
      _maxSpeedMph = clampedSpeedMph;
    }

    if (altitudeFt.isFinite) {
      if (altitudeFt > _maxAltitudeFt) _maxAltitudeFt = altitudeFt;
      if (altitudeFt < _minAltitudeFt) _minAltitudeFt = altitudeFt;
    }
  }

  void _updateDistanceAndMovementStats({
    required LatLng currentSmoothedPosition,
    required double smoothedSpeedMph,
    required double clampedSpeedMph,
  }) {
    final LatLng? previousSmoothed = _lastEmittedSmoothedPosition;

    if (previousSmoothed == null) {
      if (!_stoppedStopwatch.isRunning) {
        _stoppedStopwatch.start();
      }
      return;
    }

    final double gapMeters = Geolocator.distanceBetween(
      previousSmoothed.latitude,
      previousSmoothed.longitude,
      currentSmoothedPosition.latitude,
      currentSmoothedPosition.longitude,
    );

    final bool isMoving =
        clampedSpeedMph >= _stoppedThresholdMph && gapMeters > 1.0;

    if (isMoving) {
      _totalDistanceMeters += gapMeters;
      _movingSpeedSum += smoothedSpeedMph;
      _movingPointsCount++;

      if (_stoppedStopwatch.isRunning) {
        _stoppedStopwatch.stop();
      }
    } else {
      if (!_stoppedStopwatch.isRunning) {
        _stoppedStopwatch.start();
      }
    }
  }

  void _updateAltitudeGain(double altitudeMeters) {
    if (!altitudeMeters.isFinite) return;

    if (_lastValidAltitudeMeters == null) {
      _lastValidAltitudeMeters = altitudeMeters;
      return;
    }

    final double diff = altitudeMeters - _lastValidAltitudeMeters!;

    if (diff.abs() > _altitudeJitterThresholdMeters) {
      if (diff > 0.0) {
        _altitudeGainMeters += diff;
      }

      _lastValidAltitudeMeters = altitudeMeters;
    }
  }

  bool _shouldStorePoint(Position pos, LatLng smoothedPosition) {
    if (_points.isEmpty) return true;

    final LatLng? previousStored = _lastStoredSmoothedPosition;
    if (previousStored == null) return true;

    final double distanceMeters = Geolocator.distanceBetween(
      previousStored.latitude,
      previousStored.longitude,
      smoothedPosition.latitude,
      smoothedPosition.longitude,
    );

    final bool distanceTrigger =
        distanceMeters >= _minPointDistanceStorageMeters;

    final bool timeTrigger =
        pos.timestamp.difference(_points.last.timestamp).inSeconds >=
            _minStorageIntervalSeconds;

    return distanceTrigger || timeTrigger;
  }

  void _emitPoint(TripPoint point) {
    final StreamController<TripPoint>? controller = _pointController;

    if (controller == null || controller.isClosed) return;

    try {
      controller.add(point);
    } catch (e, st) {
      debugPrint('GpsService._emitPoint error: $e\n$st');
    }
  }

  // ── Kalman-lite smoother ───────────────────────────────────────────────────

  LatLng _kalmanSmooth(Position pos) {
    if (_smoothedLat == null || _smoothedLng == null) {
      _smoothedLat = pos.latitude;
      _smoothedLng = pos.longitude;
      _kalmanUncertainty = pos.accuracy.clamp(1.0, 100.0).toDouble();

      return LatLng(pos.latitude, pos.longitude);
    }

    _kalmanUncertainty += _kalmanProcessNoiseMeters;

    final double accuracyMeters = pos.accuracy.clamp(1.0, 100.0).toDouble();
    final double measurementNoise = accuracyMeters * accuracyMeters;

    final double gain =
        _kalmanUncertainty / (_kalmanUncertainty + measurementNoise);

    _smoothedLat = _smoothedLat! + gain * (pos.latitude - _smoothedLat!);
    _smoothedLng = _smoothedLng! + gain * (pos.longitude - _smoothedLng!);

    _kalmanUncertainty = (1.0 - gain) * _kalmanUncertainty;

    return LatLng(_smoothedLat!, _smoothedLng!);
  }

  // ── Safe cleanup ───────────────────────────────────────────────────────────

  Future<void> _safeCancelSubscription() async {
    final StreamSubscription<Position>? sub = _positionSubscription;
    _positionSubscription = null;

    if (sub == null) return;

    try {
      await sub.cancel();
    } catch (e, st) {
      debugPrint('GpsService subscription cancel error: $e\n$st');
    }
  }

  Future<void> _safeCloseController() async {
    final StreamController<TripPoint>? controller = _pointController;
    _pointController = null;

    if (controller == null || controller.isClosed) return;

    try {
      await controller.close();
    } catch (e, st) {
      debugPrint('GpsService controller close error: $e\n$st');
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  void dispose() {
    _isTracking = false;

    _tripStopwatch.stop();
    _stoppedStopwatch.stop();

    _safeCancelSubscription();
    _safeCloseController();

    _tripStartTime = null;
  }
}
