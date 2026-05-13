import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/settings_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SPEEDOMETER WIDGET — Optimized Liquid HUD Edition
// Responsive + performance optimized + overflow safe
// ═══════════════════════════════════════════════════════════════════════════════

class SpeedometerWidget extends StatefulWidget {
  const SpeedometerWidget({
    super.key,
    required this.speedMph,
    this.isOverLimit = false,
  });

  final double speedMph;
  final bool isOverLimit;

  @override
  State<SpeedometerWidget> createState() => _SpeedometerWidgetState();
}

class _SpeedometerWidgetState extends State<SpeedometerWidget> {
  double _previousDisplaySpeed = 0.0;

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = SettingsService.instance;

    final double displaySpeed = settings
        .toDisplaySpeed(_safeSpeed(widget.speedMph))
        .clamp(0.0, 999.0)
        .toDouble();

    final String unitLabel = settings.speedUnit.toUpperCase();
    final double maxGaugeValue = settings.useKmh ? 220.0 : 140.0;

    return Semantics(
      label: 'Speedometer showing ${displaySpeed.round()} $unitLabel',
      value: displaySpeed.round().toString(),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double maxSide = _resolveSide(constraints);
          final bool compact = maxSide < 260.0;
          final bool tiny = maxSide < 190.0;

          return Center(
            child: SizedBox.square(
              dimension: maxSide,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: _previousDisplaySpeed,
                  end: displaySpeed,
                ),
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOutCubic,
                onEnd: () {
                  _previousDisplaySpeed = displaySpeed;
                },
                builder: (
                  BuildContext context,
                  double animatedSpeed,
                  Widget? child,
                ) {
                  return Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      const Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _GlassRimPainter(),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _SpeedometerPainter(
                              speed: animatedSpeed,
                              maxSpeed: maxGaugeValue,
                              isOverLimit: widget.isOverLimit,
                              compact: compact,
                            ),
                          ),
                        ),
                      ),
                      _CenterReadout(
                        speed: animatedSpeed,
                        unitLabel: unitLabel,
                        isOverLimit: widget.isOverLimit,
                        compact: compact,
                        tiny: tiny,
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  static double _safeSpeed(double value) {
    if (!value.isFinite || value < 0.0) return 0.0;
    return value;
  }

  static double _resolveSide(BoxConstraints constraints) {
    final double width =
        constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
    final double height =
        constraints.hasBoundedHeight ? constraints.maxHeight : width;

    final double side = math.min(width, height);

    if (!side.isFinite || side <= 0.0) return 260.0;

    return side.clamp(150.0, 420.0).toDouble();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLASS RIM PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter();

  static const Color _gold = Color(0xFFD4A843);
  static const Color _goldBright = Color(0xFFEDD068);
  static const Color _goldDeep = Color(0xFF8B6914);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);
    final double radius = size.shortestSide / 2.0;

    if (radius <= 0.0) return;

    final Rect circleRect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final Paint shadowPaint = Paint()
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.transparent,
          Colors.black.withValues(alpha: 0.52),
        ],
        stops: const <double>[0.76, 1.0],
      ).createShader(circleRect);

    canvas.drawCircle(center, radius, shadowPaint);

    final Paint softFill = Paint()
      ..isAntiAlias = true
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.white.withValues(alpha: 0.035),
          Colors.white.withValues(alpha: 0.012),
          Colors.black.withValues(alpha: 0.18),
        ],
        stops: const <double>[0.0, 0.64, 1.0],
      ).createShader(circleRect);

    canvas.drawCircle(center, radius - 8.0, softFill);

    final Paint rimPaint = Paint()
      ..isAntiAlias = true
      ..shader = SweepGradient(
        colors: <Color>[
          _gold,
          _goldDeep.withValues(alpha: 0.25),
          _goldBright,
          _goldDeep.withValues(alpha: 0.20),
          _gold,
        ],
      ).createShader(circleRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _scale(size, 2.0, 3.0);

    canvas.drawCircle(center, radius - 2.0, rimPaint);

    final Paint bevelPaint = Paint()
      ..isAntiAlias = true
      ..shader = SweepGradient(
        colors: <Color>[
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.18),
        ],
        stops: const <double>[0.0, 0.28, 0.52, 0.78, 1.0],
      ).createShader(circleRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _scale(size, 4.0, 7.0);

    canvas.drawCircle(center, radius - 7.0, bevelPaint);

    final Paint innerRing = Paint()
      ..isAntiAlias = true
      ..color = Colors.white.withValues(alpha: 0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius * 0.68, innerRing);
  }

  static double _scale(Size size, double small, double large) {
    final double t = ((size.shortestSide - 150.0) / 270.0).clamp(0.0, 1.0);
    return ui.lerpDouble(small, large, t)!;
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPEEDOMETER PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _SpeedometerPainter extends CustomPainter {
  const _SpeedometerPainter({
    required this.speed,
    required this.maxSpeed,
    required this.isOverLimit,
    required this.compact,
  });

  final double speed;
  final double maxSpeed;
  final bool isOverLimit;
  final bool compact;

  static const double _startAngleDeg = 145.0;
  static const double _sweepAngleDeg = 250.0;

  static const Color _goldBright = Color(0xFFEDD068);
  static const Color _goldMid = Color(0xFFD4A843);
  static const Color _redAlert = Color(0xFFE8412A);
  static const Color _redGlow = Color(0xFFFF6B55);

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    if (side <= 0.0) return;

    final Offset center = Offset(size.width / 2.0, size.height / 2.0);
    final double radius = side / 2.0;
    final double trackRadius = radius - (compact ? 20.0 : 26.0);

    if (trackRadius <= 0.0) return;

    final double startAngle = _startAngleDeg * math.pi / 180.0;
    final double sweepAngle = _sweepAngleDeg * math.pi / 180.0;
    final double safeMax = maxSpeed <= 0.0 ? 1.0 : maxSpeed;
    final double fraction = (speed / safeMax).clamp(0.0, 1.0).toDouble();

    final Rect trackRect = Rect.fromCircle(
      center: center,
      radius: trackRadius,
    );

    final double grooveWidth = compact ? 13.0 : 18.0;
    final double activeWidth = compact ? 10.0 : 14.0;

    final Paint groovePaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xFF070707)
      ..strokeWidth = grooveWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(trackRect, startAngle, sweepAngle, false, groovePaint);

    final Paint grooveHighlight = Paint()
      ..isAntiAlias = true
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = math.max(4.0, grooveWidth - 5.0)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(trackRect, startAngle, sweepAngle, false, grooveHighlight);

    _drawInactiveThreshold(canvas, trackRect, startAngle, sweepAngle);

    if (fraction > 0.0) {
      _drawActiveArc(
        canvas,
        trackRect,
        startAngle,
        sweepAngle,
        fraction,
        activeWidth,
      );
    }

    _drawTicks(
      canvas,
      center,
      trackRadius,
      startAngle,
      sweepAngle,
      fraction,
      compact,
    );

    if (fraction > 0.0) {
      _drawLeadingTip(
        canvas,
        center,
        trackRadius,
        startAngle,
        sweepAngle,
        fraction,
      );
    }
  }

  void _drawInactiveThreshold(
    Canvas canvas,
    Rect trackRect,
    double startAngle,
    double sweepAngle,
  ) {
    final Paint thresholdPaint = Paint()
      ..isAntiAlias = true
      ..color = _redAlert.withValues(alpha: 0.13)
      ..strokeWidth = compact ? 4.0 : 5.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      trackRect,
      startAngle + sweepAngle * 0.78,
      sweepAngle * 0.22,
      false,
      thresholdPaint,
    );
  }

  void _drawActiveArc(
    Canvas canvas,
    Rect trackRect,
    double startAngle,
    double sweepAngle,
    double fraction,
    double activeWidth,
  ) {
    final Color arcColor = isOverLimit ? _redAlert : _goldMid;
    final Color arcBright = isOverLimit ? _redGlow : _goldBright;

    final Paint glowPaint = Paint()
      ..isAntiAlias = true
      ..color = arcColor.withValues(alpha: isOverLimit ? 0.36 : 0.26)
      ..strokeWidth = compact ? 20.0 : 28.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);

    canvas.drawArc(
      trackRect,
      startAngle,
      sweepAngle * fraction,
      false,
      glowPaint,
    );

    final Paint activePaint = Paint()
      ..isAntiAlias = true
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: <Color>[
          arcColor.withValues(alpha: 0.15),
          arcColor,
          arcBright,
        ],
        stops: const <double>[0.0, 0.58, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(trackRect)
      ..strokeWidth = activeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      trackRect,
      startAngle,
      sweepAngle * fraction,
      false,
      activePaint,
    );
  }

  void _drawLeadingTip(
    Canvas canvas,
    Offset center,
    double trackRadius,
    double startAngle,
    double sweepAngle,
    double fraction,
  ) {
    final Color tipColor = isOverLimit ? _redGlow : _goldBright;
    final double tipAngle = startAngle + sweepAngle * fraction;

    final Offset tipPosition = Offset(
      center.dx + trackRadius * math.cos(tipAngle),
      center.dy + trackRadius * math.sin(tipAngle),
    );

    final Paint tipGlowPaint = Paint()
      ..isAntiAlias = true
      ..color = tipColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0);

    canvas.drawCircle(tipPosition, compact ? 4.8 : 6.4, tipGlowPaint);

    final Paint tipCorePaint = Paint()
      ..isAntiAlias = true
      ..color = Colors.white;

    canvas.drawCircle(tipPosition, compact ? 1.8 : 2.3, tipCorePaint);
  }

  void _drawTicks(
    Canvas canvas,
    Offset center,
    double trackRadius,
    double startAngle,
    double sweepAngle,
    double fraction,
    bool compact,
  ) {
    final int tickCount = compact ? 40 : 60;
    final double outerRadius = trackRadius - (compact ? 15.0 : 22.0);

    for (int i = 0; i <= tickCount; i++) {
      final bool major = compact ? i % 8 == 0 : i % 10 == 0;
      final double angle = startAngle + (sweepAngle / tickCount) * i;
      final double tickFraction = i / tickCount;
      final bool active = tickFraction <= fraction;

      final double tickLength = major ? (compact ? 9.0 : 12.0) : 5.0;
      final double strokeWidth = major ? 1.7 : 0.8;

      final Color color;
      if (active) {
        color = isOverLimit ? _redGlow : _goldBright;
      } else {
        color = major ? const Color(0xFF2A2616) : const Color(0xFF1A1810);
      }

      final double innerRadius = outerRadius - tickLength;
      final Paint tickPaint = Paint()
        ..isAntiAlias = true
        ..color = color
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(
          center.dx + innerRadius * math.cos(angle),
          center.dy + innerRadius * math.sin(angle),
        ),
        Offset(
          center.dx + outerRadius * math.cos(angle),
          center.dy + outerRadius * math.sin(angle),
        ),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter oldDelegate) {
    return oldDelegate.speed != speed ||
        oldDelegate.maxSpeed != maxSpeed ||
        oldDelegate.isOverLimit != isOverLimit ||
        oldDelegate.compact != compact;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CENTER READOUT
// ═══════════════════════════════════════════════════════════════════════════════

class _CenterReadout extends StatelessWidget {
  const _CenterReadout({
    required this.speed,
    required this.unitLabel,
    required this.isOverLimit,
    required this.compact,
    required this.tiny,
  });

  final double speed;
  final String unitLabel;
  final bool isOverLimit;
  final bool compact;
  final bool tiny;

  @override
  Widget build(BuildContext context) {
    final Color baseColor =
        isOverLimit ? const Color(0xFFE8412A) : const Color(0xFFD4A843);
    final Color mutedColor = baseColor.withValues(alpha: 0.46);

    final double numberSize = tiny
        ? 54.0
        : compact
            ? 72.0
            : 100.0;

    final double letterSpacing = tiny
        ? -2.0
        : compact
            ? -3.2
            : -5.0;

    return IgnorePointer(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: tiny ? 130.0 : 190.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _DividerLine(color: mutedColor, width: tiny ? 32.0 : 45.0),
              SizedBox(height: tiny ? 5.0 : 8.0),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isOverLimit
                        ? const <Color>[
                            Color(0xFFFF8A7A),
                            Color(0xFFE8412A),
                          ]
                        : const <Color>[
                            Color(0xFFFEE79B),
                            Color(0xFFD4A843),
                          ],
                  ).createShader(bounds);
                },
                child: Text(
                  speed.round().toString(),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: numberSize,
                    fontWeight: FontWeight.w200,
                    letterSpacing: letterSpacing,
                    height: 0.88,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              SizedBox(height: tiny ? 3.0 : 5.0),
              _UnitLabel(
                unitLabel: unitLabel,
                color: mutedColor,
                tiny: tiny,
              ),
              SizedBox(height: tiny ? 7.0 : 12.0),
              _DividerLine(color: mutedColor, width: tiny ? 32.0 : 45.0),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: isOverLimit && !tiny
                    ? Padding(
                        key: const ValueKey<String>('over-limit'),
                        padding: const EdgeInsets.only(top: 11.0),
                        child: Text(
                          '⚠  OVER LIMIT',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: const Color(0xFFE8412A),
                            fontSize: compact ? 8.0 : 9.0,
                            fontWeight: FontWeight.w900,
                            letterSpacing: compact ? 1.8 : 2.4,
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey<String>('normal-speed'),
                        height: 0,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitLabel extends StatelessWidget {
  const _UnitLabel({
    required this.unitLabel,
    required this.color,
    required this.tiny,
  });

  final String unitLabel;
  final Color color;
  final bool tiny;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Dot(color: color, size: tiny ? 2.5 : 3.0),
        SizedBox(width: tiny ? 6.0 : 8.0),
        Text(
          unitLabel,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(
            color: color,
            fontSize: tiny ? 8.0 : 10.0,
            fontWeight: FontWeight.w900,
            letterSpacing: tiny ? 2.6 : 4.0,
          ),
        ),
        SizedBox(width: tiny ? 6.0 : 8.0),
        _Dot(color: color, size: tiny ? 2.5 : 3.0),
      ],
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine({
    required this.color,
    required this.width,
  });

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 1.0,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.transparent,
            color,
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
