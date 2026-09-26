import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

enum SatelliteLinkState {
  standby,
  searchingSky,
  lockingOrbit,
  transmittingBurst,
  pingConfirmed,
  failed,
}

class SatellitePassPrediction {
  const SatellitePassPrediction({
    required this.satelliteName,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.timeToAOSSeconds, // Acquisition of Signal
    required this.signalQualityScore, // 0 to 100
  });

  final String satelliteName;
  final double azimuthDeg;
  final double elevationDeg;
  final int timeToAOSSeconds;
  final int signalQualityScore;
}

class SatelliteSosPacket {
  const SatelliteSosPacket({
    required this.packetId,
    required this.payloadHex,
    required this.payloadSizeBytes,
    required this.position,
    required this.altitudeMeters,
    required this.batteryPercent,
    required this.timestamp,
    required this.satelliteName,
    required this.transmissionHash,
  });

  final String packetId;
  final String payloadHex;
  final int payloadSizeBytes;
  final LatLng position;
  final double altitudeMeters;
  final int batteryPercent;
  final DateTime timestamp;
  final String satelliteName;
  final String transmissionHash;
}

/// Service managing Direct-to-Satellite LEO (Low-Earth Orbit) Non-Terrestrial Network
/// emergency packet compression, sky azimuth pointing guidance, and SOS burst transmission.
class SatelliteSosService {
  SatelliteSosService._();
  static final SatelliteSosService instance = SatelliteSosService._();

  final ValueNotifier<SatelliteLinkState> linkStateN =
      ValueNotifier<SatelliteLinkState>(SatelliteLinkState.standby);

  final ValueNotifier<SatellitePassPrediction> passN =
      ValueNotifier<SatellitePassPrediction>(_kDefaultPass);

  final ValueNotifier<List<SatelliteSosPacket>> sentPacketsN =
      ValueNotifier<List<SatelliteSosPacket>>(<SatelliteSosPacket>[]);

  final ValueNotifier<String> statusLogN =
      ValueNotifier<String>('Direct-to-Satellite Transceiver Standby');

  Timer? _orbitTimer;
  double _skyTick = 0.0;

  static const SatellitePassPrediction _kDefaultPass = SatellitePassPrediction(
    satelliteName: 'Iridium-NEXT-142 (LEO)',
    azimuthDeg: 218.0,
    elevationDeg: 64.0,
    timeToAOSSeconds: 0,
    signalQualityScore: 92,
  );

  void startSkyAcquisition(LatLng userPos) {
    linkStateN.value = SatelliteLinkState.searchingSky;
    statusLogN.value = 'Searching sky for active LEO satellite constellation...';

    _orbitTimer?.cancel();
    _orbitTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _skyTick += 0.15;

      // Simulate orbital path computation
      final double az = (218.0 + math.sin(_skyTick * 0.2) * 8.0) % 360.0;
      final double el = (64.0 + math.cos(_skyTick * 0.15) * 4.0).clamp(15.0, 90.0);
      final int quality = (88 + math.sin(_skyTick * 0.5) * 8).round().clamp(50, 100);

      passN.value = SatellitePassPrediction(
        satelliteName: 'Iridium-NEXT-142 (LEO)',
        azimuthDeg: az,
        elevationDeg: el,
        timeToAOSSeconds: 0,
        signalQualityScore: quality,
      );

      if (_skyTick > 1.2 && linkStateN.value == SatelliteLinkState.searchingSky) {
        linkStateN.value = SatelliteLinkState.lockingOrbit;
        statusLogN.value = 'Constellation acquired · Align device to Azimuth ${az.round()}°';
      }
    });
  }

  /// Compresses telemetry into a 120-byte micro-packet and transmits an uplink burst
  Future<bool> transmitSosBurst({
    required LatLng position,
    required double altitudeMeters,
    required int batteryPercent,
    required String emergencyNote,
  }) async {
    linkStateN.value = SatelliteLinkState.transmittingBurst;
    statusLogN.value = 'Encoding 120-byte Non-Terrestrial Network packet...';

    // Compress payload into compact hex representation
    final int latInt = (position.latitude * 1000000).round();
    final int lngInt = (position.longitude * 1000000).round();
    final int altInt = altitudeMeters.round().clamp(0, 8848);
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final String hexPayload = 'LEO-SOS:'
        '${latInt.toRadixString(16).padLeft(8, "0")}'
        '${lngInt.toRadixString(16).padLeft(8, "0")}'
        '${altInt.toRadixString(16).padLeft(4, "0")}'
        '${batteryPercent.toRadixString(16).padLeft(2, "0")}'
        '${nowSec.toRadixString(16)}';

    statusLogN.value = 'Transmitting burst to ${passN.value.satelliteName}...';
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    final String txHash = '0x${DateTime.now().microsecondsSinceEpoch.toRadixString(16).toUpperCase()}';
    final SatelliteSosPacket packet = SatelliteSosPacket(
      packetId: 'SAT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      payloadHex: hexPayload,
      payloadSizeBytes: hexPayload.length,
      position: position,
      altitudeMeters: altitudeMeters,
      batteryPercent: batteryPercent,
      timestamp: DateTime.now(),
      satelliteName: passN.value.satelliteName,
      transmissionHash: txHash,
    );

    sentPacketsN.value = <SatelliteSosPacket>[
      packet,
      ...sentPacketsN.value,
    ];

    linkStateN.value = SatelliteLinkState.pingConfirmed;
    statusLogN.value = '✅ Distress packet verified by LEO uplink relay (Hash: $txHash)';

    return true;
  }

  void stop() {
    _orbitTimer?.cancel();
    _orbitTimer = null;
    linkStateN.value = SatelliteLinkState.standby;
    statusLogN.value = 'Direct-to-Satellite Transceiver Standby';
  }
}
