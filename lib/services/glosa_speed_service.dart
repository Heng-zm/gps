import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

enum SignalPhase {
  green,
  yellow,
  red,
}

enum GlosaAdvisoryStatus {
  greenWaveOptimal,
  accelerateSlightly,
  decelerateAhead,
  unavoidableStop,
}

class GlosaIntersectionSnapshot {
  const GlosaIntersectionSnapshot({
    required this.intersectionName,
    required this.distanceMeters,
    required this.phase,
    required this.secondsRemaining,
    required this.recommendedSpeedKmh,
    required this.status,
    required this.fuelSavingsEstimatePercent,
    required this.timestamp,
  });

  final String intersectionName;
  final double distanceMeters;
  final SignalPhase phase;
  final int secondsRemaining;
  final double recommendedSpeedKmh;
  final GlosaAdvisoryStatus status;
  final int fuelSavingsEstimatePercent;
  final DateTime timestamp;

  static final GlosaIntersectionSnapshot idle = GlosaIntersectionSnapshot(
    intersectionName: 'Scanning V2I Infrastructure...',
    distanceMeters: 0.0,
    phase: SignalPhase.green,
    secondsRemaining: 0,
    recommendedSpeedKmh: 50.0,
    status: GlosaAdvisoryStatus.greenWaveOptimal,
    fuelSavingsEstimatePercent: 0,
    timestamp: DateTime.now(),
  );
}

/// Service managing V2I (Vehicle-to-Infrastructure) GLOSA
/// (Green Light Optimal Speed Advisory) synchronization.
class GlosaSpeedService {
  GlosaSpeedService._();
  static final GlosaSpeedService instance = GlosaSpeedService._();

  final ValueNotifier<bool> isActiveN = ValueNotifier<bool>(false);
  final ValueNotifier<GlosaIntersectionSnapshot> snapshotN =
      ValueNotifier<GlosaIntersectionSnapshot>(GlosaIntersectionSnapshot.idle);

  Timer? _v2iTimer;
  double _simDistance = 450.0;
  int _phaseSeconds = 16;
  SignalPhase _phase = SignalPhase.red;

  static const List<String> _kIntersections = <String>[
    'Monivong Blvd & Sihanouk Blvd',
    'Norodom Blvd & Mao Tse Toung',
    'Russian Blvd & Kampuchea Krom',
    'Hun Sen Blvd & 271 St',
  ];

  void startV2iSync({LatLng? userPos}) {
    if (isActiveN.value) return;
    isActiveN.value = true;

    _simDistance = 420.0;
    _phaseSeconds = 18;
    _phase = SignalPhase.red;

    _v2iTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      _simDistance -= 4.5;
      if (_simDistance <= 25.0) {
        // Reset to next intersection
        _simDistance = 500.0;
        _phase = SignalPhase.red;
        _phaseSeconds = 22;
      }

      _phaseSeconds--;
      if (_phaseSeconds <= 0) {
        if (_phase == SignalPhase.red) {
          _phase = SignalPhase.green;
          _phaseSeconds = 28;
        } else if (_phase == SignalPhase.green) {
          _phase = SignalPhase.yellow;
          _phaseSeconds = 4;
        } else {
          _phase = SignalPhase.red;
          _phaseSeconds = 22;
        }
      }

      _computeAdvisory();
    });
  }

  void _computeAdvisory() {
    double targetSpeedKmh = 45.0;
    GlosaAdvisoryStatus status = GlosaAdvisoryStatus.greenWaveOptimal;

    // Time until next green window
    final double timeToGreenSec = _phase == SignalPhase.red
        ? _phaseSeconds.toDouble()
        : 0.0;

    if (_phase == SignalPhase.red) {
      if (timeToGreenSec > 1.0) {
        // Calculate speed to arrive just as light turns green
        final double speedMps = _simDistance / timeToGreenSec;
        targetSpeedKmh = (speedMps * 3.6).clamp(25.0, 60.0);

        if (targetSpeedKmh > 55.0) {
          status = GlosaAdvisoryStatus.unavoidableStop;
        } else if (targetSpeedKmh < 32.0) {
          status = GlosaAdvisoryStatus.decelerateAhead;
        } else {
          status = GlosaAdvisoryStatus.greenWaveOptimal;
        }
      }
    } else if (_phase == SignalPhase.green) {
      final double timeRemainingSec = _phaseSeconds.toDouble();
      final double speedNeededMps = _simDistance / math.max(1.0, timeRemainingSec);
      final double speedNeededKmh = speedNeededMps * 3.6;

      if (speedNeededKmh <= 52.0) {
        targetSpeedKmh = speedNeededKmh.clamp(35.0, 52.0);
        status = GlosaAdvisoryStatus.greenWaveOptimal;
      } else {
        targetSpeedKmh = 35.0;
        status = GlosaAdvisoryStatus.decelerateAhead;
      }
    } else {
      // Yellow
      targetSpeedKmh = 30.0;
      status = GlosaAdvisoryStatus.decelerateAhead;
    }

    final int intersectionIdx =
        ((DateTime.now().minute ~/ 3) % _kIntersections.length);

    snapshotN.value = GlosaIntersectionSnapshot(
      intersectionName: _kIntersections[intersectionIdx],
      distanceMeters: _simDistance.clamp(0.0, 600.0),
      phase: _phase,
      secondsRemaining: _phaseSeconds,
      recommendedSpeedKmh: targetSpeedKmh,
      status: status,
      fuelSavingsEstimatePercent: status == GlosaAdvisoryStatus.greenWaveOptimal ? 28 : 12,
      timestamp: DateTime.now(),
    );
  }

  void stop() {
    _v2iTimer?.cancel();
    _v2iTimer = null;
    isActiveN.value = false;
    snapshotN.value = GlosaIntersectionSnapshot.idle;
  }
}
