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
    final double maxGaugeVal = settings.useKmh ? 220.0 : 140.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: displaySpeed),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutExpo,
      builder: (context, animatedSpeed, _) {
        return AspectRatio(
          aspectRatio: 1,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glass rim
              CustomPaint(
                painter: _GlassRimPainter(),
                child: const SizedBox.expand(),
              ),
              // Main gauge
              CustomPaint(
                painter: _SpeedometerPainter(
                  speed: animatedSpeed,
                  maxSpeed: maxGaugeVal,
                  isOverLimit: isOverLimit,
                ),
                child: const SizedBox.expand(),
              ),
              // Center readout
              _CenterReadout(
                speed: animatedSpeed,
                unitLabel: unitLabel,
                isOverLimit: isOverLimit,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Glass Rim Painter ────────────────────────────────────────────────────────

class _GlassRimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    // Deep shadow ring (outermost)
    final shadowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF000000).withValues(alpha: 0.6),
        ],
        stops: const [0.78, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, shadowPaint);

    // Gold rim highlight (top-left)
    final rimHighlightPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0xFFD4A843).withValues(alpha: 0.9),
          const Color(0xFF8B6914).withValues(alpha: 0.2),
          const Color(0xFFEDD068).withValues(alpha: 0.6),
          const Color(0xFF6B4F0A).withValues(alpha: 0.1),
          const Color(0xFFD4A843).withValues(alpha: 0.9),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, outerRadius - 2, rimHighlightPaint);

    // Inner glass bevel
    final innerBevelPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0xFFFFFFFF).withValues(alpha: 0.08),
          const Color(0xFFFFFFFF).withValues(alpha: 0.02),
          const Color(0xFF000000).withValues(alpha: 0.15),
          const Color(0xFFFFFFFF).withValues(alpha: 0.05),
          const Color(0xFFFFFFFF).withValues(alpha: 0.08),
        ],
        stops: const [0.0, 0.3, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, outerRadius - 8, innerBevelPaint);
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

  // Gold palette
  static const Color _goldBright = Color(0xFFEDD068);
  static const Color _goldMid = Color(0xFFD4A843);
  static const Color _goldDark = Color(0xFF8B6914);
  static const Color _redAlert = Color(0xFFE8412A);
  static const Color _redGlow = Color(0xFFFF6B55);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final trackRadius = size.width / 2 - 22;
    final startAngle = _startAngleDeg * pi / 180;
    final sweepAngle = _sweepAngleDeg * pi / 180;
    final fraction = (speed / maxSpeed).clamp(0.0, 1.0);

    final trackRect = Rect.fromCircle(center: center, radius: trackRadius);

    // 1. Dark track groove
    final groovePaint = Paint()
      ..color = const Color(0xFF0D0D0D)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(trackRect, startAngle, sweepAngle, false, groovePaint);

    // Groove inner highlight
    final grooveHighlightPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
        trackRect, startAngle, sweepAngle, false, grooveHighlightPaint);

    // 2. Active arc
    if (fraction > 0) {
      final Color arcColorA = isOverLimit ? _redAlert : _goldDark;
      final Color arcColorB = isOverLimit ? _redGlow : _goldBright;

      // Outer glow
      final glowPaint = Paint()
        ..color = (isOverLimit ? _redAlert : _goldMid).withValues(alpha: 0.25)
        ..strokeWidth = 28
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawArc(
          trackRect, startAngle, sweepAngle * fraction, false, glowPaint);

      // Tight inner glow
      final innerGlowPaint = Paint()
        ..color = (isOverLimit ? _redGlow : _goldBright).withValues(alpha: 0.4)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawArc(
          trackRect, startAngle, sweepAngle * fraction, false, innerGlowPaint);

      // Main gradient arc
      final activePaint = Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle,
          colors: [arcColorA.withValues(alpha: 0.5), arcColorB],
          stops: const [0.0, 1.0],
          transform: GradientRotation(startAngle),
        ).createShader(trackRect)
        ..strokeWidth = 16
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
          trackRect, startAngle, sweepAngle * fraction, false, activePaint);

      // Leading edge dot flare
      final tipAngle = startAngle + sweepAngle * fraction;
      final tipX = center.dx + trackRadius * cos(tipAngle);
      final tipY = center.dy + trackRadius * sin(tipAngle);
      final tipFlare = Paint()
        ..color = isOverLimit ? _redGlow : _goldBright
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(tipX, tipY), 7, tipFlare);
      final tipCore = Paint()..color = Colors.white.withValues(alpha: 0.9);
      canvas.drawCircle(Offset(tipX, tipY), 3, tipCore);
    }

    // 3. Luxury tick marks — two rings
    _drawTicks(canvas, center, trackRadius, startAngle, sweepAngle, fraction);

    // 4. Speed labels
    _drawLabel(canvas, center, '0', startAngle, trackRadius - 30);
    _drawLabel(canvas, center, maxSpeed.toInt().toString(),
        startAngle + sweepAngle, trackRadius - 30);
  }

  void _drawTicks(Canvas canvas, Offset center, double trackRadius,
      double startAngle, double sweepAngle, double fraction) {
    const int majorCount = 10;
    const int minorPerMajor = 4;
    const int totalTicks = majorCount * minorPerMajor + majorCount;

    final outerTickR = trackRadius - 26;

    for (int i = 0; i <= totalTicks; i++) {
      final bool isMajor = i % (minorPerMajor + 1) == 0;
      final angle = startAngle + (sweepAngle / totalTicks) * i;
      final tickFraction = i / totalTicks;
      final isFilled = tickFraction <= fraction;

      final double tickLen = isMajor ? 14 : 7;
      final double strokeW = isMajor ? 2.0 : 1.0;

      Color tickColor;
      if (isFilled) {
        tickColor = isOverLimit
            ? const Color(0xFFE8412A).withValues(alpha: isMajor ? 1.0 : 0.7)
            : (isMajor ? _goldBright : _goldMid.withValues(alpha: 0.7));
      } else {
        tickColor = isMajor ? const Color(0xFF3A3020) : const Color(0xFF222017);
      }

      final innerR = outerTickR - tickLen;

      final paint = Paint()
        ..color = tickColor
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(
            center.dx + innerR * cos(angle), center.dy + innerR * sin(angle)),
        Offset(center.dx + outerTickR * cos(angle),
            center.dy + outerTickR * sin(angle)),
        paint,
      );

      // Dot accent on major filled ticks
      if (isMajor && isFilled) {
        final dotPaint = Paint()
          ..color = (isOverLimit ? const Color(0xFFE8412A) : _goldBright)
              .withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        final dotPos = Offset(
          center.dx + (innerR - 4) * cos(angle),
          center.dy + (innerR - 4) * sin(angle),
        );
        canvas.drawCircle(dotPos, 2.5, dotPaint);
      }
    }
  }

  void _drawLabel(
      Canvas canvas, Offset center, String text, double angle, double r) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF5A4A20),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
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
    final Color dimColor = isOverLimit
        ? const Color(0xFFE8412A).withValues(alpha: 0.5)
        : const Color(0xFF8B6914);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Thin decorative line above
        Container(
          width: 36,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                dimColor,
                Colors.transparent,
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Speed number
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isOverLimit
                ? [const Color(0xFFFF6B55), const Color(0xFFE8412A)]
                : [const Color(0xFFF5DFA0), const Color(0xFFD4A843)],
          ).createShader(bounds),
          child: Text(
            speed.toInt().toString(),
            style: const TextStyle(
              color: Colors.white, // masked by ShaderMask
              fontSize: 96,
              fontWeight: FontWeight.w100,
              letterSpacing: -6,
              height: 0.9,
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Unit label with decorative dots
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(dimColor),
            const SizedBox(width: 6),
            Text(
              unitLabel,
              style: TextStyle(
                color: dimColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 5,
              ),
            ),
            const SizedBox(width: 6),
            _dot(dimColor),
          ],
        ),

        const SizedBox(height: 8),

        // Thin decorative line below
        Container(
          width: 36,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                dimColor,
                Colors.transparent,
              ],
            ),
          ),
        ),

        // Over-limit warning
        if (isOverLimit) ...[
          const SizedBox(height: 10),
          Text(
            '⚠  OVER LIMIT',
            style: TextStyle(
              color: const Color(0xFFE8412A).withValues(alpha: 0.9),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dot(Color color) => Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
}
