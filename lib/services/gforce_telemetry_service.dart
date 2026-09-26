import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Vehicle cornering & acceleration telemetry data point.
class GForceReading {
  const GForceReading({
    required this.lateralG,
    required this.longitudinalG,
    required this.verticalG,
    required this.totalG,
    required this.leanAngleDeg,
    required this.peakLateralG,
    required this.peakBrakingG,
    required this.peakAccelG,
    required this.timestamp,
  });

  /// Cornering G: positive = turning right, negative = turning left.
  final double lateralG;

  /// Acceleration/Braking G: positive = accelerating, negative = braking.
  final double longitudinalG;

  /// Vertical G (bumps/dips): ~1.0G is normal earth gravity.
  final double verticalG;

  /// Combined planar G force magnitude.
  final double totalG;

  /// Estimated bike/vehicle lean angle in degrees (-90 to +90).
  final double leanAngleDeg;

  /// Peak lateral G achieved during session.
  final double peakLateralG;

  /// Peak braking G achieved during session.
  final double peakBrakingG;

  /// Peak acceleration G achieved during session.
  final double peakAccelG;

  final DateTime timestamp;

  static const GForceReading zero = GForceReading(
    lateralG: 0.0,
    longitudinalG: 0.0,
    verticalG: 1.0,
    totalG: 0.0,
    leanAngleDeg: 0.0,
    peakLateralG: 0.0,
    peakBrakingG: 0.0,
    peakAccelG: 0.0,
    timestamp: null ?? _kZeroTime,
  );

  static final DateTime _kZeroTime = DateTime(2026, 1, 1);
}

/// Service that captures device accelerometer & gyroscope to compute
/// live G-Forces, cornering limits, and bike lean angles.
class GForceTelemetryService {
  GForceTelemetryService._();
  static final GForceTelemetryService instance = GForceTelemetryService._();

  final ValueNotifier<GForceReading> readingN =
      ValueNotifier<GForceReading>(GForceReading.zero);

  StreamSubscription<UserAccelerometerEvent>? _userAccelSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double _peakLat = 0.0;
  double _peakBrake = 0.0;
  double _peakAccel = 0.0;

  // Smoothing filters (Low-Pass Filter)
  double _smoothLat = 0.0;
  double _smoothLong = 0.0;
  double _smoothVert = 1.0;
  double _smoothLean = 0.0;

  bool _active = false;
  bool get isActive => _active;

  static const double _kEarthG = 9.80665;
  static const double _kAlpha = 0.22; // Low-pass filter factor

  void start() {
    if (_active) return;
    _active = true;

    // Use UserAccelerometer (removes earth gravity automatically)
    try {
      _userAccelSub = userAccelerometerEventStream().listen(
        _onUserAccel,
        onError: (Object err) => debugPrint('UserAccel error: $err'),
      );
    } catch (_) {
      // Fallback to standard accelerometer
      _accelSub = accelerometerEventStream().listen(_onStandardAccel);
    }
  }

  void stop() {
    _active = false;
    _userAccelSub?.cancel();
    _userAccelSub = null;
    _accelSub?.cancel();
    _accelSub = null;
  }

  void resetPeaks() {
    _peakLat = 0.0;
    _peakBrake = 0.0;
    _peakAccel = 0.0;
    readingN.value = GForceReading(
      lateralG: _smoothLat,
      longitudinalG: _smoothLong,
      verticalG: _smoothVert,
      totalG: math.sqrt(_smoothLat * _smoothLat + _smoothLong * _smoothLong),
      leanAngleDeg: _smoothLean,
      peakLateralG: 0.0,
      peakBrakingG: 0.0,
      peakAccelG: 0.0,
      timestamp: DateTime.now(),
    );
  }

  void _onUserAccel(UserAccelerometerEvent event) {
    // Coordinate mapping (Portrait mount):
    // X-axis: lateral acceleration (turning)
    // Y-axis: longitudinal acceleration (braking/acceleration)
    // Z-axis: vertical acceleration
    final double rawLat = (-event.x / _kEarthG).clamp(-3.5, 3.5);
    final double rawLong = (event.y / _kEarthG).clamp(-3.5, 3.5);
    final double rawVert = (event.z / _kEarthG).clamp(-2.0, 4.0) + 1.0;

    _smoothLat = _smoothLat + _kAlpha * (rawLat - _smoothLat);
    _smoothLong = _smoothLong + _kAlpha * (rawLong - _smoothLong);
    _smoothVert = _smoothVert + _kAlpha * (rawVert - _smoothVert);

    // Lean angle estimation: atan2(lateralG, verticalG)
    final double rawLean =
        math.atan2(_smoothLat, math.max(0.2, _smoothVert)) * (180.0 / math.pi);
    _smoothLean = _smoothLean + 0.18 * (rawLean - _smoothLean);

    final double totalPlanarG =
        math.sqrt(_smoothLat * _smoothLat + _smoothLong * _smoothLong);

    // Track peaks
    final double absLat = _smoothLat.abs();
    if (absLat > _peakLat) _peakLat = absLat;
    if (_smoothLong < -0.1 && _smoothLong.abs() > _peakBrake) {
      _peakBrake = _smoothLong.abs();
    }
    if (_smoothLong > 0.1 && _smoothLong > _peakAccel) {
      _peakAccel = _smoothLong;
    }

    readingN.value = GForceReading(
      lateralG: _smoothLat,
      longitudinalG: _smoothLong,
      verticalG: _smoothVert,
      totalG: totalPlanarG,
      leanAngleDeg: _smoothLean.clamp(-75.0, 75.0),
      peakLateralG: _peakLat,
      peakBrakingG: _peakBrake,
      peakAccelG: _peakAccel,
      timestamp: DateTime.now(),
    );
  }

  void _onStandardAccel(AccelerometerEvent event) {
    // Fallback simple gravity estimation
    final double rawLat = (-event.x / _kEarthG).clamp(-3.0, 3.0);
    final double rawLong = ((event.y - _kEarthG) / _kEarthG).clamp(-3.0, 3.0);

    _smoothLat = _smoothLat + _kAlpha * (rawLat - _smoothLat);
    _smoothLong = _smoothLong + _kAlpha * (rawLong - _smoothLong);

    readingN.value = GForceReading(
      lateralG: _smoothLat,
      longitudinalG: _smoothLong,
      verticalG: 1.0,
      totalG: math.sqrt(_smoothLat * _smoothLat + _smoothLong * _smoothLong),
      leanAngleDeg: _smoothLat * 45.0,
      peakLateralG: math.max(_peakLat, _smoothLat.abs()),
      peakBrakingG: _peakBrake,
      peakAccelG: _peakAccel,
      timestamp: DateTime.now(),
    );
  }
}
