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
    final displaySpeed = settings.toDisplaySpeed(speedMph).clamp(0.0, 999.0);
    final unitLabel = settings.speedUnit.toUpperCase();
    final double maxGaugeVal = settings.useKmh ? 220.0 : 140.0;

    return Semantics(
      label: 'Speedometer showing ${displaySpeed.toInt()} $unitLabel',
      value: displaySpeed.toInt().toString(),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: displaySpeed),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
        builder: (context, animatedSpeed, _) {
          return AspectRatio(
            aspectRatio: 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Static Hardware Layer (Cached for Performance)
                const RepaintBoundary(
                  child: _StaticGlassBackground(),
                ),

                // 2. Dynamic Gauge Layer
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _SpeedometerPainter(
                      speed: animatedSpeed,
                      maxSpeed: maxGaugeVal,
                      isOverLimit: isOverLimit,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),

                // 3. Center Digital Readout
                _CenterReadout(
                  speed: animatedSpeed,
                  unitLabel: unitLabel,
                  isOverLimit: isOverLimit,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Static Glass Background ──────────────────────────────────────────────────

class _StaticGlassBackground extends StatelessWidget {
  const _StaticGlassBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlassRimPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _GlassRimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    // Deep OLED Black Drop Shadow
    final shadowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF000000).withValues(alpha: 0.6),
        ],
        stops: const [0.85, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, shadowPaint);

    // Primary Gold Bezel
    final rimPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0xFFD4A843),
          const Color(0xFF8B6914).withValues(alpha: 0.2),
          const Color(0xFFEDD068),
          const Color(0xFF8B6914).withValues(alpha: 0.2),
          const Color(0xFFD4A843),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, outerRadius - 2, rimPaint);

    // Glass Inner Specular Edge
    final bevelPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.15),
        ],
        stops: const [0.0, 0.3, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(center, outerRadius - 5, bevelPaint);
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) => false;
}

// ─── Main Speedometer Painter ─────────────────────────────────────────────────

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;
  final bool isOverLimit;

  const _SpeedometerPainter({
    required this.speed,
    required this.maxSpeed,
    required this.isOverLimit,
  });

  static const double _startAngleDeg = 145;
  static const double _sweepAngleDeg = 250;

  static const Color _goldBright = Color(0xFFEDD068);
  static const Color _goldMid = Color(0xFFD4A843);
  static const Color _redAlert = Color(0xFFE8412A);
  static const Color _redGlow = Color(0xFFFF6B55);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final trackRadius = size.width / 2 - 25;
    final startAngle = _startAngleDeg * pi / 180;
    final sweepAngle = _sweepAngleDeg * pi / 180;
    final fraction = (speed / maxSpeed).clamp(0.001, 1.0);

    final trackRect = Rect.fromCircle(center: center, radius: trackRadius);

    // 1. Physical Track Background (The "Groove")
    final groovePaint = Paint()
      ..color = const Color(0xFF080808)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke;
    canvas.drawArc(trackRect, startAngle, sweepAngle, false, groovePaint);

    // Specular highlight on the bottom of the groove
    final innerHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke;
    canvas.drawArc(trackRect, startAngle, sweepAngle, false, innerHighlight);

    // 2. Active Speed Arc
    final Color arcColor = isOverLimit ? _redAlert : _goldMid;
    final Color arcColorBright = isOverLimit ? _redGlow : _goldBright;

    // Outer Neon Glow
    final glowPaint = Paint()
      ..color = arcColor.withValues(alpha: 0.25)
      ..strokeWidth = 26
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawArc(
        trackRect, startAngle, sweepAngle * fraction, false, glowPaint);

    // Main Gradient Needle Arc
    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [arcColor.withValues(alpha: 0.1), arcColorBright],
        stops: const [0.0, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(trackRect)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        trackRect, startAngle, sweepAngle * fraction, false, activePaint);

    // 3. Leading Tip (Pill Flare)
    final tipAngle = startAngle + (sweepAngle * fraction);
    final tipPos = Offset(
      center.dx + trackRadius * cos(tipAngle),
      center.dy + trackRadius * sin(tipAngle),
    );

    final tipGlow = Paint()
      ..color = arcColorBright
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(tipPos, 6, tipGlow);

    final tipCore = Paint()..color = Colors.white;
    canvas.drawCircle(tipPos, 2.2, tipCore);

    // 4. Luxury Tick Marks
    _drawTicks(canvas, center, trackRadius, startAngle, sweepAngle, fraction);
  }

  void _drawTicks(Canvas canvas, Offset center, double trackRadius,
      double startAngle, double sweepAngle, double fraction) {
    const int tickCount = 60;
    final outerTickR = trackRadius - 22;

    for (int i = 0; i <= tickCount; i++) {
      final bool isMajor = i % 10 == 0;
      final angle = startAngle + (sweepAngle / tickCount) * i;
      final tickFraction = i / tickCount;
      final isActive = tickFraction <= fraction;

      final double tickLen = isMajor ? 12 : 6;
      final double strokeW = isMajor ? 1.8 : 0.8;

      Color color;
      if (isActive) {
        color = isOverLimit ? _redGlow : _goldBright;
      } else {
        color = isMajor ? const Color(0xFF2A2616) : const Color(0xFF1A1810);
      }

      final innerR = outerTickR - tickLen;
      final paint = Paint()
        ..color = color
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(
            center.dx + innerR * cos(angle), center.dy + innerR * sin(angle)),
        Offset(center.dx + outerTickR * cos(angle),
            center.dy + outerTickR * sin(angle)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeedometerPainter old) =>
      old.speed != speed || old.isOverLimit != isOverLimit;
}

// ─── Center Readout ───────────────────────────────────────────────────────────

class _CenterReadout extends StatelessWidget {
  final double speed;
  final String unitLabel;
  final bool isOverLimit;

  const _CenterReadout({
    required this.speed,
    required this.unitLabel,
    required this.isOverLimit,
  });

  @override
  Widget build(BuildContext context) {
    final Color baseColor =
        isOverLimit ? const Color(0xFFE8412A) : const Color(0xFFD4A843);
    final Color mutedColor = baseColor.withValues(alpha: 0.4);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _divider(mutedColor),
        const SizedBox(height: 8),

        // Animated Number
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isOverLimit
                ? [const Color(0xFFFF8A7A), const Color(0xFFE8412A)]
                : [const Color(0xFFFEE79B), const Color(0xFFD4A843)],
          ).createShader(bounds),
          child: Text(
            speed.toInt().toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 100,
              fontWeight: FontWeight.w200,
              letterSpacing: -5,
              height: 0.9,
            ),
          ),
        ),

        const SizedBox(height: 4),

        // Unit Label
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(mutedColor),
            const SizedBox(width: 8),
            Text(
              unitLabel,
              style: TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(width: 8),
            _dot(mutedColor),
          ],
        ),

        const SizedBox(height: 12),
        _divider(mutedColor),

        if (isOverLimit) ...[
          const SizedBox(height: 12),
          const Text(
            '⚠  OVER LIMIT',
            style: TextStyle(
              color: Color(0xFFE8412A),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _divider(Color color) => Container(
        width: 45,
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, color, Colors.transparent],
          ),
        ),
      );

  Widget _dot(Color color) => Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
