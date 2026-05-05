import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_data.dart';

class GpsService {
  StreamController<TripPoint>? _pointController;
  StreamSubscription<Position>? _positionSubscription;

  // INTERNAL DATA
  final List<TripPoint> _points = [];
  final Stopwatch _tripStopwatch = Stopwatch();
  final Stopwatch _stoppedStopwatch = Stopwatch();

  Position? _lastPosition;

  double _totalDistanceMeters = 0;
  double _altitudeGainMeters = 0;
  double _maxSpeedMph = 0;
  double _movingSpeedSum = 0;
  int _movingPointsCount = 0;
  double _maxAltitudeFt = double.negativeInfinity;
  double _minAltitudeFt = double.infinity;
  double? _lastValidAltitude;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  Stream<TripPoint>? get pointStream => _pointController?.stream;

  // CONSTANTS FOR PRECISION
  static const double _stoppedThresholdMph =
      1.6; // Slightly raised for drift reduction
  static const double _mpsToMph = 2.23694;
  static const double _metersToFeet = 3.28084;
  static const double _metersToMiles = 1609.34;
  static const double _altitudeJitterThreshold =
      3.5; // Meters to ignore GPS altitude noise
  static const double _maxPlausibleSpeedMph = 250.0;

  static double get _minAccuracyThreshold => kIsWeb ? 100.0 : 35.0;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint("Location services are disabled.");
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return false;
    return (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always);
  }

  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint("Current position error: $e");
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _resetInternalState();
    _isTracking = true;
    _tripStopwatch.start();
    _pointController = StreamController<TripPoint>.broadcast();

    late final LocationSettings locationSettings;

    if (kIsWeb) {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Tracking your journey in the background',
          notificationTitle: 'GPS Tracker Pro Active',
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings =
          const LocationSettings(accuracy: LocationAccuracy.high);
    }

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
            _handleNewPosition,
            onError: (err) => debugPrint("GPS Stream Error: $err"));
  }

  void _resetInternalState() {
    _points.clear();
    _tripStopwatch.reset();
    _stoppedStopwatch.reset();
    _lastPosition = null;
    _lastValidAltitude = null;
    _totalDistanceMeters = 0;
    _altitudeGainMeters = 0;
    _maxSpeedMph = 0;
    _movingSpeedSum = 0;
    _movingPointsCount = 0;
    _maxAltitudeFt = double.negativeInfinity;
    _minAltitudeFt = double.infinity;
  }

  void _handleNewPosition(Position position) {
    // 1. Filter by Accuracy
    if (position.accuracy > _minAccuracyThreshold) return;

    // 2. Manual Speed Calculation Fallback (Fixes 0.0 speed on Web/Simulators)
    double speedMps = position.speed;
    if (speedMps <= 0 && _lastPosition != null) {
      final double distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      final double seconds = position.timestamp
              .difference(_lastPosition!.timestamp)
              .inMilliseconds /
          1000.0;

      if (seconds > 0 && distance > 0.5) {
        speedMps = distance / seconds;
      }
    }

    final double speedMph = (speedMps < 0 ? 0.0 : speedMps) * _mpsToMph;
    if (speedMph > _maxPlausibleSpeedMph) return;

    final double altitudeFt = position.altitude * _metersToFeet;

    // Update Peak Stats
    if (speedMph > _maxSpeedMph) _maxSpeedMph = speedMph;
    if (altitudeFt > _maxAltitudeFt) _maxAltitudeFt = altitudeFt;
    if (altitudeFt < _minAltitudeFt) _minAltitudeFt = altitudeFt;

    if (_lastPosition != null) {
      final double gapDistance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // Moving Logic: Filter out GPS drift while stationary
      if (speedMph >= _stoppedThresholdMph && gapDistance > 0.8) {
        _totalDistanceMeters += gapDistance;
        _movingSpeedSum += speedMph;
        _movingPointsCount++;
        if (_stoppedStopwatch.isRunning) _stoppedStopwatch.stop();
      } else {
        if (!_stoppedStopwatch.isRunning) _stoppedStopwatch.start();
      }

      // Altitude Gain calculation with jitter filtering
      final double altDiff =
          position.altitude - (_lastValidAltitude ?? position.altitude);
      if (altDiff.abs() > _altitudeJitterThreshold) {
        if (altDiff > 0) _altitudeGainMeters += altDiff;
        _lastValidAltitude = position.altitude;
      }
    }

    _lastPosition = position;

    final point = TripPoint(
      position: LatLng(position.latitude, position.longitude),
      speedMph: speedMph,
      altitudeFt: altitudeFt,
      timestamp: position.timestamp,
      accuracyMeters: position.accuracy,
    );

    _points.add(point);
    if (_pointController != null && !_pointController!.isClosed) {
      _pointController!.add(point);
    }
  }

  TripSummary? stopTracking() {
    if (!_isTracking) return null;
    _isTracking = false;

    _tripStopwatch.stop();
    _stoppedStopwatch.stop();
    _positionSubscription?.cancel();
    _pointController?.close();

    if (_points.isEmpty) return null;

    final totalTime = _tripStopwatch.elapsed;
    final stoppedTime = _stoppedStopwatch.elapsed;
    final movingTime = totalTime - stoppedTime;

    return TripSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _points.first.timestamp,
      totalTime: totalTime,
      stoppedTime: stoppedTime,
      movingTime: movingTime.isNegative ? Duration.zero : movingTime,
      maxSpeedMph: _maxSpeedMph,
      avgSpeedMph:
          _movingPointsCount == 0 ? 0.0 : _movingSpeedSum / _movingPointsCount,
      altitudeGainFt: _altitudeGainMeters * _metersToFeet,
      maxAltitudeFt:
          _maxAltitudeFt == double.negativeInfinity ? 0 : _maxAltitudeFt,
      minAltitudeFt: _minAltitudeFt == double.infinity ? 0 : _minAltitudeFt,
      distanceMiles: _totalDistanceMeters / _metersToMiles,
      points: List.unmodifiable(_points),
    );
  }

  // --- Optimized Getters ---

  /// Returns a high-performance view of points without copying memory
  List<TripPoint> get currentPoints => UnmodifiableListView(_points);

  double get currentDistanceMiles => _totalDistanceMeters / _metersToMiles;
  double get currentMaxSpeedMph => _maxSpd;
  double get currentAvgSpeedMph =>
      _movingPointsCount == 0 ? 0.0 : _movingSpeedSum / _movingPointsCount;
  Duration get currentStoppedTime => _stoppedStopwatch.elapsed;
  Duration get currentTripTime => _tripStopwatch.elapsed;

  double get _maxSpd => _maxSpeedMph; // Alias for internal consistency

  void dispose() {
    _positionSubscription?.cancel();
    _pointController?.close();
  }
}
