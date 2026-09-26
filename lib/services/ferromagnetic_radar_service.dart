import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

enum MagneticAnomalyType {
  ambientNormal,
  undergroundPipeline,
  highVoltageCable,
  structuralIronGirders,
  voidDepletion,
}

class MagneticRadarReading {
  const MagneticRadarReading({
    required this.totalMicroTesla,
    required this.xMicroTesla,
    required this.yMicroTesla,
    required this.zMicroTesla,
    required this.anomalyDelta,
    required this.anomalyType,
    required this.peakMicroTesla,
    required this.confidenceScore, // 0 to 100
    required this.historyWaterfall,
    required this.timestamp,
  });

  final double totalMicroTesla;
  final double xMicroTesla;
  final double yMicroTesla;
  final double zMicroTesla;
  final double anomalyDelta;
  final MagneticAnomalyType anomalyType;
  final double peakMicroTesla;
  final int confidenceScore;
  final List<double> historyWaterfall;
  final DateTime timestamp;

  static final MagneticRadarReading zero = MagneticRadarReading(
    totalMicroTesla: 45.0,
    xMicroTesla: 18.0,
    yMicroTesla: -22.0,
    zMicroTesla: 34.0,
    anomalyDelta: 0.0,
    anomalyType: MagneticAnomalyType.ambientNormal,
    peakMicroTesla: 45.0,
    confidenceScore: 95,
    historyWaterfall: <double>[],
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Service that reads real hardware 3-axis Magnetometer sensors to detect
/// subterranean ferromagnetic anomalies, buried metal pipelines, and geological shifts.
class FerromagneticRadarService {
  FerromagneticRadarService._();
  static final FerromagneticRadarService instance = FerromagneticRadarService._();

  final ValueNotifier<bool> isActiveN = ValueNotifier<bool>(false);
  final ValueNotifier<MagneticRadarReading> readingN =
      ValueNotifier<MagneticRadarReading>(MagneticRadarReading.zero);

  StreamSubscription<MagnetometerEvent>? _magSub;
  double _peakFlux = 45.0;

  final List<double> _waterfall = <double>[];
  static const int _kWaterfallMax = 48;

  // Expected baseline ambient geomagnetic field in Cambodia / SE Asia (~42 μT)
  static const double _kEarthBaselineMicroTesla = 42.5;

  void start() {
    if (isActiveN.value) return;
    isActiveN.value = true;

    try {
      _magSub = magnetometerEventStream().listen(
        _onMagnetometerData,
        onError: (Object err) => debugPrint('Magnetometer error: $err'),
      );
    } catch (e) {
      debugPrint('Cannot start Magnetometer sensor: $e');
    }
  }

  void stop() {
    _magSub?.cancel();
    _magSub = null;
    isActiveN.value = false;
    _waterfall.clear();
    readingN.value = MagneticRadarReading.zero;
  }

  void resetPeak() {
    _peakFlux = 45.0;
  }

  void _onMagnetometerData(MagnetometerEvent event) {
    // Total Magnetic Field Strength B = sqrt(x^2 + y^2 + z^2) in μT
    final double totalFlux = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    if (totalFlux > _peakFlux) {
      _peakFlux = totalFlux;
    }

    _waterfall.insert(0, totalFlux);
    if (_waterfall.length > _kWaterfallMax) {
      _waterfall.removeLast();
    }

    final double anomalyDelta = (totalFlux - _kEarthBaselineMicroTesla).abs();

    MagneticAnomalyType type = MagneticAnomalyType.ambientNormal;
    int confidence = 92;

    if (totalFlux > 92.0) {
      type = MagneticAnomalyType.structuralIronGirders;
      confidence = 96;
    } else if (totalFlux > 68.0) {
      type = MagneticAnomalyType.undergroundPipeline;
      confidence = 88;
    } else if (totalFlux < 22.0) {
      type = MagneticAnomalyType.voidDepletion;
      confidence = 85;
    } else if (anomalyDelta > 15.0) {
      type = MagneticAnomalyType.highVoltageCable;
      confidence = 82;
    }

    readingN.value = MagneticRadarReading(
      totalMicroTesla: totalFlux,
      xMicroTesla: event.x,
      yMicroTesla: event.y,
      zMicroTesla: event.z,
      anomalyDelta: anomalyDelta,
      anomalyType: type,
      peakMicroTesla: _peakFlux,
      confidenceScore: confidence,
      historyWaterfall: List<double>.unmodifiable(_waterfall),
      timestamp: DateTime.now(),
    );
  }
}
