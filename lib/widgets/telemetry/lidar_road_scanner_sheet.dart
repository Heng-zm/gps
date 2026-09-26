import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/lidar_road_scanner_service.dart';
import '../../theme/app_theme.dart';
import '../common/app_glass_card.dart';

class LidarRoadScannerSheet extends StatefulWidget {
  const LidarRoadScannerSheet({super.key});

  @override
  State<LidarRoadScannerSheet> createState() => _LidarRoadScannerSheetState();
}

class _LidarRoadScannerSheetState extends State<LidarRoadScannerSheet> {
  final LidarRoadScannerService _service = LidarRoadScannerService.instance;

  @override
  void initState() {
    super.initState();
    _service.startScanning();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _service.isScanningN,
      builder: (BuildContext context, bool isScanning, _) {
        return ValueListenableBuilder<LidarScanFrame>(
          valueListenable: _service.frameN,
          builder: (BuildContext context, LidarScanFrame frame, _) {
            final bool hasHazard = frame.anomalies.isNotEmpty;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 3D Perspective Road Mesh Wireframe View
                  _build3DScannerCanvas(frame),
                  const SizedBox(height: 14),

                  // Surface Index & Laser Stats Row
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _StatCard(
                          title: 'SURFACE INDEX',
                          value: '${frame.surfaceSmoothnessScore}/100',
                          subtitle: frame.surfaceSmoothnessScore > 80
                              ? 'Smooth Asphalt'
                              : 'Rough / Potholes',
                          color: frame.surfaceSmoothnessScore > 80
                              ? AppColors.green
                              : AppColors.red,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          title: 'LIDAR DENSITY',
                          value: '${frame.laserPointCount}',
                          subtitle: 'Points / Sec',
                          color: AppColors.blueSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Hazard Alert Pill if detected
                  if (hasHazard)
                    ...frame.anomalies.map((LidarRoadAnomaly anomaly) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              CupertinoIcons.exclamationmark_octagon_fill,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'HAZARD DETECTED · ${anomaly.distanceMeters.toStringAsFixed(1)}M AHEAD',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pothole depth ~${anomaly.depthCm.toStringAsFixed(1)}cm · Slow down or bypass',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  // Scanner Power Toggle
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (isScanning) {
                        _service.stopScanning();
                      } else {
                        _service.startScanning();
                      }
                    },
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: isScanning
                            ? Colors.white.withValues(alpha: 0.08)
                            : AppColors.blue.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isScanning
                              ? Colors.white.withValues(alpha: 0.15)
                              : AppColors.blueSoft.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          isScanning ? 'PAUSE SCANNER' : 'START 3D ROAD SCAN',
                          style: TextStyle(
                            color: isScanning ? Colors.white70 : AppColors.blueSoft,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Technology Info Card
                  AppGlassCard(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Row(
                          children: <Widget>[
                            Icon(CupertinoIcons.waveform_path_ecg, size: 14, color: AppColors.blueSoft),
                            SizedBox(width: 6),
                            Text(
                              'ABOUT IPHONE LIDAR PROFILING',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Uses iPhone 12/13/14/15/16 Pro rear LiDAR Time-of-Flight sensor to construct a millimeter-accurate 3D depth mesh of the road surface up to 30 meters ahead.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _build3DScannerCanvas(LidarScanFrame frame) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(
                painter: _LidarMeshPainter(points: frame.points),
              ),
            ),
            // Scanner Active HUD Pill
            Positioned(
              top: 10,
              left: 12,
              child: Row(
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.blueSoft,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    '3D LIDAR ROAD MESH · LIVE',
                    style: TextStyle(
                      color: AppColors.blueSoft,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            // Range Scale on Right
            Positioned(
              top: 10,
              right: 12,
              bottom: 10,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '30m',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '15m',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '0m',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _LidarMeshPainter extends CustomPainter {
  const _LidarMeshPainter({required this.points});

  final List<LidarPoint3D> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final Offset centerBottom = Offset(size.width / 2, size.height * 0.95);
    final Offset vanishingPoint = Offset(size.width / 2, size.height * 0.12);

    final Paint gridPaint = Paint()
      ..color = AppColors.blueSoft.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Draw perspective lane edges
    canvas.drawLine(centerBottom + const Offset(-120, 0), vanishingPoint, gridPaint);
    canvas.drawLine(centerBottom + const Offset(120, 0), vanishingPoint, gridPaint);

    // Plot 3D point cloud
    for (final LidarPoint3D pt in points) {
      // Perspective projection
      final double zNorm = (pt.z / 30.0).clamp(0.05, 1.0);
      final double yScreen = vanishingPoint.dy + (centerBottom.dy - vanishingPoint.dy) * (1.0 - zNorm);
      final double widthAtZ = (size.width * 0.75) * (1.0 - zNorm * 0.7);
      final double xScreen = (size.width / 2) + (pt.x / 1.8) * (widthAtZ / 2);

      // Y elevation offset (dip or bump)
      final double elevationPx = pt.y * 120.0;
      final Offset ptOffset = Offset(xScreen, yScreen + elevationPx);

      final bool isDip = pt.y < -0.04;
      final Color ptColor = isDip
          ? AppColors.red
          : pt.y > 0.03
              ? Colors.amberAccent
              : AppColors.blueSoft.withValues(alpha: 0.65 * (1.0 - zNorm * 0.5));

      final Paint ptPaint = Paint()
        ..color = ptColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(ptOffset, isDip ? 3.5 : 1.8 * (1.0 - zNorm * 0.5), ptPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LidarMeshPainter old) => true;
}
