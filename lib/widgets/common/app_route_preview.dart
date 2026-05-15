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
  });

  final List<LatLng> points;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _RoutePreviewPainter(points: points, color: color),
        ),
      ),
    );
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

    final Paint bgPaint = Paint()
      ..color = AppColors.white.withValues(alpha: 0.055);
    canvas.drawRRect(bg, bgPaint);

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
    const double pad = 14;

    Offset project(LatLng point) {
      final double x = pad + ((point.longitude - minLng) / lngRange) * (size.width - pad * 2);
      final double y = pad + ((maxLat - point.latitude) / latRange) * (size.height - pad * 2);
      return Offset(x, y);
    }

    final ui.Path path = ui.Path()..moveTo(project(points.first).dx, project(points.first).dy);
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
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}
