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

  double _maxAltitudeFt = -100000;
  double _minAltitudeFt = 100000;
  double? _lastValidAltitude;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  Stream<TripPoint>? get pointStream => _pointController?.stream;

  // CONSTANTS
  static const double _stoppedThresholdMph = 1.1; // Slightly more sensitive
  static const double _mpsToMph = 2.23694;
  static const double _metersToFeet = 3.28084;
  static const double _metersToMiles = 1609.34;
  static const double _altitudeJitterThreshold = 1.5; // Meters
  static const double _maxPlausibleSpeedMph = 240.0;
  static const double _minPointDistanceStorage = 3.0; // RAM optimization

  static double get _minAccuracyThreshold => kIsWeb ? 100.0 : 40.0;

  /// Fetches current position for weather/UI initialization
  Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await requestPermission();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint("GPS getCurrentLocation error: $e");
      // Faster fallback
      return await Geolocator.getLastKnownPosition();
    }
  }

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) return false;
    return (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always);
  }

  Future<void> startTracking() async {
    if (_isTracking) return;

    final hasPermission = await requestPermission();
    if (!hasPermission) return;

    _resetInternalState();
    _isTyping(true);
    _tripStopwatch.start();

    _pointController = StreamController<TripPoint>.broadcast();

    late final LocationSettings settings;

    if (kIsWeb) {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        distanceFilter: 1,
      );
    } else if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        intervalDuration: const Duration(seconds: 1),
        distanceFilter: 1,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Tracking your journey in real-time',
          notificationTitle: 'TrackPro AI Active',
          enableWakeLock: true,
        ),
      );
    } else {
      settings = const LocationSettings(accuracy: LocationAccuracy.high);
    }

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
            _handleNewPosition,
            onError: (e) => debugPrint("GPS Stream Error: $e"));
  }

  void _isTyping(bool val) => _isTracking = val;

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
    _maxAltitudeFt = -100000;
    _minAltitudeFt = 100000;
  }

  void _handleNewPosition(Position pos) {
    // 1. Filter out low accuracy "noise" (crucial for tunnels/city canyons)
    if (pos.accuracy > _minAccuracyThreshold) return;

    // 2. Speed Calculation
    double speedMps = pos.speed;

    // Fallback: If device doesn't report speed, calculate from Lat/Lng gap
    if (speedMps <= 0 && _lastPosition != null) {
      final double distMeters = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude);
      final double timeSecs =
          pos.timestamp.difference(_lastPosition!.timestamp).inMilliseconds /
              1000.0;
      if (timeSecs > 0) speedMps = distMeters / timeSecs;
    }

    final double speedMph = (speedMps < 0 ? 0.0 : speedMps) * _mpsToMph;

    // Ignore spikes that are physically impossible for driving
    if (speedMph > _maxPlausibleSpeedMph) return;

    final double altitudeFt = pos.altitude * _metersToFeet;

    // Peak Statistics Update
    if (speedMph > _maxSpeedMph) _maxSpeedMph = speedMph;
    if (altitudeFt > _maxAltitudeFt) _maxAltitudeFt = altitudeFt;
    if (altitudeFt < _minAltitudeFt) _minAltitudeFt = altitudeFt;

    if (_lastPosition != null) {
      final double gap = Geolocator.distanceBetween(_lastPosition!.latitude,
          _lastPosition!.longitude, pos.latitude, pos.longitude);

      // DRIFT SUPPRESSION: Only count movement if speed is above threshold
      // AND we have actually moved a meaningful distance.
      if (speedMph >= _stoppedThresholdMph && gap > 1.0) {
        _totalDistanceMeters += gap;
        _movingSpeedSum += speedMph;
        _movingPointsCount++;
        if (_stoppedStopwatch.isRunning) _stoppedStopwatch.stop();
      } else {
        if (!_stoppedStopwatch.isRunning) _stoppedStopwatch.start();
      }

      // Filtered Altitude Gain
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

    // 3. Smart Storage (RAM Optimization for long trips)
    final point = TripPoint(
      position: LatLng(pos.latitude, pos.longitude),
      speedMph: speedMph,
      altitudeFt: altitudeFt,
      timestamp: pos.timestamp,
      accuracyMeters: pos.accuracy,
    );

    bool shouldStore = _points.isEmpty;
    if (!shouldStore && _lastPosition != null) {
      final d = Geolocator.distanceBetween(_lastPosition!.latitude,
          _lastPosition!.longitude, pos.latitude, pos.longitude);

      // Optimization: Store if moved > 3m OR if heading changed significantly OR 10s passed
      final bool timeTrigger =
          pos.timestamp.difference(_points.last.timestamp).inSeconds >= 10;
      final bool distTrigger = d >= _minPointDistanceStorage;

      if (distTrigger || timeTrigger) {
        shouldStore = true;
      }
    }

    if (shouldStore) {
      _points.add(point);
      _lastPosition = pos;
    }

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

    if (_points.isEmpty) {
      _pointController?.close();
      return null;
    }

    final summary = TripSummary(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _points.first.timestamp,
      totalTime: _tripStopwatch.elapsed,
      stoppedTime: _stoppedStopwatch.elapsed,
      movingTime: _tripStopwatch.elapsed - _stoppedStopwatch.elapsed,
      maxSpeedMph: _maxSpeedMph,
      avgSpeedMph:
          _movingPointsCount == 0 ? 0.0 : _movingSpeedSum / _movingPointsCount,
      altitudeGainFt: _altitudeGainMeters * _metersToFeet,
      maxAltitudeFt: _maxAltitudeFt == -100000 ? 0 : _maxAltitudeFt,
      minAltitudeFt: _minAltitudeFt == 100000 ? 0 : _minAltitudeFt,
      distanceMiles: _totalDistanceMeters / _metersToMiles,
      points: List.unmodifiable(_points),
    );

    _pointController?.close();
    return summary;
  }

  // --- UI Data Accessors ---
  List<TripPoint> get currentPoints => UnmodifiableListView(_points);
  double get currentDistanceMiles => _totalDistanceMeters / _metersToMiles;
  double get currentMaxSpeedMph => _maxSpeedMph;
  double get currentAvgSpeedMph =>
      _movingPointsCount == 0 ? 0.0 : _movingSpeedSum / _movingPointsCount;
  Duration get currentTripTime => _tripStopwatch.elapsed;
  Duration get currentStoppedTime => _stoppedStopwatch.elapsed;

  void dispose() {
    _positionSubscription?.cancel();
    _pointController?.close();
  }
}
