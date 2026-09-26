import 'dart:math' as math;
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../services/gps_service.dart';
import '../../services/satellite_sos_service.dart';
import '../../theme/app_theme.dart';
import '../common/app_glass_card.dart';

class SatelliteSosSheet extends StatefulWidget {
  const SatelliteSosSheet({super.key});

  @override
  State<SatelliteSosSheet> createState() => _SatelliteSosSheetState();
}

class _SatelliteSosSheetState extends State<SatelliteSosSheet> {
  final SatelliteSosService _service = SatelliteSosService.instance;
  final GpsService _gps = GpsService.instance;

  int _batteryPercent = 85;

  @override
  void initState() {
    super.initState();
    _fetchBattery();
    final LatLng pos = _gps.lastKnownPosition ?? const LatLng(11.5564, 104.9282);
    _service.startSkyAcquisition(pos);
  }

  Future<void> _fetchBattery() async {
    try {
      final int level = await Battery().batteryLevel;
      if (mounted) setState(() => _batteryPercent = level);
    } catch (_) {}
  }

  void _transmitBurst() {
    HapticFeedback.heavyImpact();
    final LatLng pos = _gps.lastKnownPosition ?? const LatLng(11.5564, 104.9282);
    final double alt = _gps.currentAltitudeMeters;

    _service.transmitSosBurst(
      position: pos,
      altitudeMeters: alt.isFinite ? alt : 18.0,
      batteryPercent: _batteryPercent,
      emergencyNote: 'Medical emergency / off-grid beacon',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SatelliteLinkState>(
      valueListenable: _service.linkStateN,
      builder: (BuildContext context, SatelliteLinkState state, _) {
        return ValueListenableBuilder<SatellitePassPrediction>(
          valueListenable: _service.passN,
          builder: (BuildContext context, SatellitePassPrediction pass, _) {
            final bool isLock = state == SatelliteLinkState.lockingOrbit ||
                state == SatelliteLinkState.pingConfirmed;
            final bool isTx = state == SatelliteLinkState.transmittingBurst;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Sky Azimuth & Elevation Visualizer
                  _buildSkyRadar(pass, state),
                  const SizedBox(height: 16),

                  // Constellation & Link Status
                  AppGlassCard(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 18,
                    child: Column(
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Icon(CupertinoIcons.antenna_radiowaves_left_right,
                                    size: 16, color: AppColors.blueSoft),
                                const SizedBox(width: 8),
                                Text(
                                  pass.satelliteName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isLock
                                    ? AppColors.green.withValues(alpha: 0.2)
                                    : Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isLock ? 'ORBIT LOCKED' : 'SEARCHING',
                                style: TextStyle(
                                  color: isLock ? AppColors.green : Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: <Widget>[
                            _InfoCol(label: 'AZIMUTH', value: '${pass.azimuthDeg.round()}° (SW)'),
                            _InfoCol(label: 'ELEVATION', value: '${pass.elevationDeg.round()}°'),
                            _InfoCol(label: 'LINK QUALITY', value: '${pass.signalQualityScore}%'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Transmit 120-byte SOS Burst Button
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: isTx ? null : _transmitBurst,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: <Color>[Color(0xFFFF3B30), Color(0xFFD70015)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: AppColors.red.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          if (isTx)
                            const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                          else
                            const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            isTx ? 'UPLINKING TO SATELLITE...' : 'TRANSMIT LEO SOS BURST (120B)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Live Uplink Logs
                  ValueListenableBuilder<String>(
                    valueListenable: _service.statusLogN,
                    builder: (_, String log, __) {
                      return Text(
                        log,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Transmission Receipts
                  _buildReceiptsList(),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSkyRadar(SatellitePassPrediction pass, SatelliteLinkState state) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: pass.isAligned
              ? AppColors.green.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CustomPaint(
            size: const Size(180, 180),
            painter: _SkyRadarPainter(
              azimuthDeg: pass.azimuthDeg,
              elevationDeg: pass.elevationDeg,
              deviceHeadingDeg: pass.deviceHeadingDeg,
              devicePitchDeg: pass.devicePitchDeg,
              isAligned: pass.isAligned,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: pass.isAligned
                  ? AppColors.green.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: pass.isAligned
                    ? AppColors.green.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Text(
              pass.isAligned
                  ? '🎯 SATELLITE LOCKED · Phone Aligned (${pass.deviceHeadingDeg.round()}° / ${pass.devicePitchDeg.round()}°)'
                  : 'Hold phone up to sky · Compass: ${pass.deviceHeadingDeg.round()}° · Tilt: ${pass.devicePitchDeg.round()}°',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: pass.isAligned ? AppColors.green : Colors.white.withValues(alpha: 0.75),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptsList() {
    return ValueListenableBuilder<List<SatelliteSosPacket>>(
      valueListenable: _service.sentPacketsN,
      builder: (_, List<SatelliteSosPacket> packets, __) {
        if (packets.isEmpty) return const SizedBox.shrink();

        return AppGlassCard(
          padding: const EdgeInsets.all(14),
          borderRadius: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'SATELLITE TRANSMISSION RECEIPT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 8),
              ...packets.map((SatelliteSosPacket p) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'ID: ${p.packetId} · ${p.payloadSizeBytes} Bytes · Uplink: ${p.satelliteName}',
                        style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Hash: ${p.transmissionHash} · ${p.position.latitude.toStringAsFixed(4)}, ${p.position.longitude.toStringAsFixed(4)}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9.5, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _InfoCol extends StatelessWidget {
  const _InfoCol({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _SkyRadarPainter extends CustomPainter {
  const _SkyRadarPainter({
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.deviceHeadingDeg,
    required this.devicePitchDeg,
    required this.isAligned,
  });

  final double azimuthDeg;
  final double elevationDeg;
  final double deviceHeadingDeg;
  final double devicePitchDeg;
  final bool isAligned;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 14;

    final Paint ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawCircle(center, radius * 0.33, ringPaint);
    canvas.drawCircle(center, radius * 0.66, ringPaint);
    canvas.drawCircle(center, radius, ringPaint);

    // Cardinal directions N, E, S, W
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), ringPaint);
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), ringPaint);

    // Satellite position on hemisphere (distance from center = (90 - elevation) / 90 * radius)
    final double radAz = (azimuthDeg - 90) * (math.pi / 180.0);
    final double distFromCenter = ((90.0 - elevationDeg) / 90.0).clamp(0.0, 1.0) * radius;

    final Offset satPos = Offset(
      center.dx + math.cos(radAz) * distFromCenter,
      center.dy + math.sin(radAz) * distFromCenter,
    );

    // Real device physical pointing crosshair (clamped safely inside radar boundary)
    final double devRad = (deviceHeadingDeg - 90) * (math.pi / 180.0);
    final double maxReticleRadius = math.max(0.0, radius - 14.0);
    final double devDist = ((90.0 - devicePitchDeg) / 90.0).clamp(0.0, 1.0) * maxReticleRadius;
    final Offset devPos = Offset(
      center.dx + math.cos(devRad) * devDist,
      center.dy + math.sin(devRad) * devDist,
    );

    // Draw connection lock beam if close
    if (isAligned) {
      final Paint beamPaint = Paint()
        ..color = AppColors.green.withValues(alpha: 0.45)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(devPos, satPos, beamPaint);
    }

    // Satellite Glow
    final Color satColor = isAligned ? AppColors.green : AppColors.blueSoft;
    final Paint glowPaint = Paint()
      ..color = satColor.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(satPos, 14, glowPaint);

    // Satellite Dot
    final Paint satPaint = Paint()..color = satColor;
    canvas.drawCircle(satPos, 6.5, satPaint);

    final Paint corePaint = Paint()..color = Colors.white;
    canvas.drawCircle(satPos, 2.5, corePaint);

    // Device Pointer Reticle (Phone Crosshair)
    final Paint reticlePaint = Paint()
      ..color = isAligned ? AppColors.green : Colors.amber
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(devPos, 10, reticlePaint);
    canvas.drawLine(Offset(devPos.dx - 14, devPos.dy), Offset(devPos.dx + 14, devPos.dy), reticlePaint);
    canvas.drawLine(Offset(devPos.dx, devPos.dy - 14), Offset(devPos.dx, devPos.dy + 14), reticlePaint);
  }

  @override
  bool shouldRepaint(covariant _SkyRadarPainter old) => true;
}
