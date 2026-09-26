import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/gforce_telemetry_service.dart';
import '../../theme/app_theme.dart';

/// Interactive F1 / Porsche GT3-style Circular G-Force Telemetry Meter
class GForceMeterWidget extends StatefulWidget {
  const GForceMeterWidget({
    super.key,
    this.compact = false,
    this.size = 260.0,
  });

  final bool compact;
  final double size;

  @override
  State<GForceMeterWidget> createState() => _GForceMeterWidgetState();
}

class _GForceMeterWidgetState extends State<GForceMeterWidget> {
  final GForceTelemetryService _service = GForceTelemetryService.instance;

  @override
  void initState() {
    super.initState();
    _service.start();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GForceReading>(
      valueListenable: _service.readingN,
      builder: (BuildContext context, GForceReading reading, _) {
        if (widget.compact) {
          return _buildCompact(reading);
        }
        return _buildFull(reading);
      },
    );
  }

  Widget _buildCompact(GForceReading reading) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 36,
            height: 36,
            child: CustomPaint(
              painter: _GMeterPainter(
                lateralG: reading.lateralG,
                longitudinalG: reading.longitudinalG,
                peakLatG: reading.peakLateralG,
                compact: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${reading.totalG.toStringAsFixed(2)}G',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'LAT ${reading.lateralG >= 0 ? "+" : ""}${reading.lateralG.toStringAsFixed(2)}G',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFull(GForceReading reading) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Circular G-Meter Canvas
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _GMeterPainter(
              lateralG: reading.lateralG,
              longitudinalG: reading.longitudinalG,
              peakLatG: reading.peakLateralG,
              compact: false,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Readout Stats
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _StatPill(
              label: 'LATERAL',
              value: '${reading.lateralG >= 0 ? "+" : ""}${reading.lateralG.toStringAsFixed(2)}G',
              color: AppColors.blueSoft,
            ),
            _StatPill(
              label: 'BRAKE/ACCEL',
              value: '${reading.longitudinalG >= 0 ? "+" : ""}${reading.longitudinalG.toStringAsFixed(2)}G',
              color: reading.longitudinalG < -0.3 ? AppColors.red : AppColors.green,
            ),
            _StatPill(
              label: 'LEAN ANGLE',
              value: '${reading.leanAngleDeg.round()}°',
              color: Colors.amberAccent,
            ),
            _StatPill(
              label: 'PEAK LAT',
              value: '${reading.peakLateralG.toStringAsFixed(2)}G',
              color: Colors.purpleAccent,
            ),
          ],
        ),

        const SizedBox(height: 12),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          minSize: 32,
          onPressed: () {
            HapticFeedback.lightImpact();
            _service.resetPeaks();
          },
          child: Text(
            'RESET PEAKS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _GMeterPainter extends CustomPainter {
  const _GMeterPainter({
    required this.lateralG,
    required this.longitudinalG,
    required this.peakLatG,
    required this.compact,
  });

  final double lateralG;
  final double longitudinalG;
  final double peakLatG;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    final Paint circlePaint = Paint()
      ..color = Colors.white.withValues(alpha: compact ? 0.15 : 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Paint axisPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Outer and Inner Rings (0.5G, 1.0G, 1.5G)
    canvas.drawCircle(center, radius * 0.33, circlePaint);
    canvas.drawCircle(center, radius * 0.66, circlePaint);
    canvas.drawCircle(center, radius, circlePaint);

    // Crosshairs
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);

    // Max display range = 1.8G
    const double maxG = 1.8;
    final double pxX = (lateralG / maxG).clamp(-1.0, 1.0) * radius;
    final double pxY = (-longitudinalG / maxG).clamp(-1.0, 1.0) * radius;

    final Offset dotPos = Offset(center.dx + pxX, center.dy + pxY);

    // Dynamic glow color
    final double gMag = math.sqrt(lateralG * lateralG + longitudinalG * longitudinalG);
    final Color dotColor = gMag > 1.2
        ? AppColors.red
        : gMag > 0.7
            ? Colors.amberAccent
            : AppColors.blueSoft;

    // Vector line from center to current G
    final Paint linePaint = Paint()
      ..color = dotColor.withValues(alpha: 0.5)
      ..strokeWidth = compact ? 1.5 : 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, dotPos, linePaint);

    // Outer glow
    final Paint glowPaint = Paint()
      ..color = dotColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(dotPos, compact ? 5 : 9, glowPaint);

    // Center live dot
    final Paint dotPaint = Paint()..color = dotColor;
    canvas.drawCircle(dotPos, compact ? 3.5 : 6.0, dotPaint);

    // Center core white dot
    final Paint corePaint = Paint()..color = Colors.white;
    canvas.drawCircle(dotPos, compact ? 1.5 : 2.5, corePaint);
  }

  @override
  bool shouldRepaint(covariant _GMeterPainter old) {
    return old.lateralG != lateralG ||
        old.longitudinalG != longitudinalG ||
        old.peakLatG != peakLatG;
  }
}
