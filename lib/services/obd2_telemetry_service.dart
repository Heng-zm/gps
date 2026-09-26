import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

enum Obd2ConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  simulating,
}

class Obd2DtcFault {
  const Obd2DtcFault({
    required this.code,
    required this.descriptionEn,
    required this.descriptionKm,
    required this.severity,
  });

  final String code;
  final String descriptionEn;
  final String descriptionKm;
  final String severity; // Low, Medium, High
}

class Obd2TelemetrySnapshot {
  const Obd2TelemetrySnapshot({
    required this.rpm,
    required this.speedKmh,
    required this.coolantTempC,
    required this.engineLoadPercent,
    required this.throttlePercent,
    required this.turboBoostBar,
    required this.gear,
    required this.faults,
    required this.fuelEconomyL100km,
    required this.batteryVoltage,
  });

  final int rpm;
  final double speedKmh;
  final int coolantTempC;
  final double engineLoadPercent;
  final double throttlePercent;
  final double turboBoostBar;
  final int gear;
  final List<Obd2DtcFault> faults;
  final double fuelEconomyL100km;
  final double batteryVoltage;

  static const Obd2TelemetrySnapshot idle = Obd2TelemetrySnapshot(
    rpm: 0,
    speedKmh: 0.0,
    coolantTempC: 88,
    engineLoadPercent: 0.0,
    throttlePercent: 0.0,
    turboBoostBar: 0.0,
    gear: 0,
    faults: <Obd2DtcFault>[],
    fuelEconomyL100km: 0.0,
    batteryVoltage: 12.6,
  );
}

/// Service managing OBD-II ELM327 Bluetooth/WiFi ECU Telemetry
class Obd2TelemetryService {
  Obd2TelemetryService._();
  static final Obd2TelemetryService instance = Obd2TelemetryService._();

  final ValueNotifier<Obd2ConnectionState> stateN =
      ValueNotifier<Obd2ConnectionState>(Obd2ConnectionState.disconnected);

  final ValueNotifier<Obd2TelemetrySnapshot> snapshotN =
      ValueNotifier<Obd2TelemetrySnapshot>(Obd2TelemetrySnapshot.idle);

  Timer? _simTimer;
  double _simT = 0.0;

  static const List<Obd2DtcFault> _kSampleFaults = <Obd2DtcFault>[
    Obd2DtcFault(
      code: 'P0420',
      descriptionEn: 'Catalytic Converter System Efficiency Below Threshold (Bank 1)',
      descriptionKm: 'ប្រសិទ្ធភាពប្រព័ន្ធបំលែងផ្សែងពុលទាបជាងកម្រិតស្តង់ដារ',
      severity: 'Medium',
    ),
    Obd2DtcFault(
      code: 'P0171',
      descriptionEn: 'System Too Lean (Bank 1) — Fuel trim running low',
      descriptionKm: 'ល្បាយសាំងស្តើងខ្វះសាំងក្នុងបន្ទប់ចំហេះ (ខ្យល់ច្រើនជាងសាំង)',
      severity: 'Medium',
    ),
  ];

  void startSimulation() {
    stop();
    stateN.value = Obd2ConnectionState.simulating;

    _simTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _simT += 0.15;

      // Realistic engine simulation: accelerating through gears 1 to 5
      final double cycle = (_simT % 24.0);
      int gear = 1;
      double speed = 0.0;
      double rawRpm = 850.0;
      double throttle = 12.0;
      double load = 18.0;
      double boost = 0.0;

      if (cycle < 4.0) {
        gear = 1;
        throttle = 45.0;
        speed = cycle * 8.0;
        rawRpm = 1000 + cycle * 950;
        boost = 0.45;
        load = 55.0;
      } else if (cycle < 9.0) {
        gear = 2;
        throttle = 60.0;
        speed = 32.0 + (cycle - 4.0) * 8.5;
        rawRpm = 2200 + (cycle - 4.0) * 750;
        boost = 0.95;
        load = 68.0;
      } else if (cycle < 15.0) {
        gear = 3;
        throttle = 50.0;
        speed = 74.0 + (cycle - 9.0) * 6.0;
        rawRpm = 2600 + (cycle - 9.0) * 550;
        boost = 0.82;
        load = 62.0;
      } else if (cycle < 20.0) {
        gear = 4;
        throttle = 35.0;
        speed = 110.0 + (cycle - 15.0) * 3.0;
        rawRpm = 2800 + (cycle - 15.0) * 250;
        boost = 0.40;
        load = 45.0;
      } else {
        // Cruising & coasting
        gear = 5;
        throttle = 18.0;
        speed = 125.0 - (cycle - 20.0) * 4.0;
        rawRpm = 2200 - (cycle - 20.0) * 120;
        boost = 0.05;
        load = 28.0;
      }

      final double fuelEcon = (speed > 10.0)
          ? (load * 0.12 + 2.5) + math.sin(_simT) * 0.4
          : 0.0;

      snapshotN.value = Obd2TelemetrySnapshot(
        rpm: rawRpm.round().clamp(750, 7800),
        speedKmh: speed.clamp(0.0, 220.0),
        coolantTempC: 91 + (math.sin(_simT * 0.1) * 2).round(),
        engineLoadPercent: load.clamp(5.0, 100.0),
        throttlePercent: throttle.clamp(0.0, 100.0),
        turboBoostBar: boost.clamp(0.0, 1.8),
        gear: gear,
        faults: _kSampleFaults,
        fuelEconomyL100km: fuelEcon.clamp(4.2, 18.5),
        batteryVoltage: 13.9 + math.sin(_simT * 0.5) * 0.1,
      );
    });
  }

  void stop() {
    _simTimer?.cancel();
    _simTimer = null;
    stateN.value = Obd2ConnectionState.disconnected;
    snapshotN.value = Obd2TelemetrySnapshot.idle;
  }

  void clearDtcCodes() {
    final Obd2TelemetrySnapshot current = snapshotN.value;
    snapshotN.value = Obd2TelemetrySnapshot(
      rpm: current.rpm,
      speedKmh: current.speedKmh,
      coolantTempC: current.coolantTempC,
      engineLoadPercent: current.engineLoadPercent,
      throttlePercent: current.throttlePercent,
      turboBoostBar: current.turboBoostBar,
      gear: current.gear,
      faults: const <Obd2DtcFault>[],
      fuelEconomyL100km: current.fuelEconomyL100km,
      batteryVoltage: current.batteryVoltage,
    );
  }
}
