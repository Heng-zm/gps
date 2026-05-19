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
          showPulse: showPulse && isActive && style.usesPulseRing,
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

    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _AnimatedPuckBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.showPulse != widget.showPulse ||
        oldWidget.style != widget.style ||
        oldWidget.isActive != widget.isActive) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.showPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat();
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int safeSpeed = _safeSpeed(widget.speed);

    if (widget.style.usesVehicleBody) {
      return _VehiclePuck(
        style: widget.style,
        size: widget.size,
        bearing: widget.bearing,
        accent: widget.style.accentColor,
        speed: safeSpeed,
        showSpeedBadge: widget.style.showsSpeedBadge,
        isActive: widget.isActive,
      );
    }

    if (widget.style.usesArrowBody) {
      return AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          return _NavigatorPuck(
            style: widget.style,
            size: widget.size,
            bearing: widget.bearing,
            accent: widget.style.accentColor,
            speed: safeSpeed,
            isActive: widget.isActive,
            pulseValue: widget.showPulse ? _pulse.value : 0,
          );
        },
      );
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return _CircularPuck(
          style: widget.style,
          bearing: widget.bearing,
          speed: safeSpeed,
          size: widget.size,
          pulseValue: widget.showPulse ? _pulse.value : 0,
          isActive: widget.isActive,
        );
      },
    );
  }

  static int _safeSpeed(double value) {
    if (!value.isFinite || value < 0) return 0;
    return value.round().clamp(0, 999).toInt();
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
    final double pulseSize = size * 0.46 + (pulseValue * size * 0.42);
    final double pulseOpacity = (1.0 - pulseValue).clamp(0.0, 1.0);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (pulseValue > 0)
          Opacity(
            opacity: pulseOpacity * 0.52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.16),
                border: Border.all(
                  color: accent.withValues(alpha: 0.46),
                  width: 2,
                ),
              ),
              child: SizedBox.square(dimension: pulseSize),
            ),
          ),
        if (style == LocationPuckStyle.pulseHalo)
          _PulseHaloDecoration(size: size, accent: accent, active: isActive),
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
          _SoftHalo(size: size, accent: accent),
        if (style == LocationPuckStyle.stealth)
          _StealthRing(size: size, accent: accent, active: isActive),
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
    final bool stealth = style == LocationPuckStyle.stealth;
    final bool pulseHalo = style == LocationPuckStyle.pulseHalo;

    final double dotSize = minimal
        ? size * 0.30
        : stealth
            ? size * 0.42
            : pulseHalo
                ? size * 0.44
                : size * 0.40;

    final Color fillColor = earner
        ? accent
        : stealth
            ? const Color(0xFF111827)
            : Colors.white;

    final Color borderColor = minimal
        ? Colors.black
        : stealth
            ? Colors.white.withValues(alpha: 0.78)
            : accent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(
          color: borderColor,
          width: minimal ? 2 : 4,
        ),
        boxShadow: isActive
            ? <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: stealth ? 0.24 : 0.42),
                  blurRadius: stealth ? 12 : 18,
                  spreadRadius: stealth ? 0 : 1,
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
            : stealth
                ? Icon(
                    CupertinoIcons.moon_stars_fill,
                    color: accent,
                    size: math.max(12, size * 0.18),
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
    required this.style,
    required this.size,
    required this.bearing,
    required this.accent,
    required this.speed,
    required this.showSpeedBadge,
    required this.isActive,
  });

  final LocationPuckStyle style;
  final double size;
  final double bearing;
  final Color accent;
  final int speed;
  final bool showSpeedBadge;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final bool rider = style == LocationPuckStyle.rider;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (rider)
          _SoftHalo(size: size * 0.84, accent: accent),
        Transform.rotate(
          angle: bearing * math.pi / 180.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size * 0.48,
            height: size * 0.48,
            decoration: BoxDecoration(
              color: rider ? const Color(0xFF111827) : accent,
              borderRadius: BorderRadius.circular(
                rider ? size * 0.24 : size * 0.18,
              ),
              border: Border.all(
                color: rider ? accent : Colors.white,
                width: rider ? 3.2 : 3,
              ),
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
            child: Icon(
              rider ? CupertinoIcons.paperplane_fill : CupertinoIcons.arrow_up,
              color: rider ? accent : Colors.white,
              size: rider ? 20 : 21,
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
    required this.style,
    required this.size,
    required this.bearing,
    required this.accent,
    required this.speed,
    required this.isActive,
    required this.pulseValue,
  });

  final LocationPuckStyle style;
  final double size;
  final double bearing;
  final Color accent;
  final int speed;
  final bool isActive;
  final double pulseValue;

  @override
  Widget build(BuildContext context) {
    final bool sport = style == LocationPuckStyle.sportArrow;
    final double pulseOpacity = (1.0 - pulseValue).clamp(0.0, 1.0);
    final double pulseSize = size * 0.54 + (pulseValue * size * 0.38);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: <Widget>[
        if (pulseValue > 0)
          Opacity(
            opacity: pulseOpacity * (sport ? 0.46 : 0.36),
            child: Container(
              width: pulseSize,
              height: pulseSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accent.withValues(alpha: sport ? 0.72 : 0.62),
                  width: sport ? 2.6 : 2,
                ),
              ),
            ),
          ),
        Transform.rotate(
          angle: bearing * math.pi / 180.0,
          child: CustomPaint(
            size: Size(size * (sport ? 0.78 : 0.72), size * (sport ? 0.78 : 0.72)),
            painter: _NavigatorArrowPainter(
              color: accent,
              sport: sport,
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

class _SoftHalo extends StatelessWidget {
  const _SoftHalo({
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
            Colors.transparent,
          ],
          stops: const <double>[0.0, 0.68, 1.0],
        ),
      ),
      child: SizedBox.square(dimension: size * 0.60),
    );
  }
}

class _PulseHaloDecoration extends StatelessWidget {
  const _PulseHaloDecoration({
    required this.size,
    required this.accent,
    required this.active,
  });

  final double size;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Container(
          width: size * 0.62,
          height: size * 0.62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: active ? 0.10 : 0.05),
          ),
        ),
        Container(
          width: size * 0.48,
          height: size * 0.48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withValues(alpha: active ? 0.42 : 0.20),
              width: 2,
            ),
          ),
        ),
      ],
    );
  }
}

class _StealthRing extends StatelessWidget {
  const _StealthRing({
    required this.size,
    required this.accent,
    required this.active,
  });

  final double size;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.58,
      height: size * 0.58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.26),
        border: Border.all(
          color: accent.withValues(alpha: active ? 0.22 : 0.10),
          width: 1.4,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
          ),
        ],
      ),
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
    required this.sport,
  });

  final Color color;
  final Color shadowColor;
  final bool sport;

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
        sport
            ? <Color>[Colors.white, color, const Color(0xFF7F1D1D)]
            : <Color>[Colors.white, color],
      );

    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = sport ? 2.7 : 2.4
      ..style = PaintingStyle.stroke;

    final ui.Path arrow = sport
        ? (ui.Path()
          ..moveTo(center.dx, 1)
          ..lineTo(size.width - 6, size.height - 8)
          ..lineTo(center.dx, size.height * 0.64)
          ..lineTo(6, size.height - 8)
          ..close())
        : (ui.Path()
          ..moveTo(center.dx, 2)
          ..lineTo(size.width - 8, size.height - 7)
          ..lineTo(center.dx, size.height * 0.72)
          ..lineTo(8, size.height - 7)
          ..close());

    canvas.drawPath(arrow, shadowPaint);
    canvas.drawPath(arrow, bodyPaint);
    canvas.drawPath(arrow, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _NavigatorArrowPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.shadowColor != shadowColor ||
        oldDelegate.sport != sport;
  }
}
