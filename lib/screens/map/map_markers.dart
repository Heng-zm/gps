// ignore_for_file: unused_element, prefer_const_constructors

part of 'map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAP MARKERS
// ─────────────────────────────────────────────────────────────────────────────

extension _MapScreenMarkerMethods on _MapScreenState {
  // ───────────────────────────────────────────────────────────────────────────
  // MARKERS
  // ───────────────────────────────────────────────────────────────────────────

  List<fm.Marker> _buildMarkers() {
    if (_route.validPoints.isEmpty) return const <fm.Marker>[];

    final List<fm.Marker> markers = <fm.Marker>[
      _startMarker(_route.validPoints.first.position),
    ];

    if (!widget.isLive && _route.validPoints.length > 1) {
      markers.add(_endMarker(_route.validPoints.last.position));
      final int safeReplayIndex =
          _replayIndex.clamp(0, _route.validPoints.length - 1);
      markers.add(_replayMarker(_route.validPoints[safeReplayIndex].position));
    } else if (widget.isLive) {
      markers.add(_liveMarker(_route.validPoints.last.position));
    }

    if (_showSpeedGradient && _route.validPoints.length > 10) {
      final int step =
          (_route.validPoints.length / 8).ceil().clamp(25, 80).toInt();
      for (int i = step; i < _route.validPoints.length - 2; i += step) {
        markers.add(_speedTagMarker(_route.validPoints[i]));
      }
    }

    if (_route.peakSpeedIndex >= 0 &&
        _route.peakSpeedIndex < _route.validPoints.length &&
        _route.maxSpeedKmh > 5) {
      markers.add(_peakSpeedMarker(_route.validPoints[_route.peakSpeedIndex]));
    }

    return markers;
  }

  fm.Marker _startMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 36,
      height: 36,
      child: const _RouteMarkerDot(
        color: _kBlueSoft,
        icon: CupertinoIcons.flag_fill,
        glowColor: _kBlueSoft,
      ),
    );
  }

  fm.Marker _endMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 42,
      height: 42,
      alignment: Alignment.center,
      child: const _WhiteRouteNode(),
    );
  }

  fm.Marker _replayMarker(LatLng position) {
    final int safeIndex = _replayIndex.clamp(0, _route.validPoints.length - 1);
    final double bearing = safeIndex > 0
        ? _bearingOrZero(
            _route.validPoints[safeIndex - 1].position,
            _route.validPoints[safeIndex].position,
          )
        : _route.currentBearing;

    return fm.Marker(
      point: position,
      width: 96,
      height: 96,
      alignment: Alignment.center,
      child: _MapVehicleMarker(
        bearing: bearing,
        kind: _MapVehicleKind.car,
        pulseController: _markerPulseController,
      ),
    );
  }

  fm.Marker _liveMarker(LatLng position) {
    return fm.Marker(
      point: position,
      width: 96,
      height: 96,
      alignment: Alignment.center,
      child: _MapLocationPuck(
        bearing: _route.currentBearing,
        pulseController: _markerPulseController,
      ),
    );
  }

  fm.Marker _speedTagMarker(TripPoint point) {
    final Color color = _speedColor(point.speedKmh);
    return fm.Marker(
      point: point.position,
      width: 44,
      height: 24,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Text(
          point.speedKmh.toStringAsFixed(0),
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  fm.Marker _peakSpeedMarker(TripPoint point) {
    return fm.Marker(
      point: point.position,
      width: 78,
      height: 30,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[_kBlueSoft, _kBlue],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _kBlue.withValues(alpha: 0.5),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(CupertinoIcons.bolt_fill, color: Colors.black, size: 10),
            const SizedBox(width: 3),
            Text(
              '${point.speedKmh.toStringAsFixed(0)} peak',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _MapLocationPuck extends StatelessWidget {
  const _MapLocationPuck({
    required this.bearing,
    required this.pulseController,
  });

  final double bearing;
  final Animation<double> pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) {
        final double pulse = pulseController.value;
        final double pulseOpacity = (1.0 - pulse).clamp(0.0, 1.0);

        return SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBlue.withValues(alpha: 0.10),
                  border: Border.all(
                    color: _kBlue.withValues(alpha: 0.18),
                    width: 1.2,
                  ),
                ),
              ),
              Opacity(
                opacity: pulseOpacity * 0.34,
                child: Container(
                  width: 24 + pulse * 44,
                  height: 24 + pulse * 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kBlue,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.40),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              Transform.rotate(
                angle: bearing * math.pi / 180.0,
                child: CustomPaint(
                  size: const Size(74, 74),
                  painter: _MapLocationConePainter(
                    color: _kBlue,
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBlue,
                  border: Border.all(
                    color: Colors.white,
                    width: 3.2,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kBlue.withValues(alpha: 0.45),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: bearing * math.pi / 180.0,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 42),
                  child: Icon(
                    CupertinoIcons.location_fill,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapLocationConePainter extends CustomPainter {
  const _MapLocationConePainter({
    required this.color,
  });

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);
    final double radius = size.width * 0.42;

    final ui.Path cone = ui.Path()
      ..moveTo(center.dx, center.dy - radius)
      ..cubicTo(
        center.dx - radius * 0.35,
        center.dy - radius * 0.28,
        center.dx - radius * 0.22,
        center.dy - radius * 0.04,
        center.dx,
        center.dy,
      )
      ..cubicTo(
        center.dx + radius * 0.22,
        center.dy - radius * 0.04,
        center.dx + radius * 0.35,
        center.dy - radius * 0.28,
        center.dx,
        center.dy - radius,
      )
      ..close();

    final Paint paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        <Color>[
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.00),
        ],
        <double>[0.0, 1.0],
      );

    canvas.drawPath(cone, paint);
  }

  @override
  bool shouldRepaint(covariant _MapLocationConePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

enum _MapVehicleKind {
  car,
  motorbike,
}

class _MapVehicleMarker extends StatelessWidget {
  const _MapVehicleMarker({
    required this.bearing,
    required this.kind,
    required this.pulseController,
  });

  final double bearing;
  final _MapVehicleKind kind;
  final Animation<double> pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (_, __) {
        final double pulse = pulseController.value;
        final double opacity = (1.0 - pulse).clamp(0.0, 1.0);
        return SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              RepaintBoundary(
                child: Container(
                  width: 32 + pulse * 28,
                  height: 32 + pulse * 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kBlue
                        .withValues(alpha: opacity * 0.18),
                    border: Border.all(
                      color: _kBlue
                          .withValues(alpha: opacity * 0.34),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.92),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.rotate(
                angle: bearing * math.pi / 180.0,
                child: Transform.translate(
                  offset: const Offset(0, -10),
                  child: kind == _MapVehicleKind.motorbike
                      ? const _MapMiniMotorbike()
                      : const _MapMiniCar(),
                ),
              ),
              Positioned(
                bottom: 18,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapMiniCar extends StatelessWidget {
  const _MapMiniCar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            bottom: 4,
            child: Container(
              width: 38,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            bottom: 13,
            child: Container(
              width: 38,
              height: 43,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.white, Color(0xFFE8EDF6)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(0xFFCAD3DF), width: 1.2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 9,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 16,
            child: Container(
              width: 25,
              height: 14,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF88C7F5), Color(0xFF2E6A99)],
                ),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white, width: 1.0),
              ),
            ),
          ),
          const Positioned(bottom: 20, left: 5, child: _MapVehicleWheel()),
          const Positioned(bottom: 20, right: 5, child: _MapVehicleWheel()),
          const Positioned(bottom: 13, left: 7, child: _MapTailLight()),
          const Positioned(bottom: 13, right: 7, child: _MapTailLight()),
        ],
      ),
    );
  }
}

class _MapMiniMotorbike extends StatelessWidget {
  const _MapMiniMotorbike();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            bottom: 2,
            child: Container(
              width: 40,
              height: 15,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const Positioned(bottom: 10, child: _MapBikeWheel(size: 20)),
          const Positioned(top: 23, child: _MapBikeWheel(size: 18)),
          Positioned(
            top: 31,
            child: Container(
              width: 24,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF1F2329),
                borderRadius: BorderRadius.circular(8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 25,
            child: Container(
              width: 32,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFD8DEE8)),
              ),
            ),
          ),
          Positioned(
            top: 11,
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapVehicleWheel extends StatelessWidget {
  const _MapVehicleWheel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E23),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MapTailLight extends StatelessWidget {
  const _MapTailLight();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _MapBikeWheel extends StatelessWidget {
  const _MapBikeWheel({
    required this.size,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF15171B),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF40464F), width: 3),
      ),
    );
  }
}

class _WhiteRouteNode extends StatelessWidget {
  const _WhiteRouteNode();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 31,
      height: 31,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 3.2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEARING ARROW PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class _BearingArrowPainter extends CustomPainter {
  const _BearingArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2.0;
    final double cy = size.height / 2.0;

    canvas.drawPath(
      ui.Path()
        ..moveTo(cx, cy - 16)
        ..lineTo(cx - 6, cy + 2)
        ..lineTo(cx, cy - 2)
        ..lineTo(cx + 6, cy + 2)
        ..close(),
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _BearingArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// LATLNG TWEEN
// ─────────────────────────────────────────────────────────────────────────────

