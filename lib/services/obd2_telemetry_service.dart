import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

enum Obd2ConnectionState {
  disconnected,
  connecting,
  connected,
  simulating,
  error,
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

  Obd2TelemetrySnapshot copyWith({
    int? rpm,
    double? speedKmh,
    int? coolantTempC,
    double? engineLoadPercent,
    double? throttlePercent,
    double? turboBoostBar,
    int? gear,
    List<Obd2DtcFault>? faults,
    double? fuelEconomyL100km,
    double? batteryVoltage,
  }) {
    return Obd2TelemetrySnapshot(
      rpm: rpm ?? this.rpm,
      speedKmh: speedKmh ?? this.speedKmh,
      coolantTempC: coolantTempC ?? this.coolantTempC,
      engineLoadPercent: engineLoadPercent ?? this.engineLoadPercent,
      throttlePercent: throttlePercent ?? this.throttlePercent,
      turboBoostBar: turboBoostBar ?? this.turboBoostBar,
      gear: gear ?? this.gear,
      faults: faults ?? this.faults,
      fuelEconomyL100km: fuelEconomyL100km ?? this.fuelEconomyL100km,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
    );
  }
}

/// Real OBD-II ELM327 Socket & Bluetooth Engine Telemetry Service.
///
/// Connects to real hardware ELM327 Wi-Fi / IP adapters (default: 192.168.0.10:35000),
/// performs standard AT initialization, parses real OBD-II hex responses,
/// calculates live RPM, boost, load, coolant, and reads DTC fault codes.
class Obd2TelemetryService {
  Obd2TelemetryService._();
  static final Obd2TelemetryService instance = Obd2TelemetryService._();

  final ValueNotifier<Obd2ConnectionState> stateN =
      ValueNotifier<Obd2ConnectionState>(Obd2ConnectionState.disconnected);

  final ValueNotifier<Obd2TelemetrySnapshot> snapshotN =
      ValueNotifier<Obd2TelemetrySnapshot>(Obd2TelemetrySnapshot.idle);

  final ValueNotifier<String> statusMessageN =
      ValueNotifier<String>('Disconnected from vehicle');

  Socket? _socket;
  StreamSubscription<List<int>>? _socketSub;
  Timer? _pollTimer;
  Timer? _simTimer;
  double _simT = 0.0;

  String _host = '192.168.0.10';
  int _port = 35000;
  String get host => _host;
  int get port => _port;

  final StringBuffer _rxBuffer = StringBuffer();
  Completer<String>? _pendingResponse;

  static const Map<String, (String, String, String)> _kKnownDtcMap =
      <String, (String, String, String)>{
    'P0300': (
      'Random/Multiple Cylinder Misfire Detected',
      'ម៉ាស៊ីនផ្ទុះខុសចង្វាក់លើស៊ីឡាំងច្រើន (Misfire)',
      'High'
    ),
    'P0420': (
      'Catalytic Converter System Efficiency Below Threshold (Bank 1)',
      'ប្រសិទ្ធភាពប្រព័ន្ធបំលែងផ្សែងពុលទាបជាងស្តង់ដារ',
      'Medium'
    ),
    'P0171': (
      'System Too Lean (Bank 1) — Fuel trim running low',
      'ល្បាយសាំងស្តើងខ្វះសាំងក្នុងបន្ទប់ចំហេះ (ខ្យល់ច្រើនជាងសាំង)',
      'Medium'
    ),
    'P0113': (
      'Intake Air Temperature Sensor 1 Circuit High',
      'សេនស័រសីតុណ្ហភាពខ្យល់ចូលម៉ាស៊ីន (IAT) មានតង់ស្យុងខ្ពស់',
      'Low'
    ),
    'P0128': (
      'Coolant Thermostat (Coolant Temp Below Regulating Temp)',
      'វ៉ានទឹកម៉ាស៊ីន (Thermostat) បើកចោល ធ្វើឱ្យទឹកមិនគ្រប់កម្តៅ',
      'Low'
    ),
  };

  /// Connect to real ELM327 Wi-Fi adapter at [host]:[port]
  Future<bool> connectReal({String host = '192.168.0.10', int port = 35000}) async {
    stop();
    _host = host.trim();
    _port = port;

    if (kIsWeb) {
      statusMessageN.value = 'Raw TCP Sockets not supported on Web. Use Live Demo.';
      stateN.value = Obd2ConnectionState.error;
      return false;
    }

    stateN.value = Obd2ConnectionState.connecting;
    statusMessageN.value = 'Connecting to ELM327 at $_host:$_port...';

    try {
      _socket = await Socket.connect(_host, _port, timeout: const Duration(seconds: 4));
      _socketSub = _socket!.listen(
        _onSocketData,
        onError: (Object error) {
          debugPrint('OBD-II Socket error: $error');
          _handleDisconnect(error.toString());
        },
        onDone: () => _handleDisconnect('Device disconnected'),
      );

      // Perform real ELM327 AT handshake
      statusMessageN.value = 'Initializing ELM327 protocol...';
      await _sendCommand('AT Z\r'); // Reset
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _sendCommand('AT E0\r'); // Echo off
      await _sendCommand('AT L0\r'); // Linefeeds off
      await _sendCommand('AT SP 0\r'); // Auto protocol

      stateN.value = Obd2ConnectionState.connected;
      statusMessageN.value = 'Connected to vehicle ECU ($_host)';

      // Start live PID polling loop (every 220ms)
      _startLivePolling();
      // Scan for stored DTC trouble codes
      unawaited(scanDtcCodes());

      return true;
    } catch (e) {
      debugPrint('OBD-II connection failed: $e');
      _handleDisconnect('Cannot connect to $_host:$_port. Ensure Wi-Fi adapter is plugged in.');
      return false;
    }
  }

  void _startLivePolling() {
    _pollTimer?.cancel();
    int cycle = 0;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 220), (_) async {
      if (stateN.value != Obd2ConnectionState.connected) return;

      cycle++;
      try {
        // Query RPM (010C)
        final String rpmResp = await _sendCommand('010C\r');
        final int? rpm = _parseRpm(rpmResp);

        // Query Speed (010D)
        final String speedResp = await _sendCommand('010D\r');
        final double? speed = _parseSpeed(speedResp);

        // Interleaved queries
        int? coolant;
        double? load;
        double? boost;
        double? throttle;

        if (cycle % 4 == 0) {
          final String coolantResp = await _sendCommand('0105\r');
          coolant = _parseCoolant(coolantResp);
        }
        if (cycle % 4 == 1) {
          final String loadResp = await _sendCommand('0104\r');
          load = _parsePercentage(loadResp);
        }
        if (cycle % 4 == 2) {
          final String throttleResp = await _sendCommand('0111\r');
          throttle = _parsePercentage(throttleResp);
        }
        if (cycle % 4 == 3) {
          final String mapResp = await _sendCommand('010B\r');
          boost = _parseBoost(mapResp);
        }

        final Obd2TelemetrySnapshot cur = snapshotN.value;
        final int resolvedRpm = rpm ?? cur.rpm;
        final double resolvedSpeed = speed ?? cur.speedKmh;

        // Estimate current gear from RPM and Speed
        final int gear = _estimateGear(resolvedSpeed, resolvedRpm);

        snapshotN.value = cur.copyWith(
          rpm: resolvedRpm,
          speedKmh: resolvedSpeed,
          coolantTempC: coolant ?? cur.coolantTempC,
          engineLoadPercent: load ?? cur.engineLoadPercent,
          throttlePercent: throttle ?? cur.throttlePercent,
          turboBoostBar: boost ?? cur.turboBoostBar,
          gear: gear,
          batteryVoltage: 13.8 + (resolvedRpm > 1000 ? 0.4 : 0.0),
        );
      } catch (err) {
        debugPrint('OBD PID polling cycle error: $err');
      }
    });
  }

  Future<String> _sendCommand(String cmd) async {
    if (_socket == null) return '';
    _pendingResponse = Completer<String>();
    _rxBuffer.clear();

    _socket!.write(cmd);
    await _socket!.flush();

    try {
      return await _pendingResponse!.future.timeout(const Duration(milliseconds: 750));
    } catch (_) {
      return '';
    }
  }

  void _onSocketData(List<int> data) {
    final String text = ascii.decode(data, allowInvalid: true);
    _rxBuffer.write(text);

    // Standard ELM327 ends responses with '>' prompt
    if (text.contains('>')) {
      final String response = _rxBuffer.toString();
      if (_pendingResponse != null && !_pendingResponse!.isCompleted) {
        _pendingResponse!.complete(response);
      }
    }
  }

  void _handleDisconnect(String message) {
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
    _pollTimer?.cancel();
    _pollTimer = null;

    if (stateN.value != Obd2ConnectionState.simulating) {
      stateN.value = Obd2ConnectionState.disconnected;
      statusMessageN.value = message;
    }
  }

  /// Scan for real Diagnostic Trouble Codes (Mode 03)
  Future<List<Obd2DtcFault>> scanDtcCodes() async {
    if (stateN.value != Obd2ConnectionState.connected) {
      return snapshotN.value.faults;
    }

    try {
      final String resp = await _sendCommand('03\r');
      final List<Obd2DtcFault> parsed = _parseDtcResponse(resp);
      snapshotN.value = snapshotN.value.copyWith(faults: parsed);
      return parsed;
    } catch (e) {
      debugPrint('DTC scan error: $e');
      return <Obd2DtcFault>[];
    }
  }

  /// Clear real DTC codes from ECU (Mode 04)
  Future<bool> clearDtcCodes() async {
    if (stateN.value == Obd2ConnectionState.simulating) {
      snapshotN.value = snapshotN.value.copyWith(faults: const <Obd2DtcFault>[]);
      return true;
    }

    if (stateN.value != Obd2ConnectionState.connected) return false;

    try {
      await _sendCommand('04\r');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      snapshotN.value = snapshotN.value.copyWith(faults: const <Obd2DtcFault>[]);
      statusMessageN.value = 'Diagnostic trouble codes cleared from ECU.';
      return true;
    } catch (e) {
      debugPrint('Failed to clear DTCs: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // OBD-II RESPONSE PARSERS
  // ═══════════════════════════════════════════════════════════════════════════════

  int? _parseRpm(String raw) {
    final List<int> bytes = _extractHexBytes(raw, '41 0C');
    if (bytes.length >= 2) {
      return ((bytes[0] * 256) + bytes[1]) ~/ 4;
    }
    return null;
  }

  double? _parseSpeed(String raw) {
    final List<int> bytes = _extractHexBytes(raw, '41 0D');
    if (bytes.isNotEmpty) {
      return bytes[0].toDouble();
    }
    return null;
  }

  int? _parseCoolant(String raw) {
    final List<int> bytes = _extractHexBytes(raw, '41 05');
    if (bytes.isNotEmpty) {
      return bytes[0] - 40;
    }
    return null;
  }

  double? _parsePercentage(String raw) {
    // Used for Load (41 04) and Throttle (41 11)
    final List<String> parts = raw.replaceAll(RegExp(r'\s+'), '').split(RegExp(r'41(04|11)'));
    if (parts.length > 1 && parts[1].length >= 2) {
      final int? val = int.tryParse(parts[1].substring(0, 2), radix: 16);
      if (val != null) {
        return (val * 100.0) / 255.0;
      }
    }
    return null;
  }

  double? _parseBoost(String raw) {
    // Intake Manifold Absolute Pressure (41 0B): kPa
    final List<int> bytes = _extractHexBytes(raw, '41 0B');
    if (bytes.isNotEmpty) {
      final double mapKpa = bytes[0].toDouble();
      const double atmosphericKpa = 101.3;
      return math.max(0.0, (mapKpa - atmosphericKpa) / 100.0);
    }
    return null;
  }

  List<Obd2DtcFault> _parseDtcResponse(String raw) {
    final List<Obd2DtcFault> faults = <Obd2DtcFault>[];
    final String clean = raw.replaceAll(RegExp(r'[\r\n\s>]'), '');
    final int idx = clean.indexOf('43');
    if (idx == -1) return faults;

    final String hexPayload = clean.substring(idx + 2);
    for (int i = 0; i + 4 <= hexPayload.length; i += 4) {
      final String codeHex = hexPayload.substring(i, i + 4);
      if (codeHex == '0000') continue;

      final int? firstByte = int.tryParse(codeHex.substring(0, 2), radix: 16);
      if (firstByte == null) continue;

      // First 2 bits determine system
      final int system = (firstByte >> 6) & 0x03;
      final String prefix = system == 0
          ? 'P'
          : system == 1
              ? 'C'
              : system == 2
                  ? 'B'
                  : 'U';

      final String dtc = '$prefix${(firstByte & 0x3F).toRadixString(16).padLeft(2, '0')}${codeHex.substring(2)}'.toUpperCase();

      final (String, String, String) info = _kKnownDtcMap[dtc] ??
          (
            'Vehicle Diagnostic Fault Code $dtc',
            'កូដបញ្ហាប្រព័ន្ធរថយន្ត $dtc',
            'Medium'
          );

      faults.add(
        Obd2DtcFault(
          code: dtc,
          descriptionEn: info.$1,
          descriptionKm: info.$2,
          severity: info.$3,
        ),
      );
    }

    return faults;
  }

  List<int> _extractHexBytes(String raw, String prefix) {
    final String clean = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final String cleanPrefix = prefix.replaceAll(' ', '').toUpperCase();
    final int idx = clean.indexOf(cleanPrefix);
    if (idx == -1) return const <int>[];

    final String hexStr = clean.substring(idx + cleanPrefix.length);
    final List<int> bytes = <int>[];
    for (int i = 0; i + 2 <= hexStr.length; i += 2) {
      final int? b = int.tryParse(hexStr.substring(i, i + 2), radix: 16);
      if (b != null) {
        bytes.add(b);
      } else {
        break;
      }
    }
    return bytes;
  }

  static int _estimateGear(double speedKmh, int rpm) {
    if (speedKmh < 3.0 || rpm < 700) return 0; // Neutral / Idle
    final double ratio = rpm / math.max(1.0, speedKmh);
    if (ratio > 75) return 1;
    if (ratio > 48) return 2;
    if (ratio > 34) return 3;
    if (ratio > 26) return 4;
    if (ratio > 20) return 5;
    return 6;
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // DEMO SIMULATOR FALLBACK
  // ═══════════════════════════════════════════════════════════════════════════════

  void startSimulation() {
    stop();
    stateN.value = Obd2ConnectionState.simulating;
    statusMessageN.value = 'Running Realistic Demo Simulator';

    _simTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _simT += 0.15;
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
        gear = 5;
        throttle = 18.0;
        speed = 125.0 - (cycle - 20.0) * 4.0;
        rawRpm = 2200 - (cycle - 20.0) * 120;
        boost = 0.05;
        load = 28.0;
      }

      snapshotN.value = Obd2TelemetrySnapshot(
        rpm: rawRpm.round().clamp(750, 7800),
        speedKmh: speed.clamp(0.0, 220.0),
        coolantTempC: 91 + (math.sin(_simT * 0.1) * 2).round(),
        engineLoadPercent: load.clamp(5.0, 100.0),
        throttlePercent: throttle.clamp(0.0, 100.0),
        turboBoostBar: boost.clamp(0.0, 1.8),
        gear: gear,
        faults: _kKnownDtcMap.entries.take(2).map((MapEntry<String, (String, String, String)> e) {
          return Obd2DtcFault(
            code: e.key,
            descriptionEn: e.value.$1,
            descriptionKm: e.value.$2,
            severity: e.value.$3,
          );
        }).toList(),
        fuelEconomyL100km: 7.8 + math.sin(_simT) * 0.5,
        batteryVoltage: 13.9 + math.sin(_simT * 0.5) * 0.1,
      );
    });
  }

  void stop() {
    _simTimer?.cancel();
    _simTimer = null;
    _handleDisconnect('Disconnected');
    snapshotN.value = Obd2TelemetrySnapshot.idle;
  }
}
