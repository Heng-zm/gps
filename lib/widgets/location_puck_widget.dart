import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/location_puck_style.dart';

class AppLocationPuck extends StatelessWidget {
  const AppLocationPuck({
    super.key,
    required this.style,
    this.bearing = 0,
    this.speed = 0,
    this.showPulse = true,
    this.size,
    this.isActive = true,
  });

  final LocationPuckStyle style;
  final double bearing;
  final double speed;
  final bool showPulse;
  final double? size;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final double resolvedSize = size ?? style.markerSize;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: resolvedSize,
        child: _AnimatedPuckBody(
          style: style,
          bearing: bearing,
          speed: speed,
          showPulse: showPulse && isActive,
          size: resolvedSize,
          isActive: isActive,
        ),
      ),
    );
  }
}

class _AnimatedPuckBody extends StatefulWidget {
  const _AnimatedPuckBody({
    required this.style,
    required this.bearing,
    required this.speed,
    required this.showPulse,
    required this.size,
    required this.isActive,
  });

  final LocationPuckStyle style;
  final double bearing;
  final double speed;
  final bool showPulse;
  final double size;
  final bool isActive;

  @override
  State<_AnimatedPuckBody> createState() => _AnimatedPuckBodyState();
}

class _AnimatedPuckBodyState extends State<_AnimatedPuckBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOutCubic,
    );

    if (widget.showPulse) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedPuckBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.showPulse != widget.showPulse) {
      if (widget.showPulse) {
        _pulseController.repeat();
      } else {
        _pulseController.stop();
        _pulseController.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == LocationPuckStyle.vehicle) {
      return _VehiclePuck(
        size: widget.size,
        bearing: widget.bearing,
        accent: widget.style.accentColor,
        speed: _safeSpeed(widget.speed),
        showSpeedBadge: widget.style.showsSpeedBadge,
        isActive: widget.isActive,
      );
    }

    if (widget.style == LocationPuckStyle.navigator) {
      return _NavigatorPuck(
        size: widget.size,
        bearing: widget.bearing,
        accent: widget.style.accentColor,
        speed: _safeSpeed(widget.speed),
        isActive: widget.isActive,
        pulseValue: widget.showPulse ? _pulse.value : 0,
      );
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return _CircularPuck(
          style: widget.style,
          bearing: widget.bearing,
          speed: _safeSpeed(widget.speed),
          size: widget.size,
          pulseValue: widget.showPulse ? _pulse.value : 0,
          isActive: widget.isActive,
        );
      },
    );
  }

  static int _safeSpeed(double value) {
    if (!value.isFinite || value < 0) return 0;
    return value.round().clamp(0, 999);
  }
}

class _CircularPuck extends StatelessWidget {
  const _CircularPuck({
    required this.style,
    required this.bearing,
    required this.speed,
    required this.size,
    required this.pulseValue,
    required this.isActive,
  });

  final LocationPuckStyle style;
  final double bearing;
  final int speed;
  final double size;
  final double pulseValue;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final Color accent = style.accentColor;
    final double pulseSize = size * 0.46 + (pulseValue * size * 0.38);
    final double pulseOpacity = (1.0 - pulseValue).clamp(0.0, 1.0);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (pulseValue > 0)
          Opacity(
            opacity: pulseOpacity * 0.50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
                border: Border.all(
                  color: accent.withValues(alpha: 0.46),
                  width: 2,
                ),
              ),
              child: SizedBox.square(dimension: pulseSize),
            ),
          ),
        if (style.showsHeadingCone)
          Transform.rotate(
            angle: bearing * math.pi / 180.0,
            child: CustomPaint(
              size: Size(size * 0.68, size * 0.68),
              painter: _HeadingConePainter(
                color: accent.withValues(alpha: isActive ? 0.30 : 0.14),
              ),
            ),
          ),
        if (style == LocationPuckStyle.earner)
          _EarnerHalo(size: size, accent: accent),
        _CoreDot(
          style: style,
          size: size,
          accent: accent,
          isActive: isActive,
        ),
        if (style.showsSpeedBadge)
          Positioned(
            bottom: -3,
            child: _SpeedBadge(
              speed: speed,
              accent: accent,
            ),
          ),
      ],
    );
  }
}

class _CoreDot extends StatelessWidget {
  const _CoreDot({
    required this.style,
    required this.size,
    required this.accent,
    required this.isActive,
  });

  final LocationPuckStyle style;
  final double size;
  final Color accent;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final bool minimal = style == LocationPuckStyle.minimalDot;
    final bool earner = style == LocationPuckStyle.earner;
    final double dotSize = minimal ? size * 0.30 : size * 0.40;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: earner ? accent : Colors.white,
        border: Border.all(
          color: minimal ? Colors.black : accent,
          width: minimal ? 2 : 4,
        ),
        boxShadow: isActive
            ? <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.42),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Colors.black45,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Center(
        child: earner
            ? const Icon(
                CupertinoIcons.money_dollar,
                color: Color(0xFF111827),
                size: 15,
              )
            : Container(
                width: minimal ? size * 0.12 : size * 0.16,
                height: minimal ? size * 0.12 : size * 0.16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: style.centerColor,
                ),
              ),
      ),
    );
  }
}

class _VehiclePuck extends StatelessWidget {
  const _VehiclePuck({
    required this.size,
    required this.bearing,
    required this.accent,
    required this.speed,
    required this.showSpeedBadge,
    required this.isActive,
  });

  final double size;
  final double bearing;
  final Color accent;
  final int speed;
  final bool showSpeedBadge;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        Transform.rotate(
          angle: bearing * math.pi / 180.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size * 0.48,
            height: size * 0.48,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(size * 0.18),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: isActive
                  ? <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 20,
                      ),
                      const BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: const Icon(
              CupertinoIcons.arrow_up,
              color: Colors.white,
              size: 21,
            ),
          ),
        ),
        if (showSpeedBadge)
          Positioned(
            bottom: -3,
            child: _SpeedBadge(
              speed: speed,
              accent: accent,
            ),
          ),
      ],
    );
  }
}

class _NavigatorPuck extends StatelessWidget {
  const _NavigatorPuck({
    required this.size,
    required this.bearing,
    required this.accent,
    required this.speed,
    required this.isActive,
    required this.pulseValue,
  });

  final double size;
  final double bearing;
  final Color accent;
  final int speed;
  final bool isActive;
  final double pulseValue;

  @override
  Widget build(BuildContext context) {
    final double pulseOpacity = (1.0 - pulseValue).clamp(0.0, 1.0);
    final double pulseSize = size * 0.54 + (pulseValue * size * 0.36);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (pulseValue > 0)
          Opacity(
            opacity: pulseOpacity * 0.36,
            child: Container(
              width: pulseSize,
              height: pulseSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: 0.62),
                  width: 2,
                ),
              ),
            ),
          ),
        Transform.rotate(
          angle: bearing * math.pi / 180.0,
          child: CustomPaint(
            size: Size(size * 0.72, size * 0.72),
            painter: _NavigatorArrowPainter(
              color: accent,
              shadowColor: accent.withValues(alpha: isActive ? 0.46 : 0.18),
            ),
          ),
        ),
        Positioned(
          bottom: -3,
          child: _SpeedBadge(speed: speed, accent: accent),
        ),
      ],
    );
  }
}

class _EarnerHalo extends StatelessWidget {
  const _EarnerHalo({
    required this.size,
    required this.accent,
  });

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: SizedBox.square(dimension: size * 0.60),
    );
  }
}

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({
    required this.speed,
    required this.accent,
  });

  final int speed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      alignment: Alignment.center,
      child: IgnorePointer(
        child: Text(
          speed.toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            fontFeatures: <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  const _HeadingConePainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Offset center = Offset(size.width / 2, size.height / 2);
    final ui.Path path = ui.Path()
      ..moveTo(center.dx, center.dy - size.height * 0.55)
      ..lineTo(center.dx - size.width * 0.25, center.dy - size.height * 0.04)
      ..quadraticBezierTo(
        center.dx,
        center.dy + size.height * 0.16,
        center.dx + size.width * 0.25,
        center.dy - size.height * 0.04,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _NavigatorArrowPainter extends CustomPainter {
  const _NavigatorArrowPainter({
    required this.color,
    required this.shadowColor,
  });

  final Color color;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final Paint bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(center.dx, 0),
        Offset(center.dx, size.height),
        <Color>[Colors.white, color],
      );

    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    final ui.Path arrow = ui.Path()
      ..moveTo(center.dx, 2)
      ..lineTo(size.width - 8, size.height - 7)
      ..lineTo(center.dx, size.height * 0.72)
      ..lineTo(8, size.height - 7)
      ..close();

    canvas.drawPath(arrow, shadowPaint);
    canvas.drawPath(arrow, bodyPaint);
    canvas.drawPath(arrow, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _NavigatorArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.shadowColor != shadowColor;
  }
}
