import 'dart:math';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SpeedometerWidget extends StatelessWidget {
  final double speedMph;
  final bool isOverLimit;

  const SpeedometerWidget({
    super.key,
    required this.speedMph,
    this.isOverLimit = false,
  });

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final displaySpeed = settings.toDisplaySpeed(speedMph);
    final unitLabel = settings.speedUnit.toUpperCase();

    // Calculate dynamic max speed based on units
    final double maxGaugeVal = settings.useKmh ? 220.0 : 140.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: displaySpeed),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutSine,
      builder: (context, animatedSpeed, _) {
        return AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(
            painter: _SpeedometerPainter(
              speed: animatedSpeed,
              maxSpeed: maxGaugeVal,
              isOverLimit: isOverLimit,
              accentColor: isOverLimit
                  ? const Color(0xFFE74C3C)
                  : const Color(0xFF4ECDC4),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    animatedSpeed.toInt().toString(),
                    style: TextStyle(
                      color:
                          isOverLimit ? const Color(0xFFE74C3C) : Colors.white,
                      fontSize: 84, // Slightly larger
                      fontWeight: FontWeight.w200, // Thinner, more modern look
                      letterSpacing: -4,
                      height: 1,
                      shadows: [
                        if (!isOverLimit)
                          Shadow(
                            color:
                                const Color(0xFF4ECDC4).withValues(alpha: 0.3),
                            blurRadius: 20,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unitLabel,
                    style: TextStyle(
                      color: isOverLimit
                          ? const Color(0xFFE74C3C).withValues(alpha: 0.7)
                          : const Color(0xFF4ECDC4),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final bool isOverLimit;
  final Color accentColor;

  const _SpeedometerPainter({
    required this.speed,
    required this.maxSpeed,
    required this.isOverLimit,
    required this.accentColor,
  });

  static const double _startAngleDeg = 150;
  static const double _sweepAngleDeg = 240;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    final startAngle = _startAngleDeg * pi / 180;
    final sweepAngle = _sweepAngleDeg * pi / 180;

    // 1. Draw Background Track
    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // 2. Draw Active Progress Arc with Neon Glow
    final fraction = (speed / maxSpeed).clamp(0.0, 1.0);

    if (fraction > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);

      // Outer Glow layer
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.3)
        ..strokeWidth = 20
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawArc(rect, startAngle, sweepAngle * fraction, false, glowPaint);

      // Main Arc layer
      final activePaint = Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle,
          colors: [
            accentColor.withValues(alpha: 0.2),
            accentColor,
          ],
          stops: const [0.0, 1.0],
          transform: GradientRotation(startAngle),
        ).createShader(rect)
        ..strokeWidth = 14
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
          rect, startAngle, sweepAngle * fraction, false, activePaint);
    }

    // 3. Draw Modern Ticks
    const int tickCount = 40; // More ticks for higher resolution
    for (int i = 0; i <= tickCount; i++) {
      final angle = startAngle + (sweepAngle / tickCount) * i;
      final isMajor = i % 10 == 0;
      final isFilled = i <= (tickCount * fraction);

      final double tickLength = isMajor ? 12 : 6;
      final double innerR = radius - 18 - tickLength;
      final double outerR = radius - 18;

      final tickPaint = Paint()
        ..color = isFilled
            ? accentColor.withValues(alpha: 0.8)
            : const Color(0xFF333333)
        ..strokeWidth = isMajor ? 2.5 : 1.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(
            center.dx + innerR * cos(angle), center.dy + innerR * sin(angle)),
        Offset(
            center.dx + outerR * cos(angle), center.dy + outerR * sin(angle)),
        tickPaint,
      );
    }

    // 4. Draw Semantic Labels (0 and Max)
    _drawText(canvas, center, '0', startAngle, radius - 45);
    _drawText(canvas, center, maxSpeed.toInt().toString(),
        startAngle + sweepAngle, radius - 45);
  }

  void _drawText(
      Canvas canvas, Offset center, String text, double angle, double r) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF555555),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
        center.dx + r * cos(angle) - tp.width / 2,
        center.dy + r * sin(angle) - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_SpeedometerPainter old) =>
      old.speed != speed ||
      old.isOverLimit != isOverLimit ||
      old.maxSpeed != maxSpeed;
}
