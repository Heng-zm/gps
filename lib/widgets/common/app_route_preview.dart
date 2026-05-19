import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/app_theme.dart';

class AppRoutePreview extends StatelessWidget {
  const AppRoutePreview({
    super.key,
    required this.points,
    this.height = 90,
    this.color = AppColors.blueSoft,
    this.maxRenderPoints = 180,
  });

  final List<LatLng> points;
  final double height;
  final Color color;
  final int maxRenderPoints;

  @override
  Widget build(BuildContext context) {
    final List<LatLng> safePoints = _downsampleValid(points, maxRenderPoints);

    return RepaintBoundary(
      child: SizedBox(
        height: height.clamp(48.0, 240.0).toDouble(),
        width: double.infinity,
        child: CustomPaint(
          isComplex: true,
          painter: _RoutePreviewPainter(points: safePoints, color: color),
        ),
      ),
    );
  }

  static List<LatLng> _downsampleValid(List<LatLng> source, int maxPoints) {
    final List<LatLng> valid = source
        .where((LatLng point) =>
            point.latitude.isFinite &&
            point.longitude.isFinite &&
            point.latitude.abs() <= 90 &&
            point.longitude.abs() <= 180)
        .toList(growable: false);

    final int safeMax = maxPoints.clamp(16, 600).toInt();
    if (valid.length <= safeMax) return valid;

    return List<LatLng>.generate(safeMax, (int index) {
      final int sourceIndex =
          ((index / (safeMax - 1)) * (valid.length - 1)).round();
      return valid[sourceIndex];
    }, growable: false);
  }
}

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter({
    required this.points,
    required this.color,
  });

  final List<LatLng> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );

    canvas.drawRRect(
      bg,
      Paint()..color = AppColors.white.withValues(alpha: 0.055),
    );

    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final LatLng point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final double latRange = math.max(0.000001, maxLat - minLat);
    final double lngRange = math.max(0.000001, maxLng - minLng);
    const double pad = 14.0;

    Offset project(LatLng point) {
      final double x =
          pad + ((point.longitude - minLng) / lngRange) * (size.width - pad * 2);
      final double y =
          pad + ((maxLat - point.latitude) / latRange) * (size.height - pad * 2);
      return Offset(x, y);
    }

    final Offset firstPoint = project(points.first);
    final ui.Path path = ui.Path()..moveTo(firstPoint.dx, firstPoint.dy);
    for (int i = 1; i < points.length; i++) {
      final Offset p = project(points[i]);
      path.lineTo(p.dx, p.dy);
    }

    final Paint glow = Paint()
      ..color = color.withValues(alpha: 0.22)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glow);

    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);

    final Paint dot = Paint()..color = color;
    canvas.drawCircle(project(points.first), 3.5, dot);
    canvas.drawCircle(project(points.last), 4.0, dot);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.points != points;
  }
}
